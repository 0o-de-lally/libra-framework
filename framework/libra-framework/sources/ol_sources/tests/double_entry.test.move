#[test_only]
module ol_framework::test_double_entry {
  use std::signer;
  use ol_framework::double_entry;
  // use ol_framework::libra_coin;
  // use ol_framework::ol_account;
  // use diem_framework::coin;

  #[test(double_entry_sig = @123, bob_depositor = @456)]
  /// vm can migrate an account
  fun user_tx_set_double_entry(double_entry_sig: &signer,
  bob_depositor: address) {
    double_entry::set_double_entry(double_entry_sig);
    let double_entry_acc = signer::address_of(double_entry_sig);
    assert!(double_entry::is_double_entry(double_entry_acc), 7357001);
    assert!(!double_entry::is_double_entry(bob_depositor), 7357002);

    // // initialize and add
    // register_credit_impl(double_entry_acc, bob_depositor, 100);
    // assert!(user_credits(double_entry_acc, bob_depositor) == 100, 7357003);

    // // debit
    // debit_credit_impl(double_entry_acc, bob_depositor, 10);
    // assert!(user_credits(double_entry_acc, bob_depositor) == 90, 7357004);

    // // credit again
    // register_credit_impl(double_entry_acc, bob_depositor, 20);
    // assert!(user_credits(double_entry_acc, bob_depositor) == 110, 7357005);
  }
}
