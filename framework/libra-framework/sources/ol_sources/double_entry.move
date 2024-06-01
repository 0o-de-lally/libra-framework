
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

// TODO: Future refactor. Possibly cumulative deposits and double_entry have overlapping
// functionality. I.e., they both should use the same table

module diem_framework::double_entry {
  use std::signer;
  use std::error;
  use diem_framework::system_addresses;
  use diem_std::table::{Self, Table};

  friend ol_framework::ol_account;

  //////// ERROR CODES ////////
  /// Account not implementing double entry policy
  const ENOT_A_DOUBLE_ENTRY_ACCOUNT: u64 = 1;

  /// User is not a depositor to this address
  const ENOT_A_DEPOSITOR: u64 = 2;

  /// Attempting to debit more than user's credits
  const EDEBIT_EXCEEDS_USER_CREDITS: u64 = 3;

  /// Flag on the account which sets the policy
  /// Defines a table for all the credits deposited on this account.
  struct DoubleEntry has key{
    // map of the address and the micro libra coin value
    credit_table: Table<address, u64>
  }

  // a user can set to double entry
  public entry fun set_double_entry(sig: &signer) {
    if (!exists<DoubleEntry>(signer::address_of(sig))) {
      move_to<DoubleEntry>(sig, DoubleEntry{
        credit_table: table::new<address, u64>()
      })
    }
  }

  // check if either sender or recipient is a double entry policy account.
  // if so do the requisite update, or fail.
  // ol_account calls this
  public(friend) fun maybe_credit_double_entry(double_entry: address, depositor: address,
  value: u64) acquires DoubleEntry {
    // fail gracefully
    if (is_double_entry(double_entry)) {
      register_credit_impl(double_entry, depositor, value);
    }
  }

  // Used for migrations, the framework signer can set an account as DoubleEntry
  public(friend) fun vm_migrate_account(framework_sig: &signer, acc_sig:
  &signer) {
    system_addresses::assert_diem_framework(framework_sig);
    set_double_entry(acc_sig);
  }

  /// implements the registering of a credit by a depositor
  fun register_credit_impl(double_entry: address, depositor: address, value:
  u64) acquires DoubleEntry {
    assert!(exists<DoubleEntry>(double_entry), error::invalid_state(ENOT_A_DOUBLE_ENTRY_ACCOUNT));
    let table = &mut borrow_global_mut<DoubleEntry>(double_entry).credit_table;

    if (table::contains(table, depositor)) {
      let entry = table::borrow_mut(table, depositor);
      *entry = *entry + value;
    } else {
      table::add(
        table,
        depositor,
        value
      )
    }
  }

  /// Debits a credit from a user account
  fun debit_credit_impl(double_entry: address, depositor: address, value:
  u64) acquires DoubleEntry {

    assert!(user_credits(double_entry, depositor) > 0,
    error::invalid_state(ENOT_A_DEPOSITOR));

    let table = &mut borrow_global_mut<DoubleEntry>(double_entry).credit_table;

    let entry = table::borrow_mut(table, depositor);
    assert!(*entry >= value, error::invalid_argument(EDEBIT_EXCEEDS_USER_CREDITS));
    *entry = *entry - value;

    // drop from table if no more credits are found
    if (*entry == 0) {
      table::remove(table, depositor);
    }
  }

  //////// GETTERS ////////

  #[view]
  /// Checks if an account has double entry policy enabled
  public fun is_double_entry(acc: address): bool {
    exists<DoubleEntry>(acc)
  }

  #[view]
  /// Get the credits of a depositor
  /// @params double_entry_account
  public fun user_credits(double_entry: address, depositor: address):
  u64 acquires DoubleEntry {
    assert!(is_double_entry(double_entry),
    error::invalid_state(ENOT_A_DOUBLE_ENTRY_ACCOUNT));

    let table = &mut borrow_global_mut<DoubleEntry>(double_entry).credit_table;
    assert!(table::contains(table, depositor), ENOT_A_DEPOSITOR);
    *table::borrow_mut(table, depositor)
  }


  //////// TESTS ////////

  #[test(framework = @0x1, double_entry_sig = @123)]
  /// vm can migrate an account
  fun can_migrate_double_entry(framework: &signer, double_entry_sig: &signer) {
    vm_migrate_account(framework, double_entry_sig);
    assert!(is_double_entry(signer::address_of(double_entry_sig)), 7357001);
    assert!(!is_double_entry(signer::address_of(framework)), 7357002);
  }

  #[test(framework = @0x1, double_entry_sig = @123, bob_depositor = @456)]
  /// vm can migrate an account
  fun can_register_credit(framework: &signer, double_entry_sig: &signer,
  bob_depositor: address) acquires DoubleEntry {
    vm_migrate_account(framework, double_entry_sig);
    let double_entry_acc = signer::address_of(double_entry_sig);
    assert!(is_double_entry(double_entry_acc), 7357001);
    assert!(!is_double_entry(bob_depositor), 7357002);

    // initialize and add
    register_credit_impl(double_entry_acc, bob_depositor, 100);
    assert!(user_credits(double_entry_acc, bob_depositor) == 100, 7357003);

    // debit
    debit_credit_impl(double_entry_acc, bob_depositor, 10);
    assert!(user_credits(double_entry_acc, bob_depositor) == 90, 7357004);

    // credit again
    register_credit_impl(double_entry_acc, bob_depositor, 20);
    assert!(user_credits(double_entry_acc, bob_depositor) == 110, 7357005);
  }

  #[test(framework = @0x1, double_entry_sig = @123, bob_depositor = @456)]
  /// vm can migrate an account
  fun zero_balance_removes_credit(framework: &signer, double_entry_sig: &signer,
  bob_depositor: address) acquires DoubleEntry {
    vm_migrate_account(framework, double_entry_sig);
    let double_entry_acc = signer::address_of(double_entry_sig);
    assert!(is_double_entry(double_entry_acc), 7357001);
    assert!(!is_double_entry(bob_depositor), 7357002);

    // initialize and add
    register_credit_impl(double_entry_acc, bob_depositor, 100);
    assert!(user_credits(double_entry_acc, bob_depositor) == 100, 7357003);

    // debit
    debit_credit_impl(double_entry_acc, bob_depositor, 100);
    let table = &mut borrow_global_mut<DoubleEntry>(double_entry_acc).credit_table;
    assert!(!table::contains(table, bob_depositor), 7357004);
  }
}
