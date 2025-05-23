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
    friend ol_framework::test_page_rank_bfs;
    #[test_only]
    friend ol_framework::mock;

    //////// ERROR CODES ////////
    /// Thrown if a trust record is missing for the user.
    const ENOT_INITIALIZED: u64 = 2;

    /// Thrown if the maximum number of nodes to process is exceeded.
    const EMAX_PROCESSED_ADDRESSES: u64 = 3;

    //////// CONSTANTS ////////
    /// Maximum score assignable for a single vouch (upper bound for direct trust).
    const MAX_VOUCH_SCORE: u64 = 100_000;

    /// Maximum number of nodes processed in a single traversal (prevents stack overflow).
    const MAX_PROCESSED_ADDRESSES: u64 = 10_000;

    /// Maximum allowed depth for trust graph traversal.
    const MAX_PATH_DEPTH: u64 = 5;

    /// Stores a user's trust score and its staleness state.
    struct UserTrustRecord has key, drop {
        /// Last computed trust score for this user.
        cached_score: u64,
        /// Timestamp (seconds) when the score was last computed.
        score_computed_at_timestamp: u64,
        /// True if the trust score is outdated and needs recalculation.
        is_stale: bool,
        // Shortest path to root is managed in a separate module.
    }

    /// Initializes a trust record for the account if it does not already exist.
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


    /// Returns the cached trust score for an address, or recalculates it if stale.
    /// Uses a reverse PageRank-like algorithm to aggregate trust from roots.
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

    /// Recalculates and updates the trust score for an address.
    /// Traverses the trust graph from roots to the target and updates the cache.
    /// This is a costly operation and should be used sparingly.
    fun set_score(addr: address): u64 acquires UserTrustRecord {
        // If user has no trust record, they have no score
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        // Cache is stale or expired - compute fresh score
        // Default roots to system account if no registry
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        // Compute score using selected algorithm
        let processed_count: u64 = 0;
        let max_depth_reached: u64 = 0;
        let visited = vector::empty<address>();
        let score = walk_backwards_from_target_with_stats(
            addr, &roots, &mut visited, 2 * MAX_VOUCH_SCORE, 0, &mut processed_count, &mut max_depth_reached, MAX_PATH_DEPTH
        );
        // Update the cache
        let user_record_mut = borrow_global_mut<UserTrustRecord>(addr);
        user_record_mut.cached_score = score;
        user_record_mut.score_computed_at_timestamp = timestamp::now_seconds();
        user_record_mut.is_stale = false;

        score
    }

    /// Walks backwards from the target toward roots of trust, accumulating trust score.
    /// - Starts from the target user.
    /// - Uses received vouches for traversal.
    /// - Accumulates score when reaching a root.
    /// - Avoids cycles and dead ends.
    /// - Applies trust decay and limits neighbor exploration to control complexity.
    fun walk_backwards_from_target_with_stats(
        current: address,
        roots: &vector<address>,
        visited: &mut vector<address>,
        current_power: u64,
        current_depth: u64,
        processed_count: &mut u64,
        max_depth_reached: &mut u64,
        max_depth: u64
    ): u64 {
        // Track maximum depth reached
        if (current_depth > *max_depth_reached) {
            *max_depth_reached = current_depth;
        };

        // Early terminations that don't consume processing budget
        if (current_depth >= max_depth) return 0;
        if (vector::contains(visited, &current)) return 0;
        if (!vouch::is_init(current)) return 0;
        if (current_power < 2) return 0;

        // Check if we've reached a root of trust - this is our success condition!
        if (vector::contains(roots, &current) && current_depth > 0) {
            return current_power
        };

        // Budget check and consumption
        assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));
        *processed_count = *processed_count + 1;

        // Get who vouched FOR this current user (backwards direction)
        let (received_from, _) = vouch::get_received_vouches(current);
        let neighbor_count = vector::length(&received_from);

        if (neighbor_count == 0) return 0;

        let total_score = 0;
        let next_power = current_power / 2;
        let next_depth = current_depth + 1;

        // Add current to visited and explore received vouches (backwards)
        vector::push_back(visited, current);

        let i = 0;

        while (i < neighbor_count) {
            assert!(*processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));

            let neighbor = *vector::borrow(&received_from, i);
            if (!vector::contains(visited, &neighbor)) {
                let visited_copy = *visited;
                let path_score = walk_backwards_from_target_with_stats(
                    neighbor,
                    roots,
                    &mut visited_copy,
                    next_power,
                    next_depth,
                    processed_count,
                    max_depth_reached,
                    max_depth
                );
                total_score = total_score + path_score;
            };
            i = i + 1;
        };

        total_score
    }

    /// Breadth-first alternative to walk_backwards_from_target_with_stats.
    /// Uses a queue-based approach instead of recursion to traverse the trust graph.
    /// - Starts from the target user and explores level by level.
    /// - Uses received vouches for traversal (backwards direction).
    /// - Accumulates score when reaching roots.
    /// - Avoids cycles and implements processing limits.
    fun walk_backwards_from_target_bfs(
        target: address,
        roots: &vector<address>,
        max_depth: u64
    ): (u64, u64, u64) {
        // BFS data structures - we track paths, not just nodes
        let queue = vector::empty<address>();
        let depths = vector::empty<u64>();
        let powers = vector::empty<u64>();
        let path_visited = vector::empty<vector<address>>(); // Track visited nodes per path

        // Statistics tracking
        let processed_count: u64 = 0;
        let max_depth_reached: u64 = 0;
        let total_score: u64 = 0;

        // Initialize queue with target
        vector::push_back(&mut queue, target);
        vector::push_back(&mut depths, 0);
        vector::push_back(&mut powers, 2 * MAX_VOUCH_SCORE);
        vector::push_back(&mut path_visited, vector::empty<address>());

        while (!vector::is_empty(&queue)) {
            // Circuit breaker
            assert!(processed_count < MAX_PROCESSED_ADDRESSES, error::invalid_state(EMAX_PROCESSED_ADDRESSES));
            processed_count = processed_count + 1;

            // Dequeue current node and its path
            let current = vector::remove(&mut queue, 0);
            let current_depth = vector::remove(&mut depths, 0);
            let current_power = vector::remove(&mut powers, 0);
            let current_visited = vector::remove(&mut path_visited, 0);

            // Track maximum depth reached
            if (current_depth > max_depth_reached) {
                max_depth_reached = current_depth;
            };

            // Early terminations
            if (current_depth >= max_depth) continue;
            if (vector::contains(&current_visited, &current)) continue; // Cycle detection for this path
            if (!vouch::is_init(current)) continue;
            if (current_power < 2) continue;

            // Check if we've reached a root of trust
            if (vector::contains(roots, &current) && current_depth > 0) {
                total_score = total_score + current_power;
                continue // Found a root, continue exploring other paths
            };

            // Add current to this path's visited list
            let new_visited = current_visited;
            vector::push_back(&mut new_visited, current);

            // Get who vouched FOR this current user (backwards direction)
            let (received_from, _) = vouch::get_received_vouches(current);
            let neighbor_count = vector::length(&received_from);

            if (neighbor_count == 0) continue;

            let next_power = current_power / 2;
            let next_depth = current_depth + 1;

            // Add all neighbors to queue with their own path copy
            let i = 0;
            while (i < neighbor_count) {
                let neighbor = *vector::borrow(&received_from, i);
                if (!vector::contains(&new_visited, &neighbor)) {
                    vector::push_back(&mut queue, neighbor);
                    vector::push_back(&mut depths, next_depth);
                    vector::push_back(&mut powers, next_power);
                    vector::push_back(&mut path_visited, new_visited); // Each neighbor gets its own copy
                };
                i = i + 1;
            };
        };

        (total_score, max_depth_reached, processed_count)
    }

    /// Alternative implementation of set_score using breadth-first search.
    /// This version explores the trust graph level by level instead of depth-first.
    fun set_score_bfs(addr: address): u64 acquires UserTrustRecord {
        // If user has no trust record, they have no score
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));

        // Get roots for computation
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);

        // Compute score using BFS algorithm
        let (score, _max_depth_reached, _processed_count) = walk_backwards_from_target_bfs(
            addr, &roots, MAX_PATH_DEPTH
        );

        // Update the cache
        let user_record_mut = borrow_global_mut<UserTrustRecord>(addr);
        user_record_mut.cached_score = score;
        user_record_mut.score_computed_at_timestamp = timestamp::now_seconds();
        user_record_mut.is_stale = false;

        score
    }

    //////// CACHE ////////

    /// Marks a user's trust score as stale, forcing recalculation on next access.
    /// Called when trust relationships change to invalidate cached scores.
    public(friend) fun mark_as_stale(addr: address) acquires UserTrustRecord {
        if (exists<UserTrustRecord>(addr)) {
            let user_record_mut = borrow_global_mut<UserTrustRecord>(addr);
            user_record_mut.is_stale = true;
        };
    }

    /// Refreshes the cached trust score for a user by recalculating it.
    /// Only callable by the user.
    public entry fun refresh_cache(user: address) acquires UserTrustRecord{
      // assert initialized
      assert!(exists<UserTrustRecord>(user), error::invalid_state(ENOT_INITIALIZED));
      // get_score
      let _score = set_score(user);
    }

    //////// GETTERS ////////
    #[view]
    /// Returns the cached trust score for a user.
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
        let processed_count: u64 = 0;
        let max_depth_reached: u64 = 0;
        let visited = vector::empty<address>();
        let score = walk_backwards_from_target_with_stats(
            addr, &roots, &mut visited, 2 * MAX_VOUCH_SCORE, 0, &mut processed_count, &mut max_depth_reached, MAX_PATH_DEPTH
        );
        (score, max_depth_reached, processed_count)
    }

    #[view]
    /// Calculates a fresh trust score for a user without updating the cache, using a custom max depth.
    /// Returns (score, max_depth_reached, accounts_processed).
    /// Intended for diagnostics and testing only.
    public fun calculate_score_depth(addr: address, max_depth: u64): (u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        let processed_count: u64 = 0;
        let max_depth_reached: u64 = 0;
        let visited = vector::empty<address>();
        let score = walk_backwards_from_target_with_stats(
            addr, &roots, &mut visited, 2 * MAX_VOUCH_SCORE, 0, &mut processed_count, &mut max_depth_reached, max_depth
        );
        (score, max_depth_reached, processed_count)
    }

    #[view]
    /// Calculates a fresh trust score using BFS for a user without updating the cache.
    /// Returns (score, max_depth_reached, accounts_processed).
    /// Intended for diagnostics and testing only.
    public fun calculate_score_bfs(addr: address): (u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        let (score, max_depth_reached, processed_count) = walk_backwards_from_target_bfs(
            addr, &roots, MAX_PATH_DEPTH
        );
        (score, max_depth_reached, processed_count)
    }

    #[view]
    /// Calculates a fresh trust score using BFS for a user without updating the cache, using a custom max depth.
    /// Returns (score, max_depth_reached, accounts_processed).
    /// Intended for diagnostics and testing only.
    public fun calculate_score_bfs_depth(addr: address, max_depth: u64): (u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        let (score, max_depth_reached, processed_count) = walk_backwards_from_target_bfs(
            addr, &roots, max_depth
        );
        (score, max_depth_reached, processed_count)
    }

    #[view]
    /// Returns the trust score using BFS algorithm (for testing/comparison purposes).
    /// This is a public wrapper around the BFS calculation.
    public fun get_trust_score_bfs(addr: address): u64 {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let roots = root_of_trust::get_current_roots_at_registry(@diem_framework);
        let (score, _, _) = walk_backwards_from_target_bfs(addr, &roots, MAX_PATH_DEPTH);
        score
    }

    #[view]
    /// Returns true if the user's trust score is marked as stale.
    public fun is_stale(addr: address): bool acquires UserTrustRecord {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));
        let record = borrow_global<UserTrustRecord>(addr);
        record.is_stale
    }

    #[view]
    /// Returns the maximum possible score for a single vouch.
    public fun get_max_single_score(): u64 {
        MAX_VOUCH_SCORE
    }

    //////// TEST HELPERS ///////
    #[test_only]
    // Sets up a mock trust network for testing.
    // - Initializes trust records and vouch structures for all test accounts.
    // - Sets up vouching relationships and unrelated ancestry for each account.
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

    #[test_only]
    /// Compares DFS vs BFS performance and results for the same address.
    /// Returns (dfs_score, dfs_depth, dfs_processed, bfs_score, bfs_depth, bfs_processed).
    public fun compare_dfs_vs_bfs(addr: address): (u64, u64, u64, u64, u64, u64) {
        assert!(exists<UserTrustRecord>(addr), error::invalid_state(ENOT_INITIALIZED));

        let (dfs_score, dfs_depth, dfs_processed) = calculate_score(addr);
        let (bfs_score, bfs_depth, bfs_processed) = calculate_score_bfs(addr);

        (dfs_score, dfs_depth, dfs_processed, bfs_score, bfs_depth, bfs_processed)
    }

    #[test_only]
    /// Test helper that sets up a comparison between DFS and BFS algorithms
    /// using the mock trust network.
    public fun test_algorithm_comparison(
        admin: &signer,
        root: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer
    ) {
        setup_mock_trust_network(admin, root, user1, user2, user3);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let user3_addr = signer::address_of(user3);

        // Compare algorithms for each user
        let (dfs1, dfs1_depth, _dfs1_proc, bfs1, bfs1_depth, _bfs1_proc) = compare_dfs_vs_bfs(user1_addr);
        let (dfs2, dfs2_depth, _dfs2_proc, bfs2, bfs2_depth, _bfs2_proc) = compare_dfs_vs_bfs(user2_addr);
        let (dfs3, dfs3_depth, _dfs3_proc, bfs3, bfs3_depth, _bfs3_proc) = compare_dfs_vs_bfs(user3_addr);

        // The scores should be identical between DFS and BFS
        assert!(dfs1 == bfs1, 99001);
        assert!(dfs2 == bfs2, 99002);
        assert!(dfs3 == bfs3, 99003);

        // Both should reach the same maximum depth
        assert!(dfs1_depth == bfs1_depth, 99004);
        assert!(dfs2_depth == bfs2_depth, 99005);
        assert!(dfs3_depth == bfs3_depth, 99006);
    }

}
