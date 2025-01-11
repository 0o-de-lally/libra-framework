module ol_framework::lockbox_migrate {
  // use ol_framework::ol_account;
  use ol_framework::lockbox;
  use diem_std::math64;
  use diem_std::coin;
  // use diem_std::signer;
  use std::vector;
  use ol_framework::libra_coin::LibraCoin;

  // const DEFAULT_LOCKS: vector<u64> = vector[1*12, 4*12, 8*12, 16*12, 24*12, 32*12];

  /// future proof calc of 1 million coins with scaling
  // TODO: move this to a util in libra_coin
  fun calc_one_million_coins(): u64{
    let decimal_places = coin::decimals<LibraCoin>();
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

  // include drop

  struct LockSpec has drop{
    amount: u64,
    duration: u64,
  }

  // use diem_std::system_addresses;

  fun make_spec(total: u64): vector<LockSpec> {
    let decimal_places = coin::decimals<LibraCoin>();
    let scaling = math64::pow(10, (decimal_places as u64));
    let locks = lockbox::get_default_locks();
    let specs = vector::empty<LockSpec>();

    let one_million = 1 * 1000000 * scaling;

    // first tier is 1M coins
    // deduct these from consideration, they stay unlocked
    total = total - one_million;

    // next tier is another bucket of 1 million coins
    let i = 0;
    let len = vector::length(&locks);
    while (i < len) {
      let duration = *vector::borrow(&locks, i);
      if (total > one_million) {
        vector::push_back(&mut specs, LockSpec{
          amount: one_million,
          duration
        });
        // deduct
        total = total - one_million;
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
    // if (total > one_million) {
    //   vector::push_back(&mut specs, LockSpec{
    //     amount: one_million,
    //     duration: vector::borrow(&locks, 1) // one year
    //   });
    //   // deduct
    //   total = total - one_million;
    // } else {
    //   vector::push_back(&mut specs, LockSpec{
    //     amount: total,
    //     duration: vector::borrow(&locks, 1) // one year
    //   });
    //   return specs;
    // };

    // // next tier is a bucket of 5 million coins
    // let five_million = 5 * one_million;

    // if (total > five_million) {

    //   vector::push_back(&mut specs, LockSpec{
    //     amount: five_million,
    //     duration: vector::borrow(&locks, 1) // one year
    //   });
    //   // deduct
    //   total = total - five_million;
    // };

    // // next tier is 10m
    // let ten_million = 5 * one_million;

    // if (total > ten_million) {
    //   vector::push_back(&mut specs, LockSpec{
    //     amount: one_million,
    //     duration: vector::borrow(&locks, 0)
    //   });
    //   total = total - ten_million;
    // }



    // return specs
  }
  //////// UNIT TESTS ///////
  fun test_make_spec() {
    use diem_std::debug::print;
    let one_million = calc_one_million_coins();
    let specs = make_spec(one_million);
    print(&@0x1);
    print(&specs);
  }
}
//   // returns the lock duration based on the amount
//   fun migration_tiers(amount: u64): u64 {
//     let decimal_places = coin::decimals<LibraCoin>();
//     let scaling = math64::pow(10, (decimal_places as u64));
//     let locks = lockbox::get_default_locks();
//     // below 100K ignore
//     if (amount < 100000 * scaling) {
//       return 0
//     } else if (amount < 5 * 1000000 * scaling) {
//       return *vector::borrow(&locks, 1)
//     } else if (amount < 10 * 1000000 * scaling) {
//       return 90
//     } else {
//       return 120
//     }
//   }
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

  // // Master account override function
  // public fun migrate_account(
  //   framework: &signer,
  //   account_to_migrate: address,
  //   lockbox_duration: u64
  // ) {
  //   system_addresses::assert_diem_framework(framework);

  //   let (unlocked, total) = ol_account::balance(account_to_migrate);

  //   let i = 0;
  //   while (i < 10) {
  //     Lockbox::create_lockbox(&account, lockbox_amount, lockbox_duration);
  //     i = i + 1;
  //   };
  //     Lockbox::create_lockbox(&account, lockbox_amount, lockbox_duration);
  //   }
  // }
