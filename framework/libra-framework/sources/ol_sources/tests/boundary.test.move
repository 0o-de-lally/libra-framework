// e2e tests for epoch boundary
#[test_only]
module ol_framework::test_boundary {
  use std::vector;
  use diem_std::bls12381;
  use diem_framework::stake;
  use diem_framework::timestamp;
  use diem_framework::reconfiguration;
  use diem_framework::diem_governance;
  use diem_framework::transaction_fee;
  use diem_framework::account;
  // use ol_framework::burn;
  use ol_framework::mock;
  use ol_framework::proof_of_fee;
  use ol_framework::jail;
  use ol_framework::slow_wallet;
  use ol_framework::vouch;
  use ol_framework::testnet;
  use ol_framework::validator_universe;
  use ol_framework::epoch_boundary;
  use ol_framework::block;
  use ol_framework::ol_account;

  const Alice: address = @0x1000a;
  const Bob: address = @0x1000b;
  const Carol: address = @0x1000c;
  const Dave: address = @0x1000d;
  const Eve: address = @0x1000e;
  const Frank: address = @0x1000f;


  fun common_test_setup(root: &signer): vector<address> {
    let set = mock::genesis_n_vals(root, 10);
    mock::ol_initialize_coin_and_fund_vals(root, 500000, true);
    mock::mock_all_vals_good_performance(root);
    mock::pof_default();
    slow_wallet::slow_wallet_epoch_drip(root, 500000);

    // NOTE: for e2e epoch tests, we need to go into an operating epoch (not 0 or 1). Advance to epoch #2
    reconfiguration::test_helper_increment_epoch_dont_reconfigure(1);
    reconfiguration::test_helper_increment_epoch_dont_reconfigure(1);

    set
  }


  #[test(root = @ol_framework, alice = @0x1000a, marlon = @0x12345)]
  fun meta_test_override_epoch_change(root: &signer) {
    common_test_setup(root);
    // testing mainnet, so change the chain_id
    testnet::unset(root);
    // test setup advances to epoch #2
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 2, 7357001);
    epoch_boundary::test_set_boundary_ready(root, epoch);

    timestamp::fast_forward_seconds(1); // needed for reconfig
    block::test_maybe_advance_epoch(root, 603000001, 602000000);

    // test epoch did not advance and needs to be triggered
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 2, 7357003);

    // test epoch can be triggered and advances
    epoch_boundary::test_trigger(root);
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 3, 7357004);
  }
  // We need to test e2e of the epoch boundary
  #[test(root = @ol_framework)]
  fun e2e_boundary_happy(root: signer) {
    let vals = common_test_setup(&root);

    // check vals balance
    vector::for_each(vals, |addr| {
      let (_unlocked, total) = ol_account::balance(addr);
      assert!(total == 500_000, 7357000);
    });

    mock::trigger_epoch(&root);

    let _vals_post = stake::get_current_validators();

    assert!(epoch_boundary::get_reconfig_success(), 7357001);

    // all validators were compliant, should be +1 of the 10 vals
    assert!(epoch_boundary::get_max_seats_offered() == 11, 7357002);

    // all vals had winning bids, but it was less than the seats on offer
    let winners = epoch_boundary::get_auction_winners();
    assert!(vector::length(&winners) == 9, 7357003);
    // all of the auction winners became the validators ultimately
    assert!(vector::length(&epoch_boundary::get_actual_vals()) == 9, 7357004);


    // check vals rewards received and bid fees collected
    // NOTE the clearing bid in this example is not the last validator, but the 9th = 2_000
    // balance + reward - fee = 500_000 + 1_000_000 - 2_000 = 1_498_000
    vector::for_each(winners, |addr| {
      let (_unlocked, total) = ol_account::balance(addr);
      assert!(total == 1_498_000, 7357005);
    });

    // check subsidy for new rewards and fees collected
    // validators = 9
    // fees collected = 9 * 1_000_000 + 9 * 2_000 = 9_018_000
    assert!(transaction_fee::system_fees_collected() == 9018000, 7357006);
  }


  #[test(root = @ol_framework, alice = @0x1000a,  marlon_rando = @0x12345)]
  fun e2e_competitive_set(root: signer, alice: signer, marlon_rando: signer) {
    let _initial_vals = common_test_setup(&root);

    // generate credentials for validator registration
    ol_account::transfer(&alice, @0x12345, 200000);
    let (_sk, pk, pop) = stake::generate_identity();
    let pk_bytes = bls12381::public_key_to_bytes(&pk);
    let pop_bytes = bls12381::proof_of_possession_to_bytes(&pop);
    validator_universe::register_validator(&marlon_rando, pk_bytes, pop_bytes, b"123", b"abc");

    // MARLON PAYS THE BID
    let vals = validator_universe::get_eligible_validators();
    assert!(vector::length(&vals) == 11, 7357001);

    mock::mock_bids(&vals);

    // MARLON HAS MANY FRIENDS
    vouch::test_set_received_list(@0x12345, vals);

    let (errs, _pass) = proof_of_fee::audit_qualification(@0x12345);
    assert!(vector::length(&errs) == 0, 7357002);

    let (_unlocked, bob_bal) = ol_account::balance(@0x1000b);
    assert!(bob_bal == 500000, 737001);
    let (_unlocked, marlon_bal) = ol_account::balance(@0x12345);
    assert!(marlon_bal == 200000, 737001);


    mock::trigger_epoch(&root);

    assert!(epoch_boundary::get_reconfig_success(), 7357003);

    // musical chairs recommended 11 seats BUT...
    assert!(epoch_boundary::get_max_seats_offered() == 11, 7357004);

    // there were only 11 bidders for the 11 offered, which is not competitive enough
    assert!(vector::length(&epoch_boundary::get_qualified_bidders()) == 11, 7357004);

    assert!(vector::length(&epoch_boundary::get_auction_winners()) == 10, 7357005);

    let (_unlocked, bob_bal_now) = ol_account::balance(@0x1000b);
    assert!(bob_bal_now == bob_bal + 1_000_000 - 2_000, 737001);

    let (_unlocked, marlon_bal_now) = ol_account::balance(@0x12345);
    // MARLON just got seated (he outbid others), but he did not receive a reward from previous epoch
    assert!(marlon_bal_now == marlon_bal - 2_000, 737001);

  }

  #[test(root = @ol_framework, alice = @0x1000a,  marlon_rando = @0x12345)]
  fun e2e_add_validator_sad_vouches(root: signer, alice: signer, marlon_rando: signer) {
    let _vals = common_test_setup(&root);
    // this test requires prod settings, since we don't check vouches on testing
    // generate credentials for validator registration
    ol_account::transfer(&alice, @0x12345, 200000);
    let (_sk, pk, pop) = stake::generate_identity();
    let pk_bytes = bls12381::public_key_to_bytes(&pk);
    let pop_bytes = bls12381::proof_of_possession_to_bytes(&pop);
    validator_universe::register_validator(&marlon_rando, pk_bytes, pop_bytes, b"123", b"abc");

    let vals = validator_universe::get_eligible_validators();
    assert!(vector::length(&vals) == 11, 7357000);

    // HOWEVER there are not sufficient bidders with vouches
    // marlon has no vouches
    let (qualified, _) = proof_of_fee::get_bidders_and_bids(true);
    assert!(vector::length(&qualified) == 10, 7357000);


    mock::mock_bids(&vals);

    // use prod settings on epoch boundary
    testnet::unset(&root);

    mock::trigger_epoch(&root);

    assert!(epoch_boundary::get_reconfig_success(), 7357002);

    // all outgoing validators were compliant, max recommended should be +1 of the 10 vals
    assert!(epoch_boundary::get_max_seats_offered() == 11, 7357003);

    // HOWEVER there are 10 bidders ONLY, so we restrict the supply of seats.
    // down to 9.

    assert!(epoch_boundary::get_filled_seats() == 9, 7357004);

    // NOTE: now MARLON is INCLUDED in this, and we filled all the seats on offer.
    // all vals had winning bids
    // but the number of bidders was equal to the seats, and
    // to make it competitive, we the seats offered were 9
    assert!(vector::length(&epoch_boundary::get_auction_winners()) == 9, 7357005);
    // all of the auction winners became the validators ultimately
    assert!(vector::length(&epoch_boundary::get_actual_vals()) == 9, 7357006);
  }

  #[test(root = @ol_framework)]
  fun e2e_boundary_excludes_jail(root: signer) {
    let vals = common_test_setup(&root);
    let alice_addr = *vector::borrow(&vals, 0);

    // mock vals performance
    let i = 1;
    while (i < vector::length(&vals)) {
      let addr = *vector::borrow(&vals, i);
      stake::mock_performance(&root, addr, 10, 0);
      i = i + 1;
    };

    // make Alice val not compliant to end up in jail
    stake::mock_performance(&root, alice_addr, 10, 10);

    // get Alice balance before epoch boundary
    let (_unlocked, alice_before) = ol_account::balance(alice_addr);

    // new epoch
    mock::trigger_epoch(&root);

    // check that Alice is jailed
    assert!(jail::is_jailed(alice_addr), 7357001);

    // ensure Alice did not receive rewards
    let (_unlocked, alice_after) = ol_account::balance(alice_addr);
    assert!(alice_before == alice_after, 7357002);

    // check that validator set reduced by 1
    let qualified_bidders = epoch_boundary::get_qualified_bidders();
    assert!(vector::length(&qualified_bidders) == 9, 7357003);

    // check subsidy for new rewards and fees collected
    // fees collected = 9 * 1_000_000 + 9 * 2_000 = 9_018_000
    assert!(transaction_fee::system_fees_collected() == 9_018_000, 7357004);

    // all vals had winning bids, but it was less than the seats on offer
    assert!(vector::length(&epoch_boundary::get_auction_winners()) == vector::length(&qualified_bidders) , 7357005);
    assert!(epoch_boundary::get_reconfig_success(), 7357006);
  }

  #[test(root = @ol_framework, marlon = @0x12345)]
  fun epoch_any_address_trigger(root: &signer, marlon: &signer) {
    common_test_setup(root);
    // testing mainnet, so change the chainid
    testnet::unset(root);
    // test setup advances to epoch #2
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 2, 7357001);
    epoch_boundary::test_set_boundary_ready(root, epoch);

    // test the APIs as root
    timestamp::fast_forward_seconds(1); // needed for reconfig
    epoch_boundary::test_trigger(root);
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 3, 7357002);

    // scenario: marlon has no privileges
    // but he can still trigger an epoch if it is enabled

    epoch_boundary::test_set_boundary_ready(root, epoch);
    timestamp::fast_forward_seconds(1); // needed for reconfig
    diem_governance::trigger_epoch(marlon);
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 4, 7357003);
  }

  #[test(root = @ol_framework)]
  fun epoch_increase_thermostat(root: &signer) {
    let vals = common_test_setup(root);

    // mock bids
    vector::for_each(vals, |a| {
      let sig = account::create_signer_for_test(a);
      proof_of_fee::pof_update_bid(&sig, 0100, 30); // 10% for 30 epochs
    });

    // mock bid history to increase thermostat by 5%
    proof_of_fee::test_mock_reward(
      root,
      1000, // nominal reward
      0100, // clearing bid
      0100, // median win bid
      vector[ 0100, 0100, 0100, 0100, 0100, 0100 ] // median history bellow 50%
    );

    // trigger epoch
    mock::trigger_epoch(root);

    assert!(epoch_boundary::get_filled_seats() == 9, 7357001);

    // check subsidy increased by 5%
    // fees collected = entry fee + reward * 105%
    // entry fee = 100 * 9 = 900
    // reward = 1050 * 9 = 10_500
    // fees collected = 10_350

    assert!(transaction_fee::system_fees_collected() == 10_350, 7357002);
  }

  #[test(root = @ol_framework)]
  fun epoch_decrease_thermostat(root: &signer) {
    let vals = common_test_setup(root);

    // mock bids
    vector::for_each(vals, |a| {
      let sig = account::create_signer_for_test(a);
      proof_of_fee::pof_update_bid(&sig, 0970, 30); // 97% for 30 epochs
    });

    // mock bid history to decrease thermostat by 5%
    proof_of_fee::test_mock_reward(
      root,
      100_000, // nominal reward
      0970, // clearing bid
      0970, // median win bid
      vector[ 0970, 0970, 0970, 0970, 0970, 0970 ] // median history above 95%
    );

    // trigger epoch
    mock::trigger_epoch(root);
    assert!(epoch_boundary::get_filled_seats() == 9, 7357001);

    // check subsidy decreased by 5%
    // fees collected = entry fee + reward * 95%
    // entry fee = 97_000 * 10 = 873_000
    // reward = 95_000 * 10 = 855_000
    // fees collected = 1_728_000
    assert!(transaction_fee::system_fees_collected() == 1_728_000, 7357002);
  }

  #[test(root = @ol_framework, marlon = @0x12345)]
  #[expected_failure(abort_code = 2, location = 0x1::epoch_boundary)]
  fun epoch_any_address_aborts(root: &signer, marlon: &signer) {
    common_test_setup(root);
    // testing mainnet, so change the chainid
    testnet::unset(root);
    // test setup advances to epoch #2
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 2, 7357001);
    epoch_boundary::test_set_boundary_ready(root, epoch);

    // test the APIs as root
    timestamp::fast_forward_seconds(1); // needed for reconfig
    epoch_boundary::test_trigger(root);
    let epoch = reconfiguration::get_current_epoch();
    assert!(epoch == 3, 7357002);

    // scenario: marlon has no privileges
    // if the epoch Boundary Bit is not set, then abort
    // Note: the Epoch will not change, but we can't assert
    // in the test

    ////// NOTE: not calling this`test_set_boundary_ready`
    // epoch_boundary::test_set_boundary_ready(root, epoch);
    //////

    timestamp::fast_forward_seconds(1);
    diem_governance::trigger_epoch(marlon);
    // aborts
  }
}
