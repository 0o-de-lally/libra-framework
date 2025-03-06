// Copyright (c) The Libra Core Contributors
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0
// Original source:
// https://github.com/diem/diem/blob/782b31cb08eeb717ea2b6f3edbf616b13fd4cae8/language/move-lang/stdlib/modules/libra_coin.move
// Original Commit:
// https://github.com/diem/diem/commit/782b31cb08eeb717ea2b6f3edbf616b13fd4cae8


module ol_framework::libra_coin {
    use std::signer;

    use diem_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use diem_framework::system_addresses;

    // use ol_framework::globals;
    use ol_framework::gas_coin::{Self, GasCoin};

    friend diem_framework::genesis;
    friend ol_framework::genesis_migration;
    friend ol_framework::pledge_accounts;

    const MAX_U64: u128 = 18446744073709551615;

    /// Account does not have mint capability
    const ENO_CAPABILITIES: u64 = 1;
    /// Mint capability has already been delegated to this specified address
    const EALREADY_DELEGATED: u64 = 2;
    /// Cannot find delegation of mint capability to this account
    const EDELEGATION_NOT_FOUND: u64 = 3;
    /// Supply somehow above MAX_U64
    const ESUPPLY_OVERFLOW: u64 = 4;

    struct LibraCoin has key { /* new games for society */}

    struct FinalMint has key {
        value: u64,
    }

    struct MintCapStore has key {
        mint_cap: MintCapability<GasCoin>,
    }

    /// Delegation token created by delegator and can be claimed by the delegatee as MintCapability.
    struct DelegatedMintCapability has store {
        to: address
    }

    /// The container stores the current pending delegations.
    struct Delegations has key {
        inner: vector<DelegatedMintCapability>,
    }

    /// Can only called during genesis to initialize the Diem coin.
    public(friend) fun initialize(diem_framework: &signer) {
      gas_coin::initialize(diem_framework);
    }

    /// FOR TESTS ONLY
    /// Can only called during genesis to initialize the Diem coin.
    public(friend) fun initialize_for_core(diem_framework: &signer):
    (BurnCapability<GasCoin>, MintCapability<GasCoin>) {
        gas_coin::initialize_for_core(diem_framework)
    }

    fun has_mint_capability(account: &signer): bool {
        exists<MintCapStore>(signer::address_of(account))
    }

    // /// Only called during genesis to destroy the diem framework account's mint capability once all initial validators
    // /// and accounts have been initialized during genesis.
    // public(friend) fun destroy_mint_cap(diem_framework: &signer) acquires MintCapStore {
    //     system_addresses::assert_diem_framework(diem_framework);
    //     let MintCapStore { mint_cap } = move_from<MintCapStore>(@diem_framework);
    //     coin::destroy_mint_cap(mint_cap);
    // }

    // at genesis we need to init the final supply
    // done at genesis_migration
    fun genesis_set_final_supply(diem_framework: &signer,
    final_supply: u64) acquires FinalMint {
      system_addresses::assert_ol(diem_framework);

      if (!exists<FinalMint>(@ol_framework)) {
        move_to(diem_framework, FinalMint {
          value: final_supply
        });
      } else {
        let state = borrow_global_mut<FinalMint>(@ol_framework);
        state.value = final_supply
      }
    }

    #[test_only]
    public fun test_set_final_supply(diem_framework: &signer,
    final_supply: u64) {
      gas_coin::test_set_final_supply(diem_framework, final_supply);
    }

    #[view]
    /// get the original final supply from genesis
    public fun get_final_supply(): u64 {
      gas_coin::get_final_supply()
    }


    // NOTE: these public functions are duplicated here to isolate the coin.move
    // from generic implementations
    /// libra coin value
    public fun value(coin: &Coin<GasCoin>): u64 {
      gas_coin::value(coin)
    }
    /// simple libra coin balance at this address,
    /// without considering locks or index
    public fun balance(addr: address): u64 {
      gas_coin::balance(addr)
    }

    /// extract coin by splitting a coin
    public fun extract(coin: &mut Coin<GasCoin>, amount: u64): Coin<GasCoin> {
      gas_coin::extract(coin, amount)
    }
    /// extract all remaining value from a coin
    public fun extract_all(coin: &mut Coin<GasCoin>): Coin<GasCoin> {
      gas_coin::extract_all(coin)
    }

    /// merge two libra coins back together
    public fun merge(dst_coin: &mut Coin<GasCoin>, source_coin: Coin<GasCoin>) {
      gas_coin::merge(dst_coin, source_coin)
    }


    /// try to register an account to use libra coin if noy yet enabled
    public fun maybe_register(sig: &signer) {
    if (!coin::is_account_registered<GasCoin>(signer::address_of(sig))) {
        coin::register<GasCoin>(sig);
      };
    }
    #[view]
    /// get the gas coin supply. Helper which wraps coin::supply and extracts option type
    // NOTE: there is casting between u128 and u64, but 0L has final supply below the u64.
    public fun supply(): u64 {
      gas_coin::supply()
    }
    #[view]
    /// debugging view
    public fun supply_128(): u128 {
      gas_coin::supply_128()
    }


    #[test_only]
    public fun restore_mint_cap(diem_framework: &signer, mint_cap: MintCapability<GasCoin>) {
        gas_coin::restore_mint_cap(diem_framework, mint_cap)
    }

    #[test_only]
    public fun extract_mint_cap(diem_framework: &signer):
    MintCapability<GasCoin> {
        gas_coin::extract_mint_cap(diem_framework)
    }


    /// FOR TESTS ONLY
    /// The `core addresses` sudo account is used to execute system transactions for testing
    /// Can only be called during genesis for tests to grant mint capability to diem framework and core resources
    /// accounts.
    public(friend) fun configure_accounts_for_test(
        diem_framework: &signer,
        core_resources: &signer,
        mint_cap: MintCapability<GasCoin>,
    ){
      gas_coin::configure_accounts_for_test(diem_framework, core_resources, mint_cap)
    }

    // NOTE: needed for smoke tests
    // TODO: guard some other way besides using the testing root account.
    /// Root account can mint to an address. Only used for genesis and tests.
    /// The "root" account in smoke tests has some privileges.
    public entry fun mint_to_impl(
        root: &signer,
        dst_addr: address,
        amount: u64,
    ) {
      gas_coin::mint_to_impl(root, dst_addr, amount);
    }

    #[test_only]
    public entry fun test_mint_to(
        root: &signer,
        dst_addr: address,
        amount: u64,
    ) {
      system_addresses::assert_ol(root);
      mint_to_impl(root, dst_addr, amount);
    }

    // /// Only callable in tests and testnets where the core resources account exists.
    // /// Create delegated token for the address so the account could claim MintCapability later.
    // public entry fun delegate_mint_capability(account: signer, to: address) acquires Delegations {
    //     system_addresses::assert_core_resource(&account);
    //     let delegations = &mut borrow_global_mut<Delegations>(@core_resources).inner;
    //     let i = 0;
    //     while (i < vector::length(delegations)) {
    //         let element = vector::borrow(delegations, i);
    //         assert!(element.to != to, error::invalid_argument(EALREADY_DELEGATED));
    //         i = i + 1;
    //     };
    //     vector::push_back(delegations, DelegatedMintCapability { to });
    // }

    // /// Only callable in tests and testnets where the core resources account exists.
    // /// Claim the delegated mint capability and destroy the delegated token.
    // public entry fun claim_mint_capability(account: &signer) acquires Delegations, MintCapStore {
    //     let maybe_index = find_delegation(signer::address_of(account));
    //     assert!(option::is_some(&maybe_index), EDELEGATION_NOT_FOUND);
    //     let idx = *option::borrow(&maybe_index);
    //     let delegations = &mut borrow_global_mut<Delegations>(@core_resources).inner;
    //     let DelegatedMintCapability { to: _ } = vector::swap_remove(delegations, idx);

    //     // Make a copy of mint cap and give it to the specified account.
    //     let mint_cap = borrow_global<MintCapStore>(@core_resources).mint_cap;
    //     move_to(account, MintCapStore { mint_cap });
    // }

    // fun find_delegation(addr: address): Option<u64> acquires Delegations {
    //     let delegations = &borrow_global<Delegations>(@core_resources).inner;
    //     let i = 0;
    //     let len = vector::length(delegations);
    //     let index = option::none();
    //     while (i < len) {
    //         let element = vector::borrow(delegations, i);
    //         if (element.to == addr) {
    //             index = option::some(i);
    //             break
    //         };
    //         i = i + 1;
    //     };
    //     index
    // }

    // #[test_only]
    // use diem_framework::aggregator_factory;

    #[test_only]
    public fun initialize_for_test(diem_framework: &signer): (BurnCapability<GasCoin>, MintCapability<GasCoin>) {
       gas_coin::initialize_for_test(diem_framework)
    }
    // COMMIT NOTE: Deduplicate the initialization by lazy initializing aggregator_factory.move
}
