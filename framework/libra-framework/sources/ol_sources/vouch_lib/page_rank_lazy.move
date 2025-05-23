module ol_framework::page_rank_lazy {
    use std::error;
    use std::signer;
    use std::timestamp;
    use std::vector;
    use ol_framework::vouch;
    use ol_framework::root_of_trust;

    friend ol_framework::vouch_txs;
    friend ol_framework::founder;
    friend ol_framework::vouch_limits;

    #[test_only]
    friend ol_framework::test_page_rank;
    #[test_only]
    friend ol_framework::mock;

    //////// ERROR CODES ////////
    /// trust record not initialized
    const ENOT_INITIALIZED: u64 = 2;

    /// max addresses processed
    const EMAX_PROCESSED_ADDRESSES: u64 = 3;

    //////// CONSTANTS ////////
    /// Maximum score that can be assigned to a single vouch.
    /// This provides an upper bound on direct trust from a single source.
    const MAX_VOUCH_SCORE: u64 = 100_000;

    /// Circuit breaker to prevent stack overflow during recursive graph traversal.
    /// Limits the total number of nodes processed in a single traversal.
    const MAX_PROCESSED_ADDRESSES: u64 = 10_000;

    /// Maximum depth for path traversal in the trust graph.
    /// This limits how far the algorithm will search from a root node.
    const MAX_PATH_DEPTH: u64 = 6;

    /// Per-user trust record - each user stores their own trust data
    /// This resource tracks a user's cached trust score and staleness state.
    struct UserTrustRecord has key, drop {
        /// Cached trust score - computed by traversing the trust graph
        cached_score: u64,
        /// When the score was last computed (timestamp in seconds)
        score_computed_at_timestamp: u64,
        /// Whether this node's trust data is stale and needs recalculation
        /// Set to true when the trust graph changes in a way that affects this user
        is_stale: bool,
        // Shortest path to root now handled in a separate module
    }

    /// Initialize a user trust record if it doesn't exist.
    /// This creates the basic structure needed to track a user's trust score.
    public fun maybe_initialize_trust_record(account: &signer) {
        let addr = signer::address_of(account);
        if (!exists<UserTrustRecord>(addr)) {
            move_to(account, UserTrustRecord {
                cached_score: 0,
                score_computed_at_timestamp: 0,
                is_stale: true,
            });
        };
    }


    /// Calculate or retrieve cached trust score for an address.
    /// Returns the cached score if it's valid, or recalculates if stale.
    ///
    /// This function uses an optimized page rank algorithm that:
    /// 1. Finds all possible paths from roots of trust to the target
    /// 2. Accumulates scores from all valid paths, including diamond patterns
    /// 3. Applies trust decay proportional to distance from roots
    ///
    /// The calculation considers the entire trust graph and properly handles:
    /// - Multiple paths to the same target
    /// - Branching and merging paths
    /// - Root-of-trust special cases
    public(friend) fun get_trust_score(addr: address): u64 acquires UserTrustRecord {

        // If user has no trust record, they have no score
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));

        // If we've calculated the score recently
        // and it's not stale, return the cached score
        let user_record = borrow_global<UserTrustRecord>(addr);
        if (!user_record.is_stale) {
            return user_record.cached_score
        };
        set_score(addr)
    }

    /// Always calculate and update the trust score for an address.
    /// This function:
    /// 1. Gets the current roots of trust
    /// 2. Traverses the graph to compute the score using our page rank algorithm
    /// 3. Updates the user's cached score and marks it as fresh
    ///
    /// This is an expensive operation that should be used judiciously.
    fun set_score(addr: address): u64 acquires UserTrustRecord {
        // If user has no trust record, they have no score
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        // Cache is stale or expired - compute fresh score
        // Default roots to system account if no registry
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        // Compute score using selected algorithm
        let (score, _, _) = traverse_graph(&roots, addr, MAX_PATH_DEPTH);
        // Update the cache
        let user_record_mut = borrow_global_mut<UserTrustRecord>(addr);
        user_record_mut.cached_score = score;
        user_record_mut.score_computed_at_timestamp = timestamp::now_seconds();
        user_record_mut.is_stale = false;

        score
    }

    /// Simplified graph traversal that finds all valid paths from each root of trust to the target address.
    /// This function iterates through each root in the provided list and accumulates scores from all
    /// paths that lead to the target.
    ///
    /// For each root, it:
    /// 1. Creates a new empty visited set to track paths independently
    /// 2. Calculates the score contribution via walk_from_node, which explores all possible paths
    /// 3. Adds the score to the total accumulation
    ///
    /// The total accumulated score represents the combined trust value from all roots to the target.
    fun traverse_graph(
        roots: &vector<address>,
        target: address,
        max_depth: u64,
    ): (u64, u64, u64) {
        let total_score = 0;
        let root_idx = 0;
        let roots_len = vector::length(roots);
        let processed_count: u64 = 0; // Track total processed nodes globally
        let max_depth_reached: u64 = 0; // Track the maximum depth reached across all paths

        // For each root, calculate its contribution independently
        while (root_idx < roots_len) {
            // Check if the global limit for processed nodes has been reached
            assert!(processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));

            let root = *vector::borrow(roots, root_idx);
            let visited = vector::empty<address>();
            if (root != target) {
                let (root_score, root_max_depth) = walk_from_node(
                    root, target, &mut visited, 2 * MAX_VOUCH_SCORE, 0, &mut processed_count, max_depth
                );
                total_score = total_score + root_score;
                // Update the global maximum depth reached
                if (root_max_depth > max_depth_reached) {
                    max_depth_reached = root_max_depth;
                };
            };
            root_idx = root_idx + 1;
        };
        (total_score, max_depth_reached, processed_count)
    }

    /// Advanced graph traversal algorithm that finds and accumulates scores from all valid paths
    /// from a starting node to a target. This function follows these principles:
    ///
    /// 1. Cycle Detection: Uses the visited set to avoid revisiting nodes already in the current path.
    /// 2. Path Independence: Creates a copy of the visited set for each branch, ensuring separate paths
    ///    are explored independently.
    /// 3. Score Accumulation: Accumulates scores from all valid and unique paths rather than only
    ///    returning the maximum score. This ensures "diamond patterns" (where multiple paths lead to
    ///    the same target) properly accumulate their trust contributions.
    /// 4. Trust Decay: Implements a 50% power reduction per hop, representing diminishing trust
    ///    with distance from the source.
    /// 5. Special Root Handling: Prevents accumulation from interconnected root accounts to avoid
    ///    artificial score inflation.
    /// 6. Depth Limiting: Restricts traversal to a maximum path depth to prevent excessive recursion.
    ///
    /// The algorithm handles complex trust graphs including branching paths, merging paths
    /// (diamond patterns), and multiple routes from roots to targets.
    ///
    /// Returns (score, max_depth_reached)
    fun walk_from_node(
        current: address,
        target: address,
        visited: &mut vector<address>,
        current_power: u64,
        current_depth: u64,
        processed_count: &mut u64,
        max_depth: u64
    ): (u64, u64) {
        // Early terminations that don't consume processing budget
        if (current_depth >= max_depth) return (0, current_depth);
        if (vector::contains(visited, &current)) return (0, current_depth);
        if (!vouch::is_init(current)) return (0, current_depth);
        if (current_power < 2) return (0, current_depth);
        if (current == target) return (current_power, current_depth);

        // Budget check and consumption
        assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));
        *processed_count = *processed_count + 1;

        let (neighbors, _) = vouch::get_given_vouches(current);
        let neighbor_count = vector::length(&neighbors);

        if (neighbor_count == 0) return (0, current_depth);

        let total_score = 0;
        let max_depth_reached = current_depth;

        // Direct connection check
        if (vector::contains(&neighbors, &target) && current_depth + 1 < max_depth) {
            total_score = total_score + (current_power / 2);
            // Update max depth for direct connection
            let direct_depth = current_depth + 1;
            if (direct_depth > max_depth_reached) {
                max_depth_reached = direct_depth;
            };
        };

        let next_power = current_power / 2;

        // Special case for root-to-root vouching
        if (
          root_of_trust::is_root_at_registry(@diem_framework, current) &&
          root_of_trust::is_root_at_registry(@diem_framework, target) &&
          current != target &&
          vector::contains(&neighbors, &target)
        ) {
            vector::push_back(visited, current);
            return (next_power, current_depth + 1)
        };

        // Add current to visited and explore neighbors
        vector::push_back(visited, current);
        let next_depth = current_depth + 1;

        // Explore all neighbors without artificial limits
        let i = 0;
        while (i < neighbor_count) {
            assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));

            let neighbor = *vector::borrow(&neighbors, i);
            if (!vector::contains(visited, &neighbor) && neighbor != target) {
                if (!root_of_trust::is_root_at_registry(@diem_framework, neighbor)) {
                    let visited_copy = *visited;
                    let (path_score, path_max_depth) = walk_from_node(
                        neighbor,
                        target,
                        &mut visited_copy,
                        next_power,
                        next_depth,
                        processed_count,
                        max_depth
                    );
                    total_score = total_score + path_score;
                    // Update max depth reached
                    if (path_max_depth > max_depth_reached) {
                        max_depth_reached = path_max_depth;
                    };
                };
            };
            i = i + 1;
        };
        (total_score, max_depth_reached)
    }

    /// Mark a user's trust score as stale, propagating the staleness to impacted downstream accounts.
    /// This function performs a controlled graph traversal to identify all accounts that may
    /// need to have their trust scores recalculated due to changes in the vouch graph.
    ///
    /// Uses cycle detection and a maximum node limit to prevent infinite recursion or DOS attacks.
    public(friend) fun mark_as_stale(user: address) acquires UserTrustRecord {
        let visited = vector::empty<address>();
        let processed_count: u64 = 0; // Initialize as a mutable local variable
        walk_stale(user, &mut visited, &mut processed_count); // Pass as a mutable reference
    }

    /// Internal helper function with cycle detection for marking nodes as stale
    /// Uses vouch module to get outgoing vouches and implements optimizations to reduce
    /// the number of nodes processed:
    ///
    /// 1. Cycle detection to avoid revisiting nodes
    /// 2. Process limit to prevent excessive recursion
    /// 3. Efficient traversal that prioritizes direct dependencies
    fun walk_stale(
        user: address,
        visited: &mut vector<address>,
        processed_count: &mut u64 // Changed to mutable reference
    ) acquires UserTrustRecord {
        // Skip if we've already visited this node in the current traversal (cycle detection)
        // This also ensures we only count/process each unique node once.
        if (vector::contains(visited, &user)) {
            return
        };

        // Check if the global limit for processed nodes has been reached *before* processing this one.
        // If *processed_count is already at the limit, we can't process another new node.
        assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));

        // This node is new and will be processed. Increment the global count.
        *processed_count = *processed_count + 1;

        // Process the current 'user' node:
        // 1. Mark its UserTrustRecord as stale if it exists.
        if (exists<UserTrustRecord>(user)) {
            let record = borrow_global_mut<UserTrustRecord>(user);
            record.is_stale = true;
        };

        // 2. Add this node to the visited set for the current traversal.
        vector::push_back(visited, user);

        // If the user is not initialized in the vouch system, they cannot have outgoing vouches.
        // Staleness propagation stops here for this path, but 'user' itself has been processed and counted.
        if (!vouch::is_init(user)) {
            return
        };

        // Now walk their outgoing vouches
        let (outgoing_vouches, _) = vouch::get_given_vouches(user);
        if (vector::length(&outgoing_vouches) == 0) {
            return
        };

        // Recursively process downstream addresses
        let i = 0;
        let len = vector::length(&outgoing_vouches);
        while (i < len) {
            // Check again if we've hit the processing limit
            assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));

            let each_vouchee = vector::borrow(&outgoing_vouches, i);
            // Pass the same mutable reference to processed_count.
            // The checks at the beginning of the recursive call (visited and limit)
            // will handle whether to proceed for 'each_vouchee'.
            walk_stale(*each_vouchee, visited, processed_count);
            i = i + 1;
        };
    }

    //////// CACHE ////////

    /// Refresh the cache
    /// state updates must be called by a user.
    /// Vouch tree updates could be a DDOS vector
    public entry fun refresh_cache(user: address) acquires UserTrustRecord{
      // assert initialized
      assert!(exists<UserTrustRecord>(user), error::invalid_state(ENOT_INITIALIZED));
      // get_score
      let _score = set_score(user);
    }

    //////// GETTERS ////////
    #[view]
    /// Get the cached trust score for a user
    public fun get_cached_score(addr: address): u64 acquires UserTrustRecord {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let record = borrow_global<UserTrustRecord>(addr);
        record.cached_score
    }

    #[view]
    /// Calculates a fresh trust score for a user without updating the cache.
    /// Returns (score, max_depth_reached, accounts_processed).
    /// Intended for diagnostics and testing only.
    public fun calculate_score(addr: address): (u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        // Cache is stale or expired - compute fresh score
        // Default roots to system account if no registry
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        // Compute score using selected algorithm
        let (score, max_depth_reached, processed_count) = traverse_graph(&roots, addr, MAX_PATH_DEPTH);
        (score, max_depth_reached, processed_count)
    }

    #[view]
    /// Calculates a fresh trust score for a user without updating the cache.
    /// Returns (score, max_depth_reached, accounts_processed).
    /// Intended for diagnostics and testing only.
    public fun calculate_score_depth(addr: address, max_depth: u64): (u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        // Cache is stale or expired - compute fresh score
        // Default roots to system account if no registry
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        // Compute score using selected algorithm
        let (score, max_depth_reached, processed_count) = traverse_graph(&roots, addr, max_depth);
        (score, max_depth_reached, processed_count)
    }

    #[view]
    // check if it's stale
    public fun is_stale(addr: address): bool acquires UserTrustRecord {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let record = borrow_global<UserTrustRecord>(addr);
        record.is_stale
    }

    #[view]
    // get the const for highest vouch score
    public fun get_max_single_score(): u64 {
        MAX_VOUCH_SCORE
    }

    //////// TEST HELPERS ///////

    #[test_only]
    public fun setup_mock_trust_network(
        admin: &signer,
        root: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer
    ) {

        root_of_trust::framework_migration(admin, vector[signer::address_of(root)], 1, 1000);
        // Initialize trust records for all accounts
        maybe_initialize_trust_record(root);
        maybe_initialize_trust_record(user1);
        maybe_initialize_trust_record(user2);
        maybe_initialize_trust_record(user3);

        // Ensure full initialization of vouch structures for all accounts
        // The init function should create both ReceivedVouches and GivenVouches structures
        vouch::init(root);
        vouch::init(user1);
        vouch::init(user2);
        vouch::init(user3);

        // Verify that all resources are initialized correctly before proceeding
        assert!(vouch::is_init(signer::address_of(root)), 99);
        assert!(vouch::is_init(signer::address_of(user1)), 99);
        assert!(vouch::is_init(signer::address_of(user2)), 99);
        assert!(vouch::is_init(signer::address_of(user3)), 99);

        // Initialize ancestry for test accounts to ensure they're unrelated
        ol_framework::ancestry::test_fork_migrate(
            admin,
            root,
            vector::empty<address>()
        );

        ol_framework::ancestry::test_fork_migrate(
            admin,
            user1,
            vector::empty<address>()
        );

        ol_framework::ancestry::test_fork_migrate(
            admin,
            user2,
            vector::empty<address>()
        );

        ol_framework::ancestry::test_fork_migrate(
            admin,
            user3,
            vector::empty<address>()
        );

        // Get addresses we need
        let root_addr = signer::address_of(root);
        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let user3_addr = signer::address_of(user3);

        // Use direct setting of vouching relationships instead of vouch_txs
        // This avoids dependencies on other modules for testing

        // 1. Setup ROOT -> USER1 and ROOT -> USER2 vouching relationships
        let root_gives = vector::empty<address>();
        vector::push_back(&mut root_gives, user1_addr);
        vector::push_back(&mut root_gives, user2_addr);

        let user1_receives = vector::empty<address>();
        vector::push_back(&mut user1_receives, root_addr);

        let user2_receives = vector::empty<address>();
        vector::push_back(&mut user2_receives, root_addr);

        vouch::test_set_both_lists(root_addr, vector::empty(), root_gives);
        vouch::test_set_both_lists(user1_addr, user1_receives, vector::empty());
        vouch::test_set_both_lists(user2_addr, user2_receives, vector::empty());

        // 2. Setup USER2 -> USER3 vouching relationship
        let user2_gives = vector::empty<address>();
        vector::push_back(&mut user2_gives, user3_addr);

        let user3_receives = vector::empty<address>();
        vector::push_back(&mut user3_receives, user2_addr);

        vouch::test_set_both_lists(user2_addr, user2_receives, user2_gives);
        vouch::test_set_both_lists(user3_addr, user3_receives, vector::empty());
    }
}
