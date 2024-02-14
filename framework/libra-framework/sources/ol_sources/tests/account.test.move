#[test_only]

/// tests for external apis, and where a dependency cycle with genesis is created.
module ol_framework::test_account {
  use std::vector;
  use ol_framework::libra_coin;
  use ol_framework::mock;
  use ol_framework::ol_account;
  use ol_framework::ancestry;
  use ol_framework::testnet;

  use diem_framework::coin;
  use diem_framework::comparator;
  use std::bcs;

  use diem_std::debug::print;

  // scenario: testing trying send more funds than are unlocked
  #[test(root = @ol_framework, alice_sig = @0x1000a)]
  fun test_account_create(root: signer, alice_sig: signer) {
    let alice_addr = @0x1000a;
    let bob_addr = @0x1C69FC2C5211343850B38790BFAC39F6C821946F926A4AB323BBFD0C96F93D4E;

    mock::ol_test_genesis(&root);

    let mint_cap = libra_coin::extract_mint_cap(&root);
    ol_account::create_account(&root, alice_addr);
    ol_account::deposit_coins(alice_addr, coin::test_mint(100, &mint_cap));
    coin::destroy_mint_cap(mint_cap);

    let addr_tree = ancestry::get_tree(alice_addr);
    assert!(vector::length(&addr_tree) > 0, 7357001);
    // print(&addr_tree);
    assert!(vector::contains(&addr_tree, &@0x1), 7357002);


    let (a_balance, _) = ol_account::balance(alice_addr);
    assert!(a_balance == 100, 735703);

    ol_account::transfer(&alice_sig, bob_addr, 20);
    let addr_tree = ancestry::get_tree(bob_addr);
    assert!(vector::length(&addr_tree) > 1, 7357004);
    assert!(vector::contains(&addr_tree, &alice_addr), 7357005);

    // print(&addr_tree);

  }

  #[test(alice = @0x1000a, bob = @0x1C69FC2C5211343850B38790BFAC39F6C821946F926A4AB323BBFD0C96F93D4E)]
  fun test_og_address_checks(alice: address, bob: address) {
    let prepend = x"00000000000000000000000000000000";
    print(&prepend);

    let v = bcs::to_bytes(&alice);
    let l = vector::length(&v);
    print(&l);
    vector::trim(&mut v, 16);
    print(&v);

    assert!(comparator::is_equal(&comparator::compare(&v, &prepend)), 7257001);

    assert!(ol_account::is_legacy_addr(alice), 7257002);

    assert!(!ol_account::is_legacy_addr(bob), 7257003);

  }


  // scenario: don't create legacy addresses
  #[test(root = @ol_framework, alice_sig = @0x1000a)]
  #[expected_failure(abort_code = 10, location = 0x1::ol_account)]
  fun test_dont_create_legacy(root: signer, alice_sig: signer) {
    let alice_addr = @0x1000a;
    let bob_addr = @0x1000b;

    mock::ol_test_genesis(&root);
    testnet::unset(&root); //make mainnet to check for legacy issues

    let mint_cap = libra_coin::extract_mint_cap(&root);
    ol_account::create_account(&root, alice_addr);
    ol_account::deposit_coins(alice_addr, coin::test_mint(100, &mint_cap));
    coin::destroy_mint_cap(mint_cap);

    ol_account::transfer(&alice_sig, bob_addr, 20);

  }
}
