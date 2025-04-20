module ol_framework::community_wallet_limits {
    use std::error;
    use std::vector;
    use diem_framework::system_addresses;
    use ol_framework::slow_wallet;
    use ol_framework::reauthorization;

    friend diem_framework::genesis;

    /// Not initialized by genesis
    const ENOT_INITIALIZED: u64 = 1;
    /// Caller is not authorized
    const ENOT_AUTHORIZED: u64 = 2;
    /// Advance exceeds the daily global unlocking rate
    const EADVANCE_EXCEEDS_LIMIT: u64 = 3;
    /// Grant exceeds the daily impact limit
    const EGRANT_EXCEEDS_DAILY_IMPACT: u64 = 4;
    /// Community wallet has exceeded its cumulative contribution limit
    const ECUMULATIVE_LIMIT_EXCEEDED: u64 = 5;
    /// Grant period is invalid
    const EINVALID_GRANT_PERIOD: u64 = 6;
    /// The total active community wallets would exceed the global limits
    const EACTIVE_CW_EXCEEDS_LIMIT: u64 = 7;

    /// Constants for calculations
    /// Maximum daily impact of a grant (5%)
    const MAX_DAILY_IMPACT: u64 = 5;
    /// Percentage divisor for calculations (100%)
    const PERCENTAGE_DIVISOR: u64 = 100;
    /// Standard grant vesting period in days (5 years)
    const GRANT_VESTING_DAYS: u64 = 365 * 5;
    /// Maximum cumulative contribution percentage (20%)
    const MAX_CUMULATIVE_CONTRIBUTION: u64 = 20;
    /// Community wallet address type identifier
    const COMMUNITY_WALLET_TYPE: u8 = 0;

    /// Structure to track global limits and all active community wallets
    struct CWLimitsTracker has key {
        // Track all active community wallets to calculate aggregate impact
        active_wallets: vector<address>,
        // Total cumulative contribution across all wallets
        total_cumulative_contribution: u64,
    }

    /// Structure to track individual community wallet transactions
    struct TransactionRecord has key {
        // Total amount of advances performed by this wallet
        advances_total: u64,
        // Total amount of grants performed by this wallet
        grants_total: u64,
        // Cumulative contribution to unlocking
        cumulative_contribution: u64,
    }

    /// Initialize the community wallet limits tracker
    public(friend) fun initialize(framework: &signer) {
        system_addresses::assert_ol(framework);

        if (!exists<CWLimitsTracker>(@ol_framework)) {
            move_to<CWLimitsTracker>(framework, CWLimitsTracker {
                active_wallets: vector::empty<address>(),
                total_cumulative_contribution: 0,
            });
        }
    }

    /// Register a community wallet to track active wallets
    public(friend) fun register_community_wallet(
        framework: &signer,
        community_wallet: address
    ) acquires CWLimitsTracker {
        system_addresses::assert_ol(framework);
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));

        let tracker = borrow_global_mut<CWLimitsTracker>(@ol_framework);
        if (!vector::contains(&tracker.active_wallets, &community_wallet)) {
            vector::push_back(&mut tracker.active_wallets, community_wallet);
        };

        // Initialize the transaction record for this wallet if it doesn't exist
        initialize_transaction_record(framework, community_wallet);
    }

    /// Initialize transaction record for a community wallet
    fun initialize_transaction_record(framework: &signer, wallet_addr: address) {
        system_addresses::assert_ol(framework);

        if (!exists<TransactionRecord>(wallet_addr)) {
            let record = TransactionRecord {
                advances_total: 0,
                grants_total: 0,
                cumulative_contribution: 0,
            };
            move_to(framework, record);
        }
    }

    /// Unregister a community wallet (when it's deauthorized)
    public(friend) fun unregister_community_wallet(
        framework: &signer,
        community_wallet: address
    ) acquires CWLimitsTracker {
        system_addresses::assert_ol(framework);
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));

        let tracker = borrow_global_mut<CWLimitsTracker>(@ol_framework);
        let (is_present, index) = vector::index_of(&tracker.active_wallets, &community_wallet);
        if (is_present) {
            vector::remove(&mut tracker.active_wallets, index);
        }
    }

    /// Check if an advance is within acceptable limits
    /// Returns true if the advance is allowed, false otherwise
    public fun check_advance_limit(community_wallet: address, amount: u64): bool acquires CWLimitsTracker, TransactionRecord {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));

        // Check cumulative contribution limit first
        if (!check_cumulative_limit(community_wallet, amount)) {
            return false
        };

        // Get the global daily unlocking rate
        let daily_unlocking = get_daily_unlocking_rate();

        // Advances should not exceed 100% of the daily global unlocking for a single advance
        if (amount > daily_unlocking) {
            return false
        };

        // Check if all active wallets were to do the same operation
        if (!check_aggregate_advance_limit(amount)) {
            return false
        };

        true
    }

    /// Check if a grant is within acceptable limits
    /// Returns true if the grant is allowed, false otherwise
    public fun check_grant_limit(
        community_wallet: address,
        amount: u64,
        vesting_days: u64
    ): bool acquires CWLimitsTracker, TransactionRecord {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        assert!(vesting_days > 0, error::invalid_argument(EINVALID_GRANT_PERIOD));

        // Check cumulative contribution limit first
        if (!check_cumulative_limit(community_wallet, amount)) {
            return false
        };

        // Get the global daily unlocking rate
        let daily_unlocking = get_daily_unlocking_rate();

        // Calculate daily impact of the grant
        let grant_daily_unlock = amount / vesting_days;

        // Calculate percentage impact (multiplied by 100 for precision)
        let percentage_impact = calculate_percentage_impact(grant_daily_unlock, daily_unlocking);

        // Check if the impact exceeds the 5% limit
        if (percentage_impact > MAX_DAILY_IMPACT * PERCENTAGE_DIVISOR) {
            return false
        };

        // Check if all active wallets were to do the same operation
        if (!check_aggregate_grant_limit(amount, vesting_days)) {
            return false
        };

        true
    }

    /// Check if the aggregate effect of all active wallets doing the same advance would exceed limits
    fun check_aggregate_advance_limit(amount: u64): bool acquires CWLimitsTracker {
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        let active_wallets_count = vector::length(&tracker.active_wallets);

        if (active_wallets_count == 0) return true;

        // Only count reauthorized wallets
        let reauthorized_count = 0;
        let i = 0;
        while (i < active_wallets_count) {
            let wallet = *vector::borrow(&tracker.active_wallets, i);
            if (reauthorization::is_v8_authorized(wallet)) {
                reauthorized_count = reauthorized_count + 1;
            };
            i = i + 1;
        };

        if (reauthorized_count == 0) return true;

        let daily_unlocking = get_daily_unlocking_rate();

        // If all active wallets did the same advance, would it exceed 100% of daily unlocking?
        amount * reauthorized_count <= daily_unlocking
    }

    /// Check if the aggregate effect of all active wallets doing the same grant would exceed limits
    fun check_aggregate_grant_limit(amount: u64, vesting_days: u64): bool acquires CWLimitsTracker {
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        let active_wallets_count = vector::length(&tracker.active_wallets);

        if (active_wallets_count == 0) return true;

        // Only count reauthorized wallets
        let reauthorized_count = 0;
        let i = 0;
        while (i < active_wallets_count) {
            let wallet = *vector::borrow(&tracker.active_wallets, i);
            if (reauthorization::is_v8_authorized(wallet)) {
                reauthorized_count = reauthorized_count + 1;
            };
            i = i + 1;
        };

        if (reauthorized_count == 0) return true;

        let daily_unlocking = get_daily_unlocking_rate();
        let grant_daily_unlock = amount / vesting_days;

        // Calculate aggregate impact if all wallets did the same grant
        let aggregate_impact = grant_daily_unlock * reauthorized_count;

        // Calculate percentage impact
        let percentage_impact = calculate_percentage_impact(aggregate_impact, daily_unlocking);

        // If all active wallets did the same grant, would it exceed 5% of daily unlocking?
        percentage_impact <= MAX_DAILY_IMPACT * PERCENTAGE_DIVISOR
    }

    /// Track a successful transaction for cumulative tracking
    public(friend) fun track_transaction(
        community_wallet: address,
        amount: u64,
        is_grant: bool
    ) acquires CWLimitsTracker, TransactionRecord {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        assert!(exists<TransactionRecord>(community_wallet), error::not_found(ENOT_INITIALIZED));

        // Update the wallet's transaction record
        let record = borrow_global_mut<TransactionRecord>(community_wallet);

        if (is_grant) {
            record.grants_total = record.grants_total + amount;
        } else {
            record.advances_total = record.advances_total + amount;
        };

        record.cumulative_contribution = record.cumulative_contribution + amount;

        // Update the global tracker
        let tracker = borrow_global_mut<CWLimitsTracker>(@ol_framework);
        tracker.total_cumulative_contribution = tracker.total_cumulative_contribution + amount;
    }

    /// Check if a transaction would exceed the cumulative contribution limit
    fun check_cumulative_limit(community_wallet: address, amount: u64): bool acquires CWLimitsTracker, TransactionRecord {
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        let daily_unlocking = get_daily_unlocking_rate();
        let max_allowed_contribution = daily_unlocking * GRANT_VESTING_DAYS * MAX_CUMULATIVE_CONTRIBUTION / PERCENTAGE_DIVISOR;

        // Check if global contributions would exceed limit
        if (tracker.total_cumulative_contribution + amount > max_allowed_contribution) {
            return false
        };

        // Also check if this wallet's individual contribution would be excessive
        if (exists<TransactionRecord>(community_wallet)) {
            let record = borrow_global<TransactionRecord>(community_wallet);
            // For now, there's no individual wallet limit, but we could add one if needed
            // (just including this check for future extensibility)
            let _ = record;
        };

        true
    }

    /// Calculate percentage impact of a daily unlock amount
    /// Returns the percentage multiplied by 100 for precision (500 = 5%)
    fun calculate_percentage_impact(grant_daily_unlock: u64, daily_unlocking: u64): u64 {
        if (daily_unlocking == 0) return 0;
        (grant_daily_unlock * PERCENTAGE_DIVISOR * PERCENTAGE_DIVISOR) / daily_unlocking
    }

    /// Get the current daily unlocking rate from slow wallet
    fun get_daily_unlocking_rate(): u64 {
        slow_wallet::get_daily_unlocking_rate()
    }

    #[view]
    /// Get the count of active and reauthorized community wallets
    public fun get_active_wallet_count(): (u64, u64) acquires CWLimitsTracker {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        let total_count = vector::length(&tracker.active_wallets);

        let reauthorized_count = 0;
        let i = 0;
        while (i < total_count) {
            let wallet = *vector::borrow(&tracker.active_wallets, i);
            if (reauthorization::is_v8_authorized(wallet)) {
                reauthorized_count = reauthorized_count + 1;
            };
            i = i + 1;
        };

        (total_count, reauthorized_count)
    }

    #[view]
    /// Get the cumulative contribution amount (global across all wallets)
    public fun get_cumulative_contribution(): u64 acquires CWLimitsTracker {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        tracker.total_cumulative_contribution
    }

    #[view]
    /// Get the cumulative contribution amount for a specific wallet
    public fun get_wallet_cumulative_contribution(wallet: address): u64 acquires TransactionRecord {
        if (!exists<TransactionRecord>(wallet)) {
            return 0
        };

        let record = borrow_global<TransactionRecord>(wallet);
        record.cumulative_contribution
    }

    #[view]
    /// Get the maximum allowed cumulative contribution
    public fun get_max_allowed_contribution(): u64 {
        let daily_unlocking = get_daily_unlocking_rate();
        daily_unlocking * GRANT_VESTING_DAYS * MAX_CUMULATIVE_CONTRIBUTION / PERCENTAGE_DIVISOR
    }

    #[view]
    /// Get the current utilization percentage of the cumulative limit
    /// Returns percentage multiplied by 100 for precision (1500 = 15%)
    public fun get_cumulative_utilization_percentage(): u64 acquires CWLimitsTracker {
        let current = get_cumulative_contribution();
        let max = get_max_allowed_contribution();

        if (max == 0) return 0;
        (current * PERCENTAGE_DIVISOR * PERCENTAGE_DIVISOR) / max
    }

    #[view]
    /// Calculate what would be the aggregate impact if all active wallets performed the same grant
    public fun calculate_aggregate_grant_impact(amount: u64, vesting_days: u64): u64 acquires CWLimitsTracker {
        let (_, reauthorized_count) = get_active_wallet_count();
        if (reauthorized_count == 0) return 0;

        let daily_unlocking = get_daily_unlocking_rate();
        let grant_daily_unlock = amount / vesting_days;

        let aggregate_impact = grant_daily_unlock * reauthorized_count;
        calculate_percentage_impact(aggregate_impact, daily_unlocking)
    }

    #[view]
    /// Calculate what would be the aggregate impact if all active wallets performed the same advance
    public fun calculate_aggregate_advance_percentage(amount: u64): u64 acquires CWLimitsTracker {
        let (_, reauthorized_count) = get_active_wallet_count();
        if (reauthorized_count == 0) return 0;

        let daily_unlocking = get_daily_unlocking_rate();
        let aggregate_amount = amount * reauthorized_count;

        calculate_percentage_impact(aggregate_amount, daily_unlocking)
    }

    #[view]
    /// Get wallet transaction totals (advances_total, grants_total, cumulative_contribution)
    public fun get_wallet_transaction_totals(wallet: address): (u64, u64, u64) acquires TransactionRecord {
        if (!exists<TransactionRecord>(wallet)) {
            return (0, 0, 0)
        };

        let record = borrow_global<TransactionRecord>(wallet);
        (record.advances_total, record.grants_total, record.cumulative_contribution)
    }

    #[view]
    /// Check if an advance would be allowed
    public fun is_advance_allowed(community_wallet: address, amount: u64): bool acquires CWLimitsTracker, TransactionRecord {
        check_advance_limit(community_wallet, amount)
    }

    #[view]
    /// Check if a grant would be allowed
    public fun is_grant_allowed(community_wallet: address, amount: u64, vesting_days: u64): bool acquires CWLimitsTracker, TransactionRecord {
        check_grant_limit(community_wallet, amount, vesting_days)
    }

    #[view]
    /// Convenience function to check with standard 5-year vesting
    public fun is_standard_grant_allowed(community_wallet: address, amount: u64): bool acquires CWLimitsTracker, TransactionRecord {
        check_grant_limit(community_wallet, amount, GRANT_VESTING_DAYS)
    }

    #[view]
    /// Get the list of active community wallets
    public fun get_active_wallets(): vector<address> acquires CWLimitsTracker {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        *&tracker.active_wallets
    }

    #[view]
    /// Get only the reauthorized community wallets
    public fun get_reauthorized_wallets(): vector<address> acquires CWLimitsTracker {
        assert!(exists<CWLimitsTracker>(@ol_framework), error::not_found(ENOT_INITIALIZED));
        let tracker = borrow_global<CWLimitsTracker>(@ol_framework);
        let all_wallets = *&tracker.active_wallets;
        let reauthorized = vector::empty<address>();

        let i = 0;
        let len = vector::length(&all_wallets);
        while (i < len) {
            let wallet = *vector::borrow(&all_wallets, i);
            if (reauthorization::is_v8_authorized(wallet)) {
                vector::push_back(&mut reauthorized, wallet);
            };
            i = i + 1;
        };

        reauthorized
    }
}
