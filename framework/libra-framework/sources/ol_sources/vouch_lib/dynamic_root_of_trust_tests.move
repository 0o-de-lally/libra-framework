#[test_only]
module ol_framework::dynamic_root_of_trust_tests {
    use std::vector;
    use diem_framework::account;
    use ol_framework::dynamic_root_of_trust;
    use ol_framework::root_of_trust;
    use ol_framework::vouch;

    // Test account addresses
    const ADMIN_ADDR: address = @0x1;
    const ROOT1_ADDR: address = @0xA1;
    const ROOT2_ADDR: address = @0xA2;
    const ROOT3_ADDR: address = @0xA3;
    const USER1_ADDR: address = @0xB1;
    const USER2_ADDR: address = @0xB2;
    const USER3_ADDR: address = @0xB3;

    #[test(admin = @0x1, root1 = @0xA1, root2 = @0xA2, root3 = @0xA3, user1 = @0xB1, user2 = @0xB2, user3 = @0xB3)]
    fun test_dynamic_root_calculation(
        admin: signer,
        root1: signer,
        root2: signer,
        root3: signer,
        user1: signer,
        user2: signer,
        user3: signer
    ) {
        // Initialize accounts
        account::create_account_for_test(ADMIN_ADDR);
        account::create_account_for_test(ROOT1_ADDR);
        account::create_account_for_test(ROOT2_ADDR);
        account::create_account_for_test(ROOT3_ADDR);
        account::create_account_for_test(USER1_ADDR);
        account::create_account_for_test(USER2_ADDR);
        account::create_account_for_test(USER3_ADDR);

        // Setup vouch structures for all accounts
        vouch::init(&root1);
        vouch::init(&root2);
        vouch::init(&root3);
        vouch::init(&user1);
        vouch::init(&user2);
        vouch::init(&user3);

        // Initialize root of trust with 3 root candidates
        let roots = vector::empty<address>();
        vector::push_back(&mut roots, ROOT1_ADDR);
        vector::push_back(&mut roots, ROOT2_ADDR);
        vector::push_back(&mut roots, ROOT3_ADDR);

        root_of_trust::test_set_root_of_trust(&admin, roots, 3, 1);

        // Setup vouching relationships:
        // ROOT1 vouches for USER1, USER2
        // ROOT2 vouches for USER1, USER3
        // ROOT3 vouches for USER1, USER2, USER3

        vouch::test_set_given_list(ROOT1_ADDR, vector[USER1_ADDR, USER2_ADDR]);
        vouch::test_set_given_list(ROOT2_ADDR, vector[USER1_ADDR, USER3_ADDR]);
        vouch::test_set_given_list(ROOT3_ADDR, vector[USER1_ADDR, USER2_ADDR, USER3_ADDR]);

        // Calculate dynamic root of trust
        let dynamic_roots = dynamic_root_of_trust::get_dynamic_roots(@diem_framework);

        // Verify USER1 is the only common vouch (intersection of all roots' vouches)
        assert!(vector::length(&dynamic_roots) == 1, 0);
        assert!(*vector::borrow(&dynamic_roots, 0) == USER1_ADDR, 1);

        // Modify ROOT1 to also vouch for USER3
        vouch::test_set_given_list(ROOT1_ADDR, vector[USER1_ADDR, USER2_ADDR, USER3_ADDR]);

        // Recalculate dynamic root of trust
        dynamic_roots = dynamic_root_of_trust::get_dynamic_roots(@diem_framework);

        // Now both USER1 and USER3 should be in the dynamic roots (common vouches)
        assert!(vector::length(&dynamic_roots) == 2, 2);
        assert!(vector::contains(&dynamic_roots, &USER1_ADDR), 3);
        assert!(vector::contains(&dynamic_roots, &USER3_ADDR), 4);

        // Remove all vouches from ROOT3
        vouch::test_set_given_list(ROOT3_ADDR, vector::empty<address>());

        // When any candidate has no vouches, there should be no common vouches
        dynamic_roots = dynamic_root_of_trust::get_dynamic_roots(@diem_framework);
        assert!(vector::length(&dynamic_roots) == 0, 5);
        assert!(!dynamic_root_of_trust::has_common_vouches(@diem_framework), 6);
    }

    #[test]
    fun test_intersection() {
        let list1 = vector[@0x1, @0x2, @0x3, @0x4];
        let list2 = vector[@0x2, @0x4, @0x6];

        let intersection = dynamic_root_of_trust::test_find_intersection(list1, list2);
        assert!(vector::length(&intersection) == 2, 0);
        assert!(vector::contains(&intersection, &@0x2), 1);
        assert!(vector::contains(&intersection, &@0x4), 2);

        // Test empty intersection
        let list3 = vector[@0x5, @0x7, @0x9];
        let empty_intersection = dynamic_root_of_trust::test_find_intersection(list1, list3);
        assert!(vector::length(&empty_intersection) == 0, 3);
    }
}
