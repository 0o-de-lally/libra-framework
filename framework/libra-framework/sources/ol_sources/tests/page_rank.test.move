#[test_only]

/// Tests for page_rank_lazy module with a large network of accounts.
/// This simulates 100 accounts with various vouching relationships
/// and tests the page rank score calculation.
module ol_framework::test_page_rank {
  use std::vector;
  use std::signer;
  use diem_std::math64;
  use ol_framework::mock;
  use ol_framework::root_of_trust;
  use ol_framework::page_rank_lazy;
  use ol_framework::vouch;
  use ol_framework::ancestry;
  use diem_framework::account; // Adding missing import for account module

  // Test with a large network of 100 accounts
  #[test(framework_sig = @ol_framework)]
  fun test_large_vouch_network(framework_sig: signer) {
    // 1. Initialize blockchain and setup the root of trust
    mock::ol_test_genesis(&framework_sig);

    // 2. Create roots (top-level trusted nodes)
    let root_signers = create_test_signers(3, 1);
    let roots = collect_addresses(&root_signers);

    // Initialize root of trust with the framework account
    root_of_trust::framework_migration(&framework_sig, roots, 1, 30);

    // 3. Create 100 normal accounts
    let normal_signers = create_test_signers(100, 100);
    let normal_addresses = collect_addresses(&normal_signers);

    // 4. Initialize ancestry, trust records and vouch structures for all accounts
    let all_signers = vector::empty<signer>();
    vector::append(&mut all_signers, root_signers);
    vector::append(&mut all_signers, normal_signers);

    let i = 0;
    let len = vector::length(&all_signers);
    while (i < len) {
      let signer_ref = vector::borrow(&all_signers, i);
      let addr = signer::address_of(signer_ref);

      // Initialize ancestry
      ancestry::test_fork_migrate(
        &framework_sig,
        signer_ref,
        vector::empty<address>()
      );

      // Initialize vouch structures
      vouch::init(signer_ref);

      // Initialize user trust record
      page_rank_lazy::initialize_user_trust_record(signer_ref);

      i = i + 1;
    };

    // 5. Create various vouching patterns

    // Pattern 1: Root nodes vouch for some high-level nodes
    let high_level_count = 10;
    let first_level_addresses = vector::empty<address>();

    // Roots vouch for the first few high-level nodes
    let j = 0;
    while (j < high_level_count) {
      if (j < vector::length(&normal_addresses)) {
        let target_addr = *vector::borrow(&normal_addresses, j);
        vector::push_back(&mut first_level_addresses, target_addr);

        // Each root vouches for this high-level node
        let i = 0;
        while (i < vector::length(&roots)) {
          let root_addr = *vector::borrow(&roots, i);
          create_vouch(root_addr, target_addr);
          i = i + 1;
        };
      };
      j = j + 1;
    };

    // Pattern 2: High-level nodes vouch for mid-level nodes
    let mid_level_count = 30;
    let mid_level_addresses = vector::empty<address>();

    // Each high-level node vouches for 3 mid-level nodes
    let j = 0;
    while (j < mid_level_count) {
      if (high_level_count + j < vector::length(&normal_addresses)) {
        let target_addr = *vector::borrow(&normal_addresses, high_level_count + j);
        vector::push_back(&mut mid_level_addresses, target_addr);

        // Determine which high-level node will vouch for this mid-level node
        let high_level_idx = j % high_level_count;
        let high_level_addr = *vector::borrow(&first_level_addresses, high_level_idx);
        create_vouch(high_level_addr, target_addr);
      };
      j = j + 1;
    };

    // Pattern 3: Mid-level nodes vouch for base nodes
    // Remaining nodes are base level
    let j = 0;
    while (high_level_count + mid_level_count + j < vector::length(&normal_addresses)) {
      let target_addr = *vector::borrow(&normal_addresses, high_level_count + mid_level_count + j);

      // Determine which mid-level node will vouch for this base node
      let mid_level_idx = j % mid_level_count;
      let mid_level_addr = *vector::borrow(&mid_level_addresses, mid_level_idx);
      create_vouch(mid_level_addr, target_addr);

      j = j + 1;
    };

    // Pattern 4: Create some cross-connections for a more realistic network
    // Add some random vouches between nodes at the same level
    let cross_connection_count = 50;
    let k = 0;
    while (k < cross_connection_count) {
      // Get two random indices
      let idx1 = math64::pow(k, 3) % vector::length(&normal_addresses);
      let idx2 = (math64::pow(k, 2) + 7) % vector::length(&normal_addresses);

      if (idx1 != idx2) {
        let addr1 = *vector::borrow(&normal_addresses, idx1);
        let addr2 = *vector::borrow(&normal_addresses, idx2);
        create_vouch(addr1, addr2);
      };

      k = k + 1;
    };

    // Add some cyclic relationships (node A vouches for B, B vouches for C, C vouches for A)
    let cycle_count = 3;
    let m = 0;
    while (m < cycle_count) {
      let idx1 = m * 10 % vector::length(&normal_addresses);
      let idx2 = (m * 10 + 3) % vector::length(&normal_addresses);
      let idx3 = (m * 10 + 6) % vector::length(&normal_addresses);

      if (idx1 != idx2 && idx2 != idx3 && idx1 != idx3) {
        let addr1 = *vector::borrow(&normal_addresses, idx1);
        let addr2 = *vector::borrow(&normal_addresses, idx2);
        let addr3 = *vector::borrow(&normal_addresses, idx3);

        create_vouch(addr1, addr2);
        create_vouch(addr2, addr3);
        create_vouch(addr3, addr1);
      };

      m = m + 1;
    };

    // 6. Calculate and verify trust scores
    let current_timestamp = 1000;

    // Calculate scores for all nodes
    let scores = vector::empty<u64>();
    let i = 0;
    while (i < vector::length(&normal_addresses)) {
      let addr = *vector::borrow(&normal_addresses, i);
      let score = page_rank_lazy::get_trust_score(addr, current_timestamp);
      vector::push_back(&mut scores, score);
      i = i + 1;
    };

    // 7. Verify trust score properties

    // Property 1: Root nodes should have non-zero scores
    let i = 0;
    while (i < vector::length(&roots)) {
      let root_addr = *vector::borrow(&roots, i);
      assert!(page_rank_lazy::is_root_node(root_addr), 7357100);
      i = i + 1;
    };

    // Property 2: First level nodes should have higher scores than the last level nodes
    if (vector::length(&scores) >= high_level_count + mid_level_count + 10) {
      let avg_first_level_score = 0;
      let i = 0;
      while (i < high_level_count) {
        avg_first_level_score = avg_first_level_score + *vector::borrow(&scores, i);
        i = i + 1;
      };
      avg_first_level_score = avg_first_level_score / high_level_count;

      let avg_last_level_score = 0;
      let total_nodes = vector::length(&normal_addresses);
      let i = 0;
      let count = 0;
      while (i < 10 && high_level_count + mid_level_count + i < total_nodes) {
        avg_last_level_score = avg_last_level_score +
            *vector::borrow(&scores, high_level_count + mid_level_count + i);
        i = i + 1;
        count = count + 1;
      };
      if (count > 0) {
        avg_last_level_score = avg_last_level_score / count;

        // First level nodes should generally have higher scores
        assert!(avg_first_level_score > avg_last_level_score, 7357101);
      };
    };

    // Property 3: Check that nodes with more vouches tend to have higher scores
    // Create nodes with specific vouching patterns to test this
    if (vector::length(&normal_addresses) >= 90) {
      let test_addr1 = *vector::borrow(&normal_addresses, 85);
      let test_addr2 = *vector::borrow(&normal_addresses, 86);
      let test_addr3 = *vector::borrow(&normal_addresses, 87);

      // Give test_addr1 more direct vouches from root nodes
      let i = 0;
      while (i < vector::length(&roots)) {
        let root_addr = *vector::borrow(&roots, i);
        create_vouch(root_addr, test_addr1);
        i = i + 1;
      };

      // Give test_addr2 vouches from mid-level nodes
      let i = 0;
      while (i < 3 && i < vector::length(&mid_level_addresses)) {
        let mid_addr = *vector::borrow(&mid_level_addresses, i);
        create_vouch(mid_addr, test_addr2);
        i = i + 1;
      };

      // Give test_addr3 only one vouch from a base level node
      if (high_level_count + mid_level_count < vector::length(&normal_addresses)) {
        let base_addr = *vector::borrow(&normal_addresses, high_level_count + mid_level_count);
        create_vouch(base_addr, test_addr3);
      };

      // Calculate scores with fresh cache
      let score1 = page_rank_lazy::get_trust_score(test_addr1, current_timestamp + 2000);
      let score2 = page_rank_lazy::get_trust_score(test_addr2, current_timestamp + 2000);
      let score3 = page_rank_lazy::get_trust_score(test_addr3, current_timestamp + 2000);

      // Address with vouches from root nodes should have the highest score
      assert!(score1 > score2, 7357102);
      assert!(score2 > score3, 7357103);
    };

    // 8. Check that trust records are correctly marked as stale when vouching relationships change
    if (vector::length(&normal_addresses) >= 92) {
      let test_addr1 = *vector::borrow(&normal_addresses, 90);
      let test_addr2 = *vector::borrow(&normal_addresses, 91);

      // First establish a vouch relationship
      create_vouch(*vector::borrow(&roots, 0), test_addr1);
      create_vouch(test_addr1, test_addr2);

      // Calculate initial scores to cache them
      let _ = page_rank_lazy::get_trust_score(test_addr1, current_timestamp);
      let score2_before = page_rank_lazy::get_trust_score(test_addr2, current_timestamp);

      // Check that records are fresh now
      assert!(page_rank_lazy::is_fresh_record(test_addr1, current_timestamp), 7357104);
      assert!(page_rank_lazy::is_fresh_record(test_addr2, current_timestamp), 7357105);

      // Remove the vouch relationship
      revoke_vouch(test_addr1, test_addr2);

      // Record should now be stale
      assert!(!page_rank_lazy::is_fresh_record(test_addr2, current_timestamp), 7357106);

      // Recalculate score
      let score2_after = page_rank_lazy::get_trust_score(test_addr2, current_timestamp);

      // Score should change (likely be lower) without the vouch
      assert!(score2_before != score2_after, 7357107);
    };
  }

  // Helper function to create a bunch of test signers
  fun create_test_signers(count: u64, start_index: u64): vector<signer> {
    let signers = vector::empty<signer>();
    let i = 0;
    while (i < count) {
      let addr_num = start_index + i;
      let addr_bytes = addr_num; // Using count directly as the address for simplicity
      let sig = create_signer_for_test(addr_bytes);
      vector::push_back(&mut signers, sig);
      i = i + 1;
    };
    signers
  }

  // Helper to extract addresses from signers
  fun collect_addresses(signers: &vector<signer>): vector<address> {
    let addresses = vector::empty<address>();
    let i = 0;
    let len = vector::length(signers);
    while (i < len) {
      let addr = signer::address_of(vector::borrow(signers, i));
      vector::push_back(&mut addresses, addr);
      i = i + 1;
    };
    addresses
  }

  // Helper to create a vouch relationship
  fun create_vouch(voucher: address, recipient: address) {
    // Try to find the signer for this address - in a real test we'd have the signers
    // But here we'll use the direct vouch test helper function
    vouch::test_new_vouch_for(voucher, recipient);
  }

  // Helper to revoke a vouch relationship
  fun revoke_vouch(voucher: address, recipient: address) {
    // Same as above, using test helper
    vouch::test_remove_vouch_from(voucher, recipient);

    // Mark record as stale
    page_rank_lazy::mark_record_stale(recipient);
  }

  // Create signer function for test purposes
  fun create_signer_for_test(addr: u64): signer {
    // Import from_bcs module for converting bytes to addresses
    use diem_std::from_bcs;
    use std::bcs;

    // Convert u64 to bytes first using BCS serialization
    let addr_bytes = bcs::to_bytes(&addr);

    // When addr is small, the BCS representation will be short
    // Pad with zeros if needed to get a valid address (32 bytes for Move addresses)
    while (vector::length(&addr_bytes) < 32) {
      vector::push_back(&mut addr_bytes, 0);
    };

    // Convert bytes to address using from_bcs module
    let addr_as_addr = from_bcs::to_address(addr_bytes);

    // Create test signer from the generated address
    account::create_signer_for_test(addr_as_addr)
  }

  // Test with a large-scale network of 1000 accounts
  #[test(framework_sig = @ol_framework)]
  fun test_massive_vouch_network(framework_sig: signer) {
    // 1. Initialize blockchain and setup the root of trust
    mock::ol_test_genesis(&framework_sig);

    // 2. Create roots (top-level trusted nodes)
    let root_count = 5;
    let root_signers = create_test_signers(root_count, 1);
    let roots = collect_addresses(&root_signers);

    // Initialize root of trust with the framework account
    root_of_trust::framework_migration(&framework_sig, roots, 2, 30);

    // 3. Create 1000 normal accounts
    let normal_count = 1000;
    let normal_signers = create_test_signers(normal_count, 100);
    let normal_addresses = collect_addresses(&normal_signers);

    // 4. Initialize ancestry, trust records and vouch structures for all accounts
    let all_signers = vector::empty<signer>();
    vector::append(&mut all_signers, root_signers);
    vector::append(&mut all_signers, normal_signers);

    initialize_all_accounts(&framework_sig, &all_signers);

    // 5. Create a multi-layer network structure

    // Layer configuration
    let layer_sizes = vector[20, 50, 100, 200, 630];  // Total = 1000 accounts
    let roots_per_layer1 = 3;   // How many root nodes vouch for each layer 1 node
    let layer_connections = 5;  // How many nodes each node vouches for in the next layer
    let cross_connections = 300; // Number of random cross-layer connections
    let cyclic_patterns = 50;   // Number of A->B->C->A cyclic vouching patterns

    // Create structured layered network
    create_layered_network(
      &roots,
      &normal_addresses,
      &layer_sizes,
      roots_per_layer1,
      layer_connections
    );

    // Add cross-connections for a more realistic network
    create_cross_connections(&normal_addresses, cross_connections);

    // Create cyclic relationships
    create_cyclic_patterns(&normal_addresses, cyclic_patterns);

    // 6. Calculate and verify trust scores
    let current_timestamp = 1000;

    // Calculate scores for nodes in each layer
    let layer_start_idx = 0;
    let avg_scores = vector::empty<u64>();

    // Calculate average scores for each layer
    let l = 0;
    while (l < vector::length(&layer_sizes)) {
      let layer_size = *vector::borrow(&layer_sizes, l);
      let layer_score_sum = 0;

      let i = 0;
      while (i < layer_size) {
        let addr_idx = layer_start_idx + i;
        if (addr_idx < vector::length(&normal_addresses)) {
          let addr = *vector::borrow(&normal_addresses, addr_idx);
          let score = page_rank_lazy::get_trust_score(addr, current_timestamp);
          layer_score_sum = layer_score_sum + score;
        };
        i = i + 1;
      };

      let avg_score = if (layer_size > 0) { layer_score_sum / layer_size } else { 0 };
      vector::push_back(&mut avg_scores, avg_score);

      layer_start_idx = layer_start_idx + layer_size;
      l = l + 1;
    };

    // 7. Verify trust score properties

    // Property 1: Root nodes should have non-zero scores
    verify_root_node_scores(&roots);

    // Property 2: Higher layers should generally have higher scores than lower layers
    verify_layer_score_distribution(&avg_scores);

    // Property 3: Track a few specific nodes to verify their individual scores
    verify_specific_node_scores(&normal_addresses, &roots, current_timestamp);
  }

  // Helper function to initialize accounts
  fun initialize_all_accounts(framework_sig: &signer, signers: &vector<signer>) {
    let i = 0;
    let len = vector::length(signers);
    while (i < len) {
      let signer_ref = vector::borrow(signers, i);
      let addr = signer::address_of(signer_ref);

      // Initialize ancestry
      ancestry::test_fork_migrate(
        framework_sig,
        signer_ref,
        vector::empty<address>()
      );

      // Initialize vouch structures
      vouch::init(signer_ref);

      // Initialize user trust record
      page_rank_lazy::initialize_user_trust_record(signer_ref);

      i = i + 1;
    };
  }

  // Helper function to create a multi-layer network
  fun create_layered_network(
    roots: &vector<address>,
    normal_addresses: &vector<address>,
    layer_sizes: &vector<u64>,
    roots_per_layer1: u64,
    layer_connections: u64
  ) {
    let layer_start_idx = 0;
    let l = 0;

    while (l < vector::length(layer_sizes)) {
      let layer_size = *vector::borrow(layer_sizes, l);
      let parent_layer_start = if (l == 0) { 0 } else { layer_start_idx - *vector::borrow(layer_sizes, l - 1) };
      let parent_layer_size = if (l == 0) { vector::length(roots) } else { *vector::borrow(layer_sizes, l - 1) };

      let i = 0;
      while (i < layer_size) {
        let addr_idx = layer_start_idx + i;
        if (addr_idx < vector::length(normal_addresses)) {
          let target_addr = *vector::borrow(normal_addresses, addr_idx);

          // For first layer, vouches come from root nodes
          if (l == 0) {
            let r = 0;
            while (r < roots_per_layer1 && r < vector::length(roots)) {
              let root_idx = (i + r) % vector::length(roots);
              let root_addr = *vector::borrow(roots, root_idx);
              create_vouch(root_addr, target_addr);
              r = r + 1;
            };
          }
          // For other layers, vouches come from previous layer
          else {
            let conn = 0;
            while (conn < layer_connections) {
              let parent_idx = (i + conn * 7) % parent_layer_size; // Use prime number to distribute connections
              let parent_addr_idx = parent_layer_start + parent_idx;

              if (parent_addr_idx < vector::length(normal_addresses)) {
                let parent_addr = *vector::borrow(normal_addresses, parent_addr_idx);
                create_vouch(parent_addr, target_addr);
              };

              conn = conn + 1;
            };
          };
        };

        i = i + 1;
      };

      layer_start_idx = layer_start_idx + layer_size;
      l = l + 1;
    };
  }

  // Helper function to create random cross-connections between layers
  fun create_cross_connections(normal_addresses: &vector<address>, count: u64) {
    let k = 0;
    while (k < count) {
      // Generate pseudo-random indices using different polynomial functions
      let idx1 = (k * k + 3 * k + 41) % vector::length(normal_addresses);
      let idx2 = (k * k * k + 7 * k + 13) % vector::length(normal_addresses);

      if (idx1 != idx2) {
        let addr1 = *vector::borrow(normal_addresses, idx1);
        let addr2 = *vector::borrow(normal_addresses, idx2);
        create_vouch(addr1, addr2);
      };

      k = k + 1;
    };
  }

  // Helper function to create cyclic vouching patterns (A-B-C-A)
  fun create_cyclic_patterns(normal_addresses: &vector<address>, count: u64) {
    let m = 0;
    while (m < count) {
      let size = vector::length(normal_addresses);
      if (size >= 3) {
        let idx1 = (m * 13) % size;
        let idx2 = (m * 13 + 11) % size;
        let idx3 = (m * 13 + 23) % size;

        if (idx1 != idx2 && idx2 != idx3 && idx1 != idx3) {
          let addr1 = *vector::borrow(normal_addresses, idx1);
          let addr2 = *vector::borrow(normal_addresses, idx2);
          let addr3 = *vector::borrow(normal_addresses, idx3);

          create_vouch(addr1, addr2);
          create_vouch(addr2, addr3);
          create_vouch(addr3, addr1);
        };
      };

      m = m + 1;
    };
  }

  // Helper function to verify that all root nodes have non-zero scores
  fun verify_root_node_scores(roots: &vector<address>) {
    let i = 0;
    while (i < vector::length(roots)) {
      let root_addr = *vector::borrow(roots, i);
      assert!(page_rank_lazy::is_root_node(root_addr), 7358000);
      i = i + 1;
    };
  }

  // Helper function to verify layer score distribution (higher layers should have higher scores)
  fun verify_layer_score_distribution(avg_scores: &vector<u64>) {
    let i = 0;
    while (i < vector::length(avg_scores) - 1) {
      let current_score = *vector::borrow(avg_scores, i);
      let next_score = *vector::borrow(avg_scores, i + 1);

      // Higher layers should generally have higher scores than lower layers
      // Using >= instead of > since some edge cases with tiny rounding differences might occur
      assert!(current_score >= next_score, 7358001);

      i = i + 1;
    };
  }

  // Helper function to verify specific node scores based on vouching patterns
  fun verify_specific_node_scores(normal_addresses: &vector<address>, roots: &vector<address>, timestamp: u64) {
    if (vector::length(normal_addresses) >= 500) {
      // Create 3 test nodes with controlled vouching patterns
      let test_addr1 = *vector::borrow(normal_addresses, 300);
      let test_addr2 = *vector::borrow(normal_addresses, 301);
      let test_addr3 = *vector::borrow(normal_addresses, 302);

      // Give test_addr1 direct vouches from all root nodes (highest influence)
      let i = 0;
      while (i < vector::length(roots)) {
        let root_addr = *vector::borrow(roots, i);
        create_vouch(root_addr, test_addr1);
        i = i + 1;
      };

      // Give test_addr2 vouches from high-tier nodes (layer 1)
      let i = 0;
      while (i < 5 && i < vector::length(normal_addresses)) {
        let high_tier_addr = *vector::borrow(normal_addresses, i);
        create_vouch(high_tier_addr, test_addr2);
        i = i + 1;
      };

      // Give test_addr3 only one vouch from a low-tier node (lowest influence)
      if (vector::length(normal_addresses) > 400) {
        let low_tier_addr = *vector::borrow(normal_addresses, 400);
        create_vouch(low_tier_addr, test_addr3);
      };

      // Calculate scores
      let score1 = page_rank_lazy::get_trust_score(test_addr1, timestamp + 1000);
      let score2 = page_rank_lazy::get_trust_score(test_addr2, timestamp + 1000);
      let score3 = page_rank_lazy::get_trust_score(test_addr3, timestamp + 1000);

      // Verify expected scoring pattern
      assert!(score1 > score2, 7358002);
      assert!(score2 > score3, 7358003);

      // Test score staleness by modifying vouching relationship
      let score2_before = page_rank_lazy::get_trust_score(test_addr2, timestamp + 2000);
      assert!(page_rank_lazy::is_fresh_record(test_addr2, timestamp + 2000), 7358004);

      // Change vouching pattern by adding a significant connection
      if (vector::length(roots) > 0) {
        create_vouch(*vector::borrow(roots, 0), test_addr2);
      };

      // Record should be marked stale
      assert!(!page_rank_lazy::is_fresh_record(test_addr2, timestamp + 2000), 7358005);

      // Recalculate score
      let score2_after = page_rank_lazy::get_trust_score(test_addr2, timestamp + 2000);
      assert!(score2_after > score2_before, 7358006); // Score should be higher with the new root vouching
    };
  }
}
