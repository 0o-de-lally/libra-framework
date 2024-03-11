
module ol_framework::not_my_friend {
// Context: In OL all games are a) opt-in b) peer-to-peer. There is no desire
// to have elected comittees to determing network-wide policies. Instead tools
// are created to allow users to declare what games they want to play and with
// whom.

// Problem: people want to know if they are safe, and will only engage in games
// that feel safe. But, blockchains should never censor people. Even
// if you thought it was a good idea, you create a governance problem
// where you'd need a comittee to decide who is good and bad, and then tribunals
// to figure that all out. You've basically reinvented governments.
// The starting place for all blockchains is that people self-select into
// groups, and choose their trusted peers.
// What about the inverse? How do users choose to drop peers? In massively
// scalable communities it's hard for users to always keep track of actors that
// they would ordinarily not want to play games (do business) with.
// Proposal: any user (alice) can publish a list of "not friends. Bob, can
// opt-in and subscribe to this list (and other lists) and request that the
// Libra framework prevent automated actions relatedt to Bob's account happen
// with the list of Alice's non-friends. AKA opt-in network filtering.

// How does this actually work:
// In short the registry is only as credible as the people publishing it. And no
// registry will have any formal authority.
// Anyone can propose a list of people they would rather not do business with.
// There could be valid or spurious reasons for this. Importantly publishing
// this it does not obligate anyone else from adopting it.
// Read again: nothing forces the network or community as a whole to adopt it.
// Users, Validators, Community Wallets, The donors to community wallets, can
// "subscribe" to that list. Now they can feel confident that any transactions
// that they submit, will first check that list, and then prevent those
// transactions from completing (most relevant: payments).
// This module may interact with other modules. For example, vouch.move. The
// user can detemine which information takes precedence: their personal vouches
// overrides the subscribed non-friend list, or the inverse (prevent vouching
// for someone that is on the list).

  use std::error;
  use std::signer;
  use std::vector;
  use std::option::{Self, Option};

  friend ol_framework::ol_account;
  friend ol_framework::vouch;
  friend ol_framework::donor_voice_txs;

  /// no non-friend list published at this address
  const ENO_LIST_PUBLISHED: u64 = 0;

  /// you have not subscribed to any registries of non-friends
  const ENO_REGISTRIES_SUBSCRIBED: u64 = 1;

  /// recipient is not a friend of yours, it's in one of your subscriptions
  // you opted into in your not_my_friend state.
  const ERECIPIENT_NOT_A_FRIEND: u64 = 2;

  /// you are trying to do a transaction with someone who doesn't want to do
  /// business with you.
  /// They have a not_my_friend protection enabled
  const ESENDER_NOT_A_FRIEND: u64 = 3;

  /// any user can publish a registry of people they would rather not do
  /// business with.
  // this is alice in the example above
  struct NotMyFriends has key {
    list: vector<address>
  }

  /// as a user I can subscribe to someone else's registry.
  /// it does not prevent a user from also having their own
  /// NotMyFriends registry.
  /// In that case the system will create a union of all the registries
  // bob in the example above
  struct Subscriptions has key {
    registries: vector<address>,
    // if this list can be overriden by a "vouch" to the account.
    vouch_can_override: bool,
  }

  /// any user can publish a registry of users that they do not want to do
  /// business with. Permissionless.
  public entry fun publish(sig: &signer) {
    if (!exists<NotMyFriends>(signer::address_of(sig))) {
      move_to<NotMyFriends>(sig, NotMyFriends {
        list: vector::empty()
      })
    }
  }

  /// user transaction to add a list to their registry
  public entry fun add_to(sig: &signer, add_list: vector<address>) acquires NotMyFriends {
    let my_addr = signer::address_of(sig);
    assert!(exists<NotMyFriends>(my_addr),
    error::invalid_state(ENO_LIST_PUBLISHED));

    let state = borrow_global_mut<NotMyFriends>(my_addr);
    vector::append(&mut state.list, add_list);
  }

  /// user transaction remove addresses from their registry
  public entry fun remove_from(sig: &signer, remove_list: vector<address>) acquires NotMyFriends {
    let my_addr = signer::address_of(sig);
    assert!(exists<NotMyFriends>(my_addr),
    error::invalid_state(ENO_LIST_PUBLISHED));

    let state = borrow_global_mut<NotMyFriends>(my_addr);
    vector::for_each(remove_list, |a| {
      vector::remove_value(&mut state.list, &a);
    })
  }


  /// A user can subscribe to another user's not-my-friend registry.
  /// system contract functions (e.g. ol_account::transfer()) will check this.
  /// a user can subscribe to multiple lists, where the result is union of lists.
  // In the example above Bob will subscribe to Alice's registry
  public entry fun keep_me_safe(sig: &signer, registry: address) acquires
  Subscriptions {
    maybe_subscribe_init(sig);
    let state = borrow_global_mut<Subscriptions>(signer::address_of(sig));
    vector::push_back(&mut state.registries, registry);
  }

  /// unsubscribe, or remove registry from this account
  public entry fun unsubscribe(sig: &signer, registry: address) acquires
  Subscriptions {
    assert!(exists<Subscriptions>(signer::address_of(sig)), ENO_REGISTRIES_SUBSCRIBED);

    let state = borrow_global_mut<Subscriptions>(signer::address_of(sig));
    vector::remove_value(&mut state.registries, &registry);
  }

  /// transaction for user to choose whether vouching overrides an address in
  // the registries subscribed to
  public entry fun let_vouch_override(sig: &signer, vouch_override: bool)
  acquires Subscriptions {
    assert!(exists<Subscriptions>(signer::address_of(sig)), ENO_REGISTRIES_SUBSCRIBED);
    let state = borrow_global_mut<Subscriptions>(signer::address_of(sig));
    state.vouch_can_override = vouch_override;
  }

  /// a user subscribes to another user's NotMyFriends
  fun maybe_subscribe_init(sig: &signer) {
   if(!exists<Subscriptions>(signer::address_of(sig))) {
    move_to(sig, Subscriptions {
      registries: vector::empty(),
      vouch_can_override: false,
    })
   }
  }

  //////// ASSERT HELPERS ///////
  /// aborts tx if maybe_friend is in a subscriber's registries
  public(friend) fun abort_not_friend(subscriber: address, maybe_friend:
  address) acquires NotMyFriends, Subscriptions {
    assert!(!is_not_a_friend(subscriber, maybe_friend), error::invalid_state(ERECIPIENT_NOT_A_FRIEND));
  }

    /// check in both directions if users have filtered each other out of their
  /// social graphs
  public(friend) fun abort_not_friends_duplex(subscriber: address,
  maybe_friend: address) acquires NotMyFriends, Subscriptions  {
    abort_not_friend(subscriber, maybe_friend);
    assert!(!is_not_a_friend(maybe_friend, subscriber), error::invalid_state(ESENDER_NOT_A_FRIEND));
  }

  //////// GETTERS ////////
  #[view]
  /// checks all registries a user is subscribed to (including own registry) for
  /// inclusion of an address
  public fun is_not_a_friend(subscriber: address, maybe_friend: address): bool acquires
  NotMyFriends, Subscriptions {
    let long_list = vector::empty();
    // first check if subscriber has own registry
    if (exists<NotMyFriends>(subscriber)) {
      let own_registry_state = borrow_global<NotMyFriends>(subscriber);
      vector::append(&mut long_list, own_registry_state.list);
    };

    if (exists<Subscriptions>(subscriber)) {
      let sub_state = borrow_global<Subscriptions>(subscriber);
      vector::for_each(sub_state.registries, |publisher| {
        let other_registry_state = borrow_global<NotMyFriends>(publisher);
        vector::append(&mut long_list, other_registry_state.list);
      })
    };

    if (vector::is_empty(&long_list)) {
      return false
    };
    vector::contains(&long_list, &maybe_friend)
  }

  #[view]
  /// checks if a user is in a particular registry
  public fun is_in_registry(registry: address, user: address): bool acquires
  NotMyFriends {
    if (!exists<NotMyFriends>(registry)) {
      return false
    } else {
      let state = borrow_global<NotMyFriends>(registry);
      vector::contains(&state.list, &user)
    }
  }

  #[view]
  /// show the list of addresses on a user's registry
  public fun get_registry_from(addr: address): Option<vector<address>> acquires
  NotMyFriends {
    if (!exists<NotMyFriends>(addr)) {
      return option::none()
    } else {
      let state = borrow_global<NotMyFriends>(addr);
      return option::some(state.list)
    }
  }
}
