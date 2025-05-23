#[test_only]
module ol_framework::test_page_rank_bfs {
    use ol_framework::page_rank_lazy;
    use ol_framework::mock;
    use std::signer;

    #[test(admin = @0x1, root = @0x42, user1 = @0x43, user2 = @0x44, user3 = @0x45)]
    /// Test that BFS and DFS produce identical results on the same trust network
    fun test_bfs_vs_dfs_comparison(
        admin: signer,
        root: signer,
        user1: signer,
        user2: signer,
        user3: signer
    ) {
        // Use the existing test helper to compare algorithms
        page_rank_lazy::test_algorithm_comparison(&admin, &root, &user1, &user2, &user3);
    }

    #[test(admin = @0x1, root = @0x42, user1 = @0x43, user2 = @0x44, user3 = @0x45)]
    /// Test BFS calculation individually
    fun test_bfs_calculation(
        admin: signer,
        root: signer,
        user1: signer,
        user2: signer,
        user3: signer
    ) {
        // Setup mock trust network
        page_rank_lazy::setup_mock_trust_network(&admin, &root, &user1, &user2, &user3);

        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);
        let user3_addr = signer::address_of(&user3);

        // Test BFS calculations
        let (score1, depth1, processed1) = page_rank_lazy::calculate_score_bfs(user1_addr);
        let (score2, depth2, processed2) = page_rank_lazy::calculate_score_bfs(user2_addr);
        let (score3, depth3, processed3) = page_rank_lazy::calculate_score_bfs(user3_addr);

        // Verify that scores are reasonable
        // User1 and User2 are directly vouched by root, so they should have the highest scores
        assert!(score1 > 0, 7001);
        assert!(score2 > 0, 7002);

        // User3 is vouched by User2, so should have a lower score than User2
        if (score3 > 0) {
            assert!(score3 <= score2, 7003);
        };

        // Verify depths are within reasonable bounds
        assert!(depth1 <= 3, 7004);
        assert!(depth2 <= 3, 7005);
        assert!(depth3 <= 3, 7006);

        // Verify processing counts are reasonable
        assert!(processed1 > 0, 7007);
        assert!(processed2 > 0, 7008);
        assert!(processed3 > 0, 7009);
    }

    #[test(admin = @0x1, root = @0x42, user1 = @0x43, user2 = @0x44, user3 = @0x45)]
    /// Test BFS with different depths
    fun test_bfs_depth_limits(
        admin: signer,
        root: signer,
        user1: signer,
        user2: signer,
        user3: signer
    ) {
        // Setup mock trust network
        page_rank_lazy::setup_mock_trust_network(&admin, &root, &user1, &user2, &user3);

        let user3_addr = signer::address_of(&user3);

        // Test with different depth limits
        let (score_depth_1, depth1, _): (u64, u64, u64) = page_rank_lazy::calculate_score_bfs_depth(user3_addr, 1);
        let (score_depth_2, depth2, _): (u64, u64, u64) = page_rank_lazy::calculate_score_bfs_depth(user3_addr, 2);
        let (score_depth_3, depth3, _): (u64, u64, u64) = page_rank_lazy::calculate_score_bfs_depth(user3_addr, 3);

        // With depth 1, User3 shouldn't reach the root (needs at least depth 2)
        // With depth 2, User3 should reach User2 but not the root
        // With depth 3, User3 should be able to reach the root

        // Score should increase with higher depth limits (up to the actual path length)
        assert!(score_depth_3 >= score_depth_2, 7011);
        assert!(score_depth_2 >= score_depth_1, 7012);

        // Verify that depth tracking works correctly
        assert!(depth1 <= 1, 7013);
        assert!(depth2 <= 2, 7014);
        assert!(depth3 <= 3, 7015);
    }

    #[test(admin = @0x1, root = @0x42, user1 = @0x43, user2 = @0x44, user3 = @0x45)]
    /// Test that BFS get_trust_score_bfs works correctly
    fun test_bfs_get_trust_score(
        admin: signer,
        root: signer,
        user1: signer,
        user2: signer,
        user3: signer
    ) {
        mock::genesis_n_vals(&admin, 3);

        // Setup mock trust network
        page_rank_lazy::setup_mock_trust_network(&admin, &root, &user1, &user2, &user3);

        let user1_addr = signer::address_of(&user1);
        let user2_addr = signer::address_of(&user2);

        // Get scores using both methods
        let dfs_score1 = page_rank_lazy::get_trust_score(user1_addr);
        let bfs_score1 = page_rank_lazy::get_trust_score_bfs(user1_addr);

        let dfs_score2 = page_rank_lazy::get_trust_score(user2_addr);
        let bfs_score2 = page_rank_lazy::get_trust_score_bfs(user2_addr);

        // Scores should be identical
        assert!(dfs_score1 == bfs_score1, 7020);
        assert!(dfs_score2 == bfs_score2, 7021);

        // Both should be properly cached after calculation
        assert!(!page_rank_lazy::is_stale(user1_addr), 7022);
        assert!(!page_rank_lazy::is_stale(user2_addr), 7023);
    }
}
