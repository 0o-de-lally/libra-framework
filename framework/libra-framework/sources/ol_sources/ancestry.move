module ol_framework::ancestry {
    use std::signer;
    use std::vector;
    use std::error;
    use std::option::{Self, Option};
    use diem_framework::system_addresses;

    friend ol_framework::vouch;
    friend ol_framework::ol_account;
    friend ol_framework::community_wallet_init;

    #[test_only]
    friend ol_framework::root_of_trust_tests;

    /// two accounts are related by ancestry and should not be.
    const EACCOUNTS_ARE_FAMILY: u64 = 1;
    /// no ancestry tree state on chain, this is probably a migration bug.
    const ENO_ANCESTRY_TREE: u64 = 2;
    /// ancestor account not in user tree.
    const ENOT_ANCESTOR: u64 = 3;

    struct Ancestry has key {
      // the full tree back to genesis set
      tree: vector<address>,
    }

    // this is limited to onboarding of users
    public(friend) fun adopt_this_child(parent_sig: &signer, new_account_sig: &signer) acquires Ancestry{
        let parent = signer::address_of(parent_sig);
        set_tree(new_account_sig, parent);
    }

    // private. The user should NEVER be able to change ancestry through a transaction.
    fun set_tree(new_account_sig: &signer, parent: address ) acquires Ancestry {
      let child = signer::address_of(new_account_sig);

      let new_tree = vector::empty<address>();

      // get the parent's ancestry if initialized.
      // if not then this is an edge case possibly a migration error,
      // and we'll just use the parent.
      if (exists<Ancestry>(parent)) {
        let parent_state = borrow_global_mut<Ancestry>(parent);
        let parent_tree = *&parent_state.tree;

        if (vector::length<address>(&parent_tree) > 0) {
          vector::append(&mut new_tree, parent_tree);
        };
      };

      // add the parent to the tree
      vector::push_back(&mut new_tree, parent);
      if (!exists<Ancestry>(child)) {
        move_to<Ancestry>(new_account_sig, Ancestry {
          tree: new_tree,
        });
      } else {
        // this is only for migration cases.
        let child_ancestry = borrow_global_mut<Ancestry>(child);
        child_ancestry.tree = new_tree;
      };
    }

    #[view]
    /// Getter for user's unfiltered tree
    /// @return vector of addresses if there is an ancestry struct
    // Commit NOTE: any transitive function that the VM calls needs to check
    // this struct exists.
    public fun get_tree(addr: address): vector<address> acquires Ancestry {
      if(!exists<Ancestry>(addr)) {
        return vector::empty<address>()
      };

      *&borrow_global<Ancestry>(addr).tree
    }



    #[view]
    /// Getter to see if a account exists in a tree (direct ancestor)
    public fun is_in_tree(ancestor: address, user: address): bool acquires Ancestry {
      let (found, _idx) = vector::index_of(&get_tree(user), &ancestor);
      found
    }

    /// get the degree (hops) between two accounts
    /// if they are related. Assumes ancestor is in the tree of User.
    /// get the degree (hops) between two accounts
    /// if they are related. Assumes ancestor is in the tree of User.
    public(friend) fun get_degree(ancestor: address, user: address): Option<u64> acquires Ancestry {
        // Handle self-reference case
        if (ancestor == user) {
            return option::some(1)
        };

        // Will still abort if no Ancestry struct - this is expected
        let user_tree = get_tree(user);
        let len = vector::length(&user_tree);
        let (found, idx) = vector::index_of(&user_tree, &ancestor);

        if (!found) {
            option::none()
        } else {
            // Calculate actual distance:
            // Length of path from user -> ancestor = len - idx
            // Example:
            // Tree: [great_grandparent, grandparent, parent]
            // To find distance to grandparent (idx 1):
            // len = 3, idx = 1, distance = 3 - 1 = 2 hops
            option::some(len - idx)
        }
    }

    /// helper function to check on transactions (e.g. vouch) if accounts are related
    public(friend) fun assert_unrelated(left: address, right: address) acquires
    Ancestry{
      let (is, _) = is_family(left, right);
      assert!(!is, error::invalid_state(EACCOUNTS_ARE_FAMILY));
    }

    #[view]
    // checks if two addresses have an intersecting permission tree
    // will return true, and the common ancestor at the intersection.
    public fun is_family(left: address, right: address): (bool, address) acquires Ancestry {
      let is_family = false;
      let common_ancestor = @diem_framework; // genesis accounts will have 0x1 as the parent address

      // don't bother checking if we are at the root of the tree
      if (system_addresses::is_reserved_address(left) || system_addresses::is_reserved_address(right)) {
        return (false, common_ancestor)
      };

      // if there is no ancestry info this is a bug, assume related
      // NOTE: we don't want to error here, since the VM calls this
      // on epoch boundary
      // TODO: make it abort, now that epoch boundary is not a problem.
      assert!(exists<Ancestry>(left), ENO_ANCESTRY_TREE);
      assert!(exists<Ancestry>(right), ENO_ANCESTRY_TREE);
      // if (!exists<Ancestry>(left)) return (true, @0x666);
      // if (!exists<Ancestry>(right)) return (true, @0x666);

      let left_tree = get_tree(left);
      let right_tree = get_tree(right);

      // check for direct relationship.
      if (vector::contains(&left_tree, &right)) return (true, right);
      if (vector::contains(&right_tree, &left)) return (true, left);

      let i = 0;
      // check every address on the list if there are overlaps.
      while (i < vector::length<address>(&left_tree)) {

        let family_addr = vector::borrow(&left_tree, i);
        if (vector::contains(&right_tree, family_addr)) {
          is_family = true;
          common_ancestor = *family_addr;

          break
        };
        i = i + 1;
      };

      // for TEST compatibility, either no ancestor is found
      // or the Vm or Framework created accounts at genesis
      if (system_addresses::is_reserved_address(common_ancestor)) {
        is_family = false;
      };
      (is_family, common_ancestor)
    }

    /// given a list, will find a user has one family member in the list.
    /// stops when it finds the first.
    /// this is intended for relatively short lists, such as multisig checking.

    public(friend) fun is_family_one_in_list(
      left: address,
      list: &vector<address>
    ):(bool, Option<address>, Option<address>) acquires Ancestry {
      let k = 0;
      while (k < vector::length(list)) {
        let right = vector::borrow(list, k);
        let (fam, _) = is_family(left, *right);
        if (fam) {
          return (true, option::some(left), option::some(*right))
        };
        k = k + 1;
      };

      (false, option::none(), option::none())
    }

    /// given one list, finds if any pair of addresses are family.
    /// stops on the first pair found.
    /// this is intended for relatively short lists, such as multisig checking.
    public(friend) fun any_family_in_list(
      addr_vec: vector<address>
    ):(bool, Option<address>, Option<address>) acquires Ancestry  {
      let i = 0;
      while (vector::length(&addr_vec) > 1) {
        let left = vector::pop_back(&mut addr_vec);
        let (fam, left_opt, right_opt) = is_family_one_in_list(left, &addr_vec);
        if (fam) {
          return (fam, left_opt, right_opt)
        };
        i = i + 1;
      };

      (false, option::none(), option::none())
    }

    /// to check if within list how many are unrelated to each other.
    /// should not be made public, or have views which can call
    public(friend) fun list_unrelated(list: vector<address>): vector<address> acquires Ancestry {
      // start our list empty
      let unrelated_buddies = vector::empty<address>();

      // iterate through this list to see which accounts are created downstream of others.
      let len = vector::length<address>(&list);
      let  i = 0;
      while (i < len) {
        // for each account in list, compare to the others.
        // if they are unrelated, add them to the list.
        let target_acc = vector::borrow<address>(&list, i);
        // check if the target account is initialized with ancestry.
        if (!exists<Ancestry>(*target_acc)) {
          // if not, skip it.
          i = i + 1;
          continue
        };

        // now loop through all the accounts again, and check if this target
        // account is related to anyone.
        let k = 0;
        while (k < vector::length<address>(&list)) {
          let comparison_acc = vector::borrow(&list, k);
          // skip if you're the same person
          if (comparison_acc != target_acc) {
            // check that the comparison account is initialized
            // with ancestry.
            if (!exists<Ancestry>(*comparison_acc)) {
              k = k + 1;
              continue
            };

            // check ancestry algo
            let (is_fam, _parent) = is_family(*comparison_acc, *target_acc);
            if (!is_fam) {
              if (!vector::contains(&unrelated_buddies, target_acc)) {
                vector::push_back<address>(&mut unrelated_buddies, *target_acc)
              }
            };
          };
          k = k + 1;
        };
        i = i + 1;
      };

      unrelated_buddies
    }

    // admin migration. Needs the signer object for both VM and child to prevent changes.
    fun fork_migrate(
      vm: &signer,
      child_sig: &signer,
      migrate_tree: vector<address>
    ) acquires Ancestry {
      system_addresses::assert_ol(vm);
      let child = signer::address_of(child_sig);

      if (!exists<Ancestry>(child)) {
        move_to<Ancestry>(child_sig, Ancestry {
          tree: migrate_tree,
        });

      } else {
        // this is only for migration cases.
        let child_ancestry = borrow_global_mut<Ancestry>(child);
        child_ancestry.tree = migrate_tree;
      };
    }


    #[test_only]
    public fun test_fork_migrate(
      vm: &signer,
      child_sig: &signer,
      migrate_tree: vector<address>
    ) acquires Ancestry {
      fork_migrate(
        vm,
        child_sig,
        migrate_tree
      );
    }

    #[test_only]
    public fun test_adopt(
      framework: &signer,
      parent_sig: &signer,
      child_sig: &signer
    ) acquires Ancestry {
      system_addresses::assert_diem_framework(framework);
      adopt_this_child(
        parent_sig,
        child_sig
      );
    }
}
