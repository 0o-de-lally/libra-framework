#[test_only]
/// A resource account is used to manage resources independent of an account managed by a user.
/// This contains several utilities to make using resource accounts more effective.
///
/// ## Resource Accounts to manage liquidity pools
///
/// A dev wishing to use resource accounts for a liquidity pool, would likely do the following:
/// 1. Create a new account using `resource_account::create_resource_account`. This creates the
/// account, stores the `signer_cap` within a `resource_account::Container`, and rotates the key to
/// the current accounts authentication key or a provided authentication key.
/// 2. Define the LiquidityPool module's address to be the same as the resource account.
/// 3. Construct a transaction package publishing transaction for the resource account using the
/// authentication key used in step 1.
/// 4. In the LiquidityPool module's `init_module` function, call `retrieve_resource_account_cap`
/// which will retrive the `signer_cap` and rotate the resource account's authentication key to
/// `0x0`, effectively locking it off.
/// 5. When adding a new coin, the liquidity pool will load the capability and hence the signer to
/// register and store new LiquidityCoin resources.
///
/// Code snippets to help:
/// ```
/// fun init_module(resource: &signer) {
///   let dev_address = @DEV_ADDR;
///   let signer_cap = retrieve_resource_account_cap(resource, dev_address);
///   let lp = LiquidityPoolInfo { signer_cap: signer_cap, ... };
///   move_to(resource, lp);
/// }
/// ```
///
/// Later on during a coin registration:
/// ```
/// public fun add_coin<X, Y>(lp: &LP, x: Coin<x>, y: Coin<y>) {
///     if(!exists<LiquidityCoin<X, Y>(LP::Address(lp), LiquidityCoin<X, Y>)) {
///         let mint, burn = Coin::initialize<LiquidityCoin<X, Y>>(...);
///         move_to(&create_signer_with_capability(&lp.cap), LiquidityCoin<X, Y>{ mint, burn });
///     }
///     ...
/// }
/// ```
/// ## Resource accounts to manage an account for module publishing (i.e., contract account)
///
/// A dev wishes to have an account dedicated to managing a contract. The contract itself does not
/// require signer post initialization. The dev could do the following:
/// 1. Create a new account using `resource_account::create_resource_account_and_publish_package`.
/// This creates the account and publishes the package for that account.
/// 2. At a later point in time, the account creator can move the signer capability to the module.
///
/// ```
/// struct MyModuleResource has key {
///     ...
///     resource_signer_cap: Option<SignerCapability>,
/// }
///
/// public fun provide_signer_capability(resource_signer_cap: SignerCapability) {
///    let account_addr = account::get_signer_capability_address(resource_signer_cap);
///    let resource_addr = type_info::account_address(&type_info::type_of<MyModuleResource>());
///    assert!(account_addr == resource_addr, EADDRESS_MISMATCH);
///    let module = borrow_global_mut<MyModuleResource>(account_addr);
///    module.resource_signer_cap = option::some(resource_signer_cap);
/// }
/// ```

module diem_framework::resource_account {
    use std::error;
    use std::signer;
    use std::vector;
    use diem_framework::account;
    use diem_std::simple_map::{Self, SimpleMap};

    friend ol_framework::ol_account;

    #[test_only]
    use diem_framework::diem_coin::DiemCoin;
    #[test_only]
    use diem_framework::coin;



    /// Container resource not found in account
    const ECONTAINER_NOT_PUBLISHED: u64 = 1;
    /// The resource account was not created by the specified source account
    const EUNAUTHORIZED_NOT_OWNER: u64 = 2;

    const ZERO_AUTH_KEY: vector<u8> = x"0000000000000000000000000000000000000000000000000000000000000000";

    struct Container has key {
        store: SimpleMap<address, account::SignerCapability>,
    }

    /// Creates a new resource account and rotates the authentication key to either
    /// the optional auth key if it is non-empty (though auth keys are 32-bytes)
    /// or the source accounts current auth key.
    fun create_resource_account(
        origin: &signer,
        seed: vector<u8>,
        optional_auth_key: vector<u8>,
    ) acquires Container {
        let (resource, resource_signer_cap) = account::create_resource_account(origin, seed);
        rotate_account_authentication_key_and_store_capability(
            origin,
            resource,
            resource_signer_cap,
            optional_auth_key,
        );
    }


    /// rotates the account key and stores the signer capability (does not
    /// change an address)
    fun rotate_account_authentication_key_and_store_capability(
        origin: &signer,
        resource: signer,
        resource_signer_cap: account::SignerCapability,
        optional_auth_key: vector<u8>,
    ) acquires Container {
        let origin_addr = signer::address_of(origin);
        if (!exists<Container>(origin_addr)) {
            move_to(origin, Container { store: simple_map::create() })
        };

        let container = borrow_global_mut<Container>(origin_addr);
        let resource_addr = signer::address_of(&resource);
        simple_map::add(&mut container.store, resource_addr, resource_signer_cap);

        let auth_key = if (vector::is_empty(&optional_auth_key)) {
            account::get_authentication_key(origin_addr)
        } else {
            optional_auth_key
        };
        account::rotate_authentication_key_internal(&resource, auth_key);
    }

    /// When called by the resource account, it will retrieve the capability associated with that
    /// account and rotate the account's auth key to 0x0 making the account inaccessible without
    /// the SignerCapability.
    public fun retrieve_resource_account_cap(
        resource: &signer,
        source_addr: address,
    ): account::SignerCapability acquires Container {
        assert!(exists<Container>(source_addr), error::not_found(ECONTAINER_NOT_PUBLISHED));

        let resource_addr = signer::address_of(resource);
        let (resource_signer_cap, empty_container) = {
            let container = borrow_global_mut<Container>(source_addr);
            assert!(simple_map::contains_key(&container.store, &resource_addr), error::invalid_argument(EUNAUTHORIZED_NOT_OWNER));
            let (_resource_addr, signer_cap) = simple_map::remove(&mut container.store, &resource_addr);
            (signer_cap, simple_map::length(&container.store) == 0)
        };

        if (empty_container) {
            let container = move_from(source_addr);
            let Container { store } = container;
            simple_map::destroy_empty(store);
        };

        account::rotate_authentication_key_internal(resource, ZERO_AUTH_KEY);
        resource_signer_cap
    }

    #[view]
    //////// 0L ////////
    /// is the account properly configurated as a resource account
    public fun is_resource_account(addr: address): bool {
      account::get_authentication_key(addr) == ZERO_AUTH_KEY
    }

    #[test(user = @0x1111)]
    fun test_create_account_and_retrieve_cap(user: signer) acquires Container {
        let user_addr = signer::address_of(&user);
        account::create_account(user_addr);

        let seed = x"01";

        create_resource_account(&user, copy seed, vector::empty());
        let container = borrow_global<Container>(user_addr);

        let resource_addr = diem_framework::account::create_resource_address(&user_addr, seed);
        let resource_cap = simple_map::borrow(&container.store, &resource_addr);

        let resource = account::create_signer_with_capability(resource_cap);
        let _resource_cap = retrieve_resource_account_cap(&resource, user_addr);
    }

    #[test(user = @0x1111)]
    #[expected_failure(abort_code = 0x10002, location = diem_std::simple_map)]
    fun test_create_account_and_retrieve_cap_resource_address_does_not_exist(user: signer) acquires Container {
        let user_addr = signer::address_of(&user);
        account::create_account(user_addr);

        let seed = x"01";
        let seed2 = x"02";

        create_resource_account(&user, seed2, vector::empty());
        let container = borrow_global<Container>(user_addr);

        let resource_addr = account::create_resource_address(&user_addr, seed);
        let resource_cap = simple_map::borrow(&container.store, &resource_addr);

        let resource = account::create_signer_with_capability(resource_cap);
        let _resource_cap = retrieve_resource_account_cap(&resource, user_addr);
    }

    // #[test(framework = @0x1, user = @0x1234)]
    // fun with_coin(framework: signer, user: signer) acquires Container {
    //     let user_addr = signer::address_of(&user);
    //     diem_framework::diem_account::create_account(copy user_addr);

    //     let (burn, mint) = diem_framework::diem_coin::initialize_for_test(&framework);
    //     let coin = coin::mint<DiemCoin>(100, &mint);
    //     coin::deposit(copy user_addr, coin);

    //     let seed = x"01";
    //     create_resource_account_and_fund(&user, copy seed, vector::empty(), 10);

    //     let resource_addr = diem_framework::account::create_resource_address(&user_addr, seed);
    //     coin::transfer<DiemCoin>(&user, resource_addr, 10);

    //     coin::destroy_burn_cap(burn);
    //     coin::destroy_mint_cap(mint);
    // }

    #[test(framework = @0x1, user = @0x2345)]
    #[expected_failure(abort_code = 0x60005, location = diem_framework::coin)]
    fun without_coin(framework: signer, user: signer) acquires Container {
        let user_addr = signer::address_of(&user);
        diem_framework::diem_account::create_account(user_addr);

        let seed = x"01";
        create_resource_account(&user, copy seed, vector::empty());

        let resource_addr = diem_framework::account::create_resource_address(&user_addr, seed);
        let (burn, mint) = diem_framework::diem_coin::initialize_for_test(&framework);
        let coin = coin::mint<DiemCoin>(100, &mint);
        coin::deposit(resource_addr, coin);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }
}
