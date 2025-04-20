# Community Wallet Limits Specification

## Overview
This module implements limits on transactions made by community wallets to ensure they do not disproportionately affect the unlocking rate of the Libra supply.

## Transaction Types
1. **Advances**: Immediate disbursements of unlocked funds
2. **Grants**: Payments to slow wallets, which vest at the daily rate (35K per day)

## Constraints

### Advances
- Each advance must never exceed 100% of the global daily unlocking rate.
- Formula: `advance_amount <= daily_global_unlocking`

### Grants
- The daily unlocking rate of a new grant should not change the daily drip by more than 5%.
- Formula: `(daily_global_unlocking + grant_daily_unlock) / daily_global_unlocking <= 1.05`
- Where `grant_daily_unlock = grant_amount / (5 * 365)` (assuming 5-year vesting)

### Cumulative Impact
- Track how much unlocking the Community Wallet has contributed over time.
- If they have added 20% more unlocks cumulatively over 5 years, they should be prevented from additional transactions.
- Formula: `cumulative_cw_contribution / (5 * 365 * daily_global_unlocking) <= 0.20`

### Aggregate Impact
- There are M potential community wallets, but only N will be active and reauthorized at any time.
- System must consider the upper limit scenario where all N reauthorized accounts perform the same operation simultaneously.
- For advances: `N * advance_amount <= daily_global_unlocking`
- For grants: `(daily_global_unlocking + N * grant_daily_unlock) / daily_global_unlocking <= 1.05`

## Module Functions

### Primary Functions
1. `check_advance_limit`: Verifies if an advance is within acceptable limits
2. `check_grant_limit`: Verifies if a grant is within acceptable limits
3. `track_transaction`: Records a successful transaction for cumulative tracking
4. `get_cumulative_contribution`: Returns the total amount the CW has contributed to unlocking

### Community Wallet Management
1. `register_community_wallet`: Adds a wallet to the tracking system
2. `unregister_community_wallet`: Removes a wallet from the tracking system
3. `get_active_wallet_count`: Returns the count of both total and reauthorized wallets
4. `get_active_wallets`: Gets all registered community wallets
5. `get_reauthorized_wallets`: Gets only active and reauthorized community wallets

### Aggregate Impact Functions
1. `check_aggregate_advance_limit`: Checks if all reauthorized wallets doing the same advance would exceed limits
2. `check_aggregate_grant_limit`: Checks if all reauthorized wallets doing the same grant would exceed limits
3. `calculate_aggregate_grant_impact`: Calculates the percentage impact if all wallets performed the same grant
4. `calculate_aggregate_advance_percentage`: Calculates the percentage impact if all wallets performed the same advance

### Helper Functions
1. `initialize`: Sets up the tracking state
2. `get_daily_unlocking_rate`: Gets the current daily unlocking rate from slow wallet
3. `calculate_grant_daily_impact`: Calculates the daily impact of a grant

## Data Structures
1. `CWLimitsTracker`: Keeps track of cumulative contributions and active wallets
2. `TransactionRecord`: Records individual transactions

## Events
1. `LimitExceededEvent`: Emitted when a transaction is rejected due to limits (types: individual, daily impact, cumulative, aggregate)
2. `TransactionTrackedEvent`: Emitted when a transaction is successfully tracked
