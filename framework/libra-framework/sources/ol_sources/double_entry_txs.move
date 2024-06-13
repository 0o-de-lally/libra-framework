// users that opted into double entry tracking cannot use the simple end-user
// ol_account::transfer function (just as multisig, and donor voice accounts
// cannot).
// This file is separate from double_entry to prevent dependency cycling
// Every time a transfer happens in the double_entry policy, an existing
// depositor needs to have a credit adjusted, before funds can be sent to
// another party.
// Given an example of a bridge account.
module diem_framework::double_entry_txs {

  // one users coins were transferred to another user's account after an off
  // chain deal
  public entry fun swap_tx(double_entry_sig: &signer, destination:
  address, amount: u64, depositor_account: address) {
    // funds will be sent from custody account to destination.
    // depositor account will be credited fully for this amount.
    // NOTE: check that the amounts are full.

  }

  /// one users coins were transferred to another account on another chain
  /// we can write a memo with the address of the offchain account.
  /// The custodial bridge operator will want to do this so that the depositor's
  /// credit is reduced, and as such the bridge operator is not carrying that liability.
  public entry fun bridge_tx(double_entry_sig: &signer, destination:
  address, amount: u64, depositor_account: address) {
    // funds will be sent from custody account to destination.
    // depositor account will be credited fully for this amount.
    // NOTE: check that the amounts are full.

  }

  /// an exchange is crediting a user when they deposited LIBRA to the exchange
  /// custody
  public entry fun exchange_tx(double_entry_sig: &signer, destination:
  address, amount: u64, depositor_account: address) {
    // funds will be sent from custody account to destination.
    // depositor account will be credited fully for this amount.
    // NOTE: check that the amounts are full.

  }


}
