
// Creates a ledger  on the account which will track credits and debits
// from individual accounts. Useful for custody providers, bridges, exchanges
// and other use cases where the owner of the account would like to increase
// trust from the depositors (creditors) of that account.

// All credits happen automatically using the normal ol_account::transfer
// functions.
// All creditors to the account can thus see query on chain how much of the
// custodian's accounts have the senders credits/collateral.
// All debits by the owner of an account with the double_entry policy, must use
// a specialized tranfer function which always must deduct from an existing
// account's credits.
// There are edge cases where an owner may debit an amount of coin which is
// greater than a single address's credits. By design these transactions will
// fail, and the owner of an account must split the transaction into two
// individual transactions. While there may be legitimate cases for this, and it
// may add work for the owner, it's preferable to make make such transactions
// explicit (plus most users taking advantage of double entry, will be doing so
// programattically).

module diem_framework::double_entry {
  use std::signer;
  use diem_framework::system_addresses;
  use diem_std::table::{Self, Table};

  /// Flag on the account which sets the policy
  struct DoubleEntry has key {}

  /// Defines a table for all the credits deposited on this account.
  struct Depositors has key{
    // map of the address and the micro libra coin value
    credit_table: Table<address, u64>
  }

  // a user can set to double entry
  public entry fun set_double_entry(sig: &signer) {
    if (!exists<DoubleEntry>(signer::address_of(sig))) {
      move_to<DoubleEntry>(sig, DoubleEntry{})
    }
  }

  // Used for migrations, the framework signer can set an account as DoubleEntry
  public(friend) fun vm_migrate_account(framework_sig: &signer, acc_sig:
  &signer) {
    system_addresses::assert_diem_framework(framework_sig);
    if (!exists<DoubleEntry>(signer::address_of(acc_sig))) {
      move_to<DoubleEntry>(acc_sig, DoubleEntry{})
    }
  }

  fun register_credit_impl(account: address, value: u64) acquires Depositors {
    let table = &mut borrow_global_mut<Depositors>(@ol_framework).credit_table;
    if (table::contains(table, account)) {
      let entry = table::borrow_mut(table, account);
      *entry = *entry + value;
    } else {
      table::add(
        table,
        account,
        value
      )
    }
  }

  #[view]
  /// Checks if an account has double entry policy enabled
  public fun is_double_entry(acc: address): bool {
    exists<DoubleEntry>(acc)
  }

  #[test(framework = @0x1, alice = @123)]
  /// vm can migrate an account
  fun can_migrate_double_entry(framework: &signer, alice: &signer) {
    vm_migrate_account(framework, alice);
    assert!(is_double_entry(signer::address_of(alice)), 7357001);
    assert!(!is_double_entry(signer::address_of(framework)), 7357002);

  }

}
