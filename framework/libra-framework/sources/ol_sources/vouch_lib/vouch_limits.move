
module ol_framework::vouch_limits {
    use std::error;
    use std::vector;
    use ol_framework::page_rank_lazy;
    use ol_framework::epoch_helper;
    use ol_framework::vouch;

    use diem_std::debug::print;

    friend ol_framework::vouch_txs;

    /// Maximum number of vouches
    const BASE_MAX_VOUCHES: u64 = 10;

    /// Maximum number of vouches allowed to be given per epoch
    const MAX_VOUCHES_PER_EPOCH: u64 = 1;

    // Add these constants for revocation limits
    /// Maximum number of revocations allowed in a single epoch
    const MAX_REVOCATIONS_PER_EPOCH: u64 = 2;

    /// Cooldown period (in epochs) required after a revocation before giving a new vouch
    const REVOCATION_COOLDOWN_EPOCHS: u64 = 3;

    //////// ERRORS ////////
    /// Revocation limit reached. You cannot revoke any more vouches in this epoch.
    const EREVOCATION_LIMIT_REACHED: u64 = 7;

    /// Cooldown period after revocation not yet passed
    const ECOOLDOWN_PERIOD_ACTIVE: u64 = 8;

    /// Vouch limit reached: above max ceiling
    const EMAX_LIMIT_GIVEN_CEILING: u64 = 9;

    /// Vouch limit reached: above number of vouches received
    const EMAX_LIMIT_GIVEN_BY_RECEIPT: u64 = 10;

    /// Vouch limit reached: because of quality of your voucher
    const EMAX_LIMIT_GIVEN_BY_SCORE: u64 = 11;

    /// Vouch limit reached: too many given in current epoch
    const EMAX_VOUCHES_PER_EPOCH: u64 = 12;


    /// GIVEN VOUCHES CHECK
    /// The maximum number of vouches which can be given
    /// is the lowest of three numbers:
    /// a. below the max safety threshold of the system
    /// b. below the count of active vouches received + 1
    /// c. below the max vouches as calculated by the users' vouch score quality
    /// d. no more than 1 vouch per epoch

    // check if we are trying to update the vouching of an existing account
    // or adding a new vouch to a new account
    public(friend) fun assert_under_limit(grantor_acc: address, vouched_account: address) {
      let given_vouches = vouch::get_given_vouches_not_expired(grantor_acc);

      let (found, _i) = vector::index_of(&given_vouches, &vouched_account);

      // don't check max vouches if we are just extending the expiration
      if (!found) {
        // are we hitting the limit of max vouches
        assert_max_vouches(grantor_acc);
      }
    }

    fun assert_max_vouches(grantor_acc: address) {
      assert_safety_ceiling_vouches(grantor_acc);
      assert_max_vouches_by_score(grantor_acc);
      assert_received_limit_vouches(grantor_acc);
      assert_epoch_vouches_limit(grantor_acc);
      // Check if cooldown period has passed since last revocation
      assert_cooldown_period(grantor_acc);
    }

    fun assert_safety_ceiling_vouches(grantor_acc: address) {
        // Get the received vouches that aren't expired
        let given_vouches = vouch::get_given_vouches_not_expired(grantor_acc);

        assert!(vector::length(&given_vouches) <= BASE_MAX_VOUCHES, error::invalid_state(EMAX_LIMIT_GIVEN_CEILING));
    }

      fun assert_received_limit_vouches(account: address) {
        // Get the received vouches that aren't expired
        let received_vouches = vouch::true_friends(account);
        let received_count = vector::length(&received_vouches);
        let given_vouches = vouch::get_given_vouches_not_expired(account);

        // Base case: Always allow at least vouches received + 1
        let max_allowed = received_count + 1;
        assert!(vector::length(&given_vouches) <= max_allowed, error::invalid_state(EMAX_LIMIT_GIVEN_BY_RECEIPT));
    }

    // a user should not be able to give more vouches than their quality score allows
    fun assert_max_vouches_by_score(grantor_acc: address) {
      // check if the grantor has already reached the limit of vouches
      let given_vouches = vouch::get_given_vouches_not_expired(grantor_acc);
      let max_allowed = calculate_score_limit(grantor_acc);

      assert!(
        vector::length(&given_vouches) <= max_allowed,
        error::invalid_state(EMAX_LIMIT_GIVEN_BY_SCORE)
      );
    }



    // Check if user has already given the maximum number of vouches allowed per epoch
    fun assert_epoch_vouches_limit(grantor_acc: address) {
      let given_this_epoch = vouch::get_given_this_epoch(grantor_acc);

      // Check if user has exceeded vouches in this epoch
      assert!(
        given_this_epoch < MAX_VOUCHES_PER_EPOCH,
        error::invalid_state(EMAX_VOUCHES_PER_EPOCH)
      );
    }

    /// Calculate the maximum number of vouches a user should be able to give based on their trust score
    public fun calculate_score_limit(grantor_acc: address): u64 {
        // Calculate the quality using the social distance method
        // This avoids dependency on page_rank_lazy
        let total_quality = page_rank_lazy::get_trust_score(grantor_acc);
        print(&total_quality);

        // For accounts with low quality vouchers,
        // we restrict further how many they can vouch for
        let max_allowed = 1;

        // TODO: collect analytics data to review this
        if (total_quality >= 2 && total_quality < 200) {
            max_allowed = 3;
        } else if (total_quality >= 200 && total_quality < 400) {
            max_allowed = 5;
        } else if (total_quality >= 400) {
            max_allowed = 10;
        };

        max_allowed
    }

    /// REVOCATION CHECKS
    /// within a period a user might try to add and revoke
    /// many users. As such there are some checks to make on
    /// revocation.
    /// 1. Over a lifetime of the account you cannot revoke more
    /// than you have vouched for.
    /// 2. You cannot revoke more times than the current
    /// amount of vouches you currently have received.

    public(friend) fun assert_revoke_limit(grantor_acc: address) {
      let revokes = vouch::get_revocations_this_epoch(grantor_acc);

      // Check if user has exceeded revocations in this epoch
      assert!(
        revokes < MAX_REVOCATIONS_PER_EPOCH,
        error::invalid_state(EREVOCATION_LIMIT_REACHED)
      );
    }

    // Check if enough time has passed since last revocation before giving a new vouch
    fun assert_cooldown_period(grantor_acc: address) {
      assert!(
        cooldown_period_passed(grantor_acc),
        error::invalid_state(ECOOLDOWN_PERIOD_ACTIVE)
      );
    }


        /// Helper function to check if the cooldown period has passed
    fun cooldown_period_passed(grantor_acc: address): bool {
      let current_epoch = epoch_helper::get_current_epoch();
      let last_revocation_epoch = vouch::get_last_revocation_epoch(grantor_acc);

      // Check if enough epochs have passed since last revocation
      current_epoch >= last_revocation_epoch + REVOCATION_COOLDOWN_EPOCHS
    }

    // /// Helper function to check how many vouches are left this epoch
    // fun remaining_epoch_vouches(addr: address): u64 {
    //   let current_epoch = epoch_helper::get_current_epoch();
    //   let state = borrow_global<VouchesLifetime>(addr);

    //   // Reset counter if we're in a new epoch
    //   if (state.last_given_epoch != current_epoch) {
    //     return MAX_VOUCHES_PER_EPOCH
    //   };

    //   // Calculate remaining vouches for this epoch
    //   if (state.given_this_epoch >= MAX_VOUCHES_PER_EPOCH) {
    //     0
    //   } else {
    //     MAX_VOUCHES_PER_EPOCH - state.given_this_epoch
    //   }
    // }

    #[view]
    // /// Returns the number of vouches a user can still give based on system limits.
    // /// This takes into account all constraints:
    // /// 1. Base maximum limit (10 vouches)
    // /// 2. Score-based limit
    // /// 3. Received vouches + 1 limit
    // /// 4. Per-epoch limit
    // /// The returned value is the minimum of all these limits minus current given vouches.
    public fun get_remaining_vouches(_addr: address): u64 {
        0
    }
    //   // Check if account is initialized
    //   if (!vouch::is_init(addr)) {
    //     return 0
    //   };
    //   // Check cooldown period
    //   if (!cooldown_period_passed(addr)) {
    //     return 0
    //   };

    //   // Get current non-expired vouches
    //   let given_count = vector::length(&vouch::get_given_vouches_not_expired(addr));

    //   // Calculate all limits
    //   let base_limit = BASE_MAX_VOUCHES;
    //   let score_limit = calculate_score_limit(addr);
    //   print(&3333);
    //   print(&score_limit);

    //   // Received limit: non-expired received vouches + 1
    //   let received_vouches = vouch::true_friends(addr);
    //   let received_limit = vector::length(&received_vouches) + 1;

    //   // Check epoch limit
    //   let epoch_limit = remaining_epoch_vouches(addr);

    //   // Find the most restrictive limit
    //   let min_limit = base_limit;
    //   if (score_limit < min_limit) { min_limit = score_limit };
    //   if (received_limit < min_limit) { min_limit = received_limit };
    //   if (epoch_limit == 0) { return 0 }; // If no vouches left this epoch, return 0


    //   // Calculate remaining vouches
    //   if (given_count >= min_limit) {
    //     0
    //   } else {
    //     min_limit - given_count
    //   }
    // }

}
