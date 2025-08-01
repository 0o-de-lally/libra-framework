// utils for calculating supply statistics
module ol_framework::supply {
  use std::vector;
  use ol_framework::libra_coin;
  use ol_framework::slow_wallet;
  use ol_framework::donor_voice_txs;
  use ol_framework::pledge_accounts;
  use ol_framework::donor_voice;
  use ol_framework::community_wallet_advance;
  use ol_framework::ol_account;
  use ol_framework::burn;

  #[view]

  /// Retrieves various supply statistics for Libra Coin.
  ///
  /// This function provides a consolidated view of different Libra Coin supply metrics,
  /// including the total supply, slow wallet locked amounts, donor voice allocations,
  /// pledged coins, and unlocked circulation.
  ///
  /// # Returns
  ///
  /// A tuple containing five values:
  /// * `total`: The total supply of Libra Coin in existence
  /// * `slow_locked`: Amount of coins locked in slow wallets
  /// * `donor_voice`: Coins allocated to community endowments via donor voice
  /// * `pledge`: Coins committed to future pledges
  /// * `unlocked`: Total coins that have been unlocked from slow wallets and are in circulation
  ///
  /// Note: Since v8, the system assumes all coins are initially locked, and this
  /// function calculates the unlocked supply based on transfers out of slow wallets
  /// and community wallets.

  public fun get_stats(): (u64, u64, u64, u64, u64) {
    let total = libra_coin::supply();
    let community_endowments = donor_voice_txs::get_dv_supply();
    let future_pledges = pledge_accounts::get_pledge_supply();


    let all_unlocked = get_all_unlocked();
    // v7 accounts which have not migrated to slow wallets,
    // will not be counted in the slow_locked or unlocked
    let assumed_locked = total - community_endowments - future_pledges - all_unlocked;

    (total, assumed_locked, community_endowments, future_pledges, all_unlocked)
  }

  #[view]
  /// Get the maximum possible supply of Libra Coin
  ///
  /// This function returns the final supply number that was set at genesis,
  /// representing the maximum amount of Libra Coin that can ever exist in the system.
  /// This is different from the current total supply, which may be less due to
  /// burns or if minting hasn't reached the final supply yet.
  ///
  /// @returns
  /// * The maximum possible supply of Libra Coin as set during genesis
  public fun get_max_supply(): u64 {
    libra_coin::get_final_supply()
  }

  #[view]
  /// Get the lifetime burn statistics for Libra Coin
  ///
  /// This function returns comprehensive burn statistics that track the total amount
  /// of Libra Coin that has been permanently removed from circulation through burning
  /// and the amount that has been recycled back into the system.
  ///
  /// # Returns
  /// A tuple containing two values:
  /// * `lifetime_burned`: Total amount of Libra Coin permanently burned/destroyed
  /// * `lifetime_recycled`: Total amount of Libra Coin recycled back into circulation
  ///
  /// # Burn vs Recycle
  /// - **Burned**: Coins permanently removed from total supply (deflationary)
  /// - **Recycled**: Coins temporarily removed but redistributed back to the system
  ///
  /// # Usage
  /// This is essential for understanding the deflationary mechanics of Libra Coin:
  /// - Calculate effective total supply: `total_supply - lifetime_burned`
  /// - Track deflationary pressure over time
  /// - Analyze burn/recycle ratios for tokenomics
  ///
  /// # Example
  /// ```
  /// let (burned, recycled) = supply::get_lifetime_burn();
  /// let total_supply = supply::get_max_supply();
  /// let effective_supply = total_supply - burned; // Actual circulating potential
  /// let burn_rate = (burned * 100) / total_supply; // Percentage of max supply burned
  /// ```
  public fun get_lifetime_burn(): (u64, u64) {
    burn::get_lifetime_tracker()
  }

  #[view]
  /// Get the current total supply of Libra Coin
  ///
  /// This function provides the current total supply of Libra Coin that actually
  /// exists in the system. In OpenLibra, this will typically be lower than the
  /// maximum supply (`get_max_supply()`) due to the burn mechanism that permanently
  /// removes coins from circulation.
  ///
  /// # Returns
  /// * The total amount of Libra Coin currently in existence (after accounting for burns)
  ///
  /// # OpenLibra Supply Reduction Model
  /// Unlike many cryptocurrencies, OpenLibra has a supply reduction model:
  /// - Coins are permanently burned and removed from the total supply
  /// - Total supply decreases over time as burns occur
  /// - This makes the remaining coins potentially more scarce
  ///
  /// # Usage
  /// This is the most straightforward supply metric and is useful for:
  /// - Calculating actual scarcity (vs theoretical maximum)
  /// - Market cap calculations with real circulating amount
  /// - Understanding the impact of burn mechanisms
  /// - Tracking supply reduction over time
  ///
  /// # Relationship to Other Functions
  /// - This is the actual current supply (post-burns)
  /// - `get_max_supply()` is the theoretical maximum (pre-burns)
  /// - `get_lifetime_burn()` shows how much has been permanently removed
  /// - `get_stats()` provides detailed breakdowns of current supply
  /// - `get_circulating()` shows immediately available portion
  ///
  /// # Example
  /// ```
  /// let total = supply::get_total_supply();
  /// let max = supply::get_max_supply();
  /// let (burned, _) = supply::get_lifetime_burn();
  ///
  /// // Total should equal max minus burned (approximately, due to other factors)
  /// assert!(total <= max, "Total supply cannot exceed maximum");
  ///
  /// // Calculate burn rate
  /// let burn_rate = (burned * 100) / max; // Percentage of max supply burned
  /// ```
  public fun get_total_supply(): u64 {
    libra_coin::supply()
  }

  #[view]
  // Unlocks come from two sources:
  // 1. Slow wallets, which have been unlocked by the slow wallet system
  // 2. Community wallets, which can borrow advances from their balance
  public fun get_all_unlocked(): u64 {
    // Note, since v8 we assume everything is locked.
    // So we calculated what has be transferred out of
    // slow wallets, and from community wallets
    let slow_unlocked = slow_wallet::get_lifetime_unlocked_supply();
    let cw_unlocked = get_cw_advanced();
    slow_unlocked + cw_unlocked
  }

  #[view]
  /// Calculate the total amount of coins advanced (unlocked) by all community wallets
  ///
  /// Community wallets can extend credit to users by unlocking coins as advances/loans.
  /// This function aggregates the lifetime withdrawals from all registered community
  /// wallets to determine how much of the total supply has been unlocked through
  /// this advance mechanism.
  ///
  /// # Returns
  /// * The total amount of coins that have been withdrawn as advances from all
  ///   community wallets across the entire system
  /// * This amount contributes to the calculation of unlocked/circulating supply
  ///
  /// # Implementation Details
  /// - Retrieves the list of all donor voice (community wallet) accounts
  /// - Iterates through each account and sums their lifetime withdrawals
  /// - Handles accounts that may not have the advance feature initialized
  ///
  /// # Usage
  /// This function is used internally by `get_all_unlocked()` to calculate the
  /// total unlocked supply, which includes both slow wallet unlocks and community
  /// wallet advances.
  public fun get_cw_advanced(): u64 {
    // Get the list of all donor voice (community wallet) accounts
    let dv_accounts = donor_voice::get_root_registry();
    let total_advanced = 0;

    // Iterate through each account and sum their lifetime withdrawals
    let i = 0;
    let len = vector::length(&dv_accounts);
    while (i < len) {
      let account = vector::borrow(&dv_accounts, i);
      let lifetime_withdrawals = community_wallet_advance::get_lifetime_withdrawals(*account);
      total_advanced = total_advanced + lifetime_withdrawals;
      i = i + 1;
    };

    total_advanced
  }

  #[view]
  /// Calculate the total remaining credit available across all community wallets
  ///
  /// Community wallets have credit limits based on their balance and usage. This function
  /// aggregates the remaining available credit from all registered community wallets,
  /// representing coins that could potentially be unlocked as advances but haven't been
  /// withdrawn yet.
  ///
  /// For accounts that haven't initialized the advance feature, this function calculates
  /// the maximum potential credit they could extend based on their current balance and
  /// the system's credit line percentage (BPS_BALANCE_CREDIT_LINE).
  ///
  /// # Returns
  /// * The total amount of credit still available for withdrawal across all community
  ///   wallets in the system
  /// * This amount represents potential liquidity that could be unlocked on demand
  ///
  /// # Implementation Details
  /// - Retrieves the list of all donor voice (community wallet) accounts
  /// - For initialized accounts: uses actual available credit based on balance and usage
  /// - For uninitialized accounts: calculates maximum potential credit as percentage of balance
  /// - Credit limits are determined by BPS_BALANCE_CREDIT_LINE (0.50% of balance)
  ///
  /// # Usage
  /// This function is used by `get_circulating()` to calculate the total circulating
  /// supply, which includes both unlocked coins and immediately available credit.
  public fun get_cw_remaining_credit(): u64 {
    // Get the list of all donor voice (community wallet) accounts
    let dv_accounts = donor_voice::get_root_registry();
    let total_available_credit = 0;

    // Get the credit line basis points for calculating potential credit
    let credit_line_bps = community_wallet_advance::get_credit_line_bps();

    // Iterate through each account and sum their available credit
    let i = 0;
    let len = vector::length(&dv_accounts);
    while (i < len) {
      let account = vector::borrow(&dv_accounts, i);

      let available_credit = if (community_wallet_advance::is_advance_initialized(*account)) {
        // For initialized accounts, use actual available credit
        community_wallet_advance::total_credit_available(*account)
      } else {
        // For uninitialized accounts, calculate maximum potential credit
        // based on their balance and the credit line percentage
        let (_, balance) = ol_account::balance(*account);
        (balance * credit_line_bps) / 10000
      };

      total_available_credit = total_available_credit + available_credit;
      i = i + 1;
    };

    total_available_credit
  }


  #[view]
  /// Calculate the total circulating supply of Libra Coin
  ///
  /// The circulating supply represents all coins that are immediately transferable or
  /// available for use without restrictions. In the OL ecosystem, this includes both
  /// coins that have been physically unlocked and credit that can be extended
  /// immediately from community wallets.
  ///
  /// # Components of Circulating Supply
  ///
  /// The circulating supply consists of:
  /// 1. **Unlocked coins from slow wallets**: Coins that users have unlocked over time
  ///    through the slow wallet mechanism
  /// 2. **Advanced coins from community wallets**: Coins that have been withdrawn as
  ///    advances/loans from community wallets to ordinary accounts
  /// 3. **Available credit from community wallets**: Remaining credit that community
  ///    wallets can extend immediately, representing potential immediate liquidity
  ///
  /// # Returns
  /// * The total amount of Libra Coin that is immediately transferable or available
  ///   for immediate use in the ecosystem
  /// * This represents the "liquid" portion of the total supply from a market perspective
  ///
  /// # Implementation Details
  /// - Uses `get_all_unlocked()` to get coins unlocked from slow wallets and CW advances
  /// - Uses `get_cw_remaining_credit()` to get immediately available credit
  /// - Sums both components to represent total immediate liquidity
  ///
  /// # Market Perspective
  /// This metric is what traditional markets would consider "circulating supply" -
  /// tokens that are freely tradeable and not locked or restricted. It provides
  /// a more accurate picture of actual market liquidity than just counting unlocked coins.
  ///
  /// # Example
  /// If there are:
  /// - 1M coins unlocked from slow wallets
  /// - 500K coins advanced from community wallets
  /// - 250K available credit from community wallets
  /// Then circulating supply = 1M + 500K + 250K = 1.75M coins
  public fun get_circulating(): u64 {
    // Get all coins that have been physically unlocked and transferred
    let unlocked = get_all_unlocked();

    // Get available credit that can be extended immediately
    let available_credit = get_cw_remaining_credit();

    // Total immediately available liquidity
    unlocked + available_credit
  }
}
