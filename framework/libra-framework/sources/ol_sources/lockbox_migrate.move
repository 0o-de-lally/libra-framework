module ol_framework::lockbox_migrate {
  use ol_framework::lockbox;
  use ol_framework::globals;
  use diem_std::math64;
  use std::vector;
  use diem_std::debug::print;

  /// future proof calc of 1 million coins with scaling
  // TODO: move this to a util in libra_coin
  fun calc_one_million_coins(): u64{
    let decimal_places = globals::get_coin_decimal_places();
    let scaling = math64::pow(10, (decimal_places as u64));
    1 * 1000000 * scaling
  }

  public fun thresholds(): vector<u64> {
    let one_million = calc_one_million_coins();

    vector[
      one_million,
      one_million * 5,
      one_million * 50,
      one_million * 100,
      one_million * 200,
      one_million * 400
    ]
  }

  struct LockSpec has drop{
    amount: u64,
    duration: u64,
  }

  fun make_spec(total: u64): vector<LockSpec> {

    let locks = lockbox::get_default_locks();
    let specs = vector::empty<LockSpec>();

    let one_million = calc_one_million_coins();

    // first tier is 1M coins
    // deduct these from consideration, they stay unlocked
    if (total <= one_million) {
      return vector::empty()
    };

    total = total - one_million;

    // next tier is another bucket of 1 million coins
    let i = 0;

    let thresh = thresholds();
    let len = vector::length(&thresh);

    while (i < len) {
      print(&total);
      let duration = *vector::borrow(&locks, i);
      let this_thresh = *vector::borrow(&thresh, i);
      if (total > this_thresh) {
        vector::push_back(&mut specs, LockSpec{
          amount: this_thresh,
          duration
        });
        // deduct
        total = total - this_thresh;
      } else {
        vector::push_back(&mut specs, LockSpec{
          amount: total,
          duration
        });
        return specs
      };
      i = i + 1;
    };
    return specs
  }

  fun check_spec(amount: u64, specs: &vector<LockSpec>): bool {

    if (amount > calc_one_million_coins()) {
      return true
    };

    let locked_amount = 0;

    let len = vector::length(specs);
    let i = 0;
    while (i < len) {
      let s = vector::borrow(specs, i);
      locked_amount = locked_amount + s.amount;
      i = i + 1;
    };

    if ((locked_amount + calc_one_million_coins()) == amount) {
      return true
    } else {
      return false
    }
  }

  //   // Standard migration function
//   public fun initialize_lockboxes(sig: &signer) {
//     let (_unlocked, total) = ol_account::balance(signer::address_of(sig));

//     // // Split balance into multiple lockboxes
//     // while (total > 0) {
//     //   ol_account::withdraw(sig, lockbox_amount);
//     //   lockbox::add_to_or_create_box(sig, lockbox_amount, 30); // Example duration
//     //   i = i + 1;
//     // }
//   }
// }

  //////// UNIT TESTS ///////
  #[test]
  fun test_make_spec() {
    let one_million = calc_one_million_coins();
    let specs = make_spec(one_million);
    assert!(vector::length(&specs) == 0, 7357001);

    let specs = make_spec(one_million * 2);
    assert!(vector::length(&specs) == 1, 7357002);
    assert!((vector::borrow(&specs, 0)).amount == one_million, 7357003);
    assert!((vector::borrow(&specs, 0)).duration == 12, 7357004);

    let specs = make_spec(one_million * 410);

    print(&specs);
    let check_is_true = check_spec(one_million * 410, &specs);
    assert!(check_is_true, 7357005);

    // iterate over the specs and check the amount match the thresholds()
    let thresh = thresholds();
    let len = vector::length(&specs);
    let i = 0;
    let total = 0;
    while (i < (len - 1)) { // last one will be the remainder
      let s = vector::borrow(&specs, i);
      let this_thresh = *vector::borrow(&thresh, i);
      assert!(s.amount == this_thresh, 7357006);
      total = total + s.amount;
      i = i + 1;
    };
    let last_spec = vector::pop_back(&mut specs);
    print(&last_spec);
    let remainder = last_spec.amount;
    assert!((one_million * 410 - total - one_million) == remainder, 7357007);

  }
}
