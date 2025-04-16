# Twin Testnet V8 Features Testing Guide

Thank you for participating in testing the new V8 features on our twin testnet. This document provides step-by-step instructions for using the Libra CLI to execute test transactions.

## Prerequisites

- Libra CLI installed (version 7.0.5 or higher)
- An account on the twin testnet with test tokens
- Basic familiarity with blockchain transactions

## Setup

1. Configure your CLI to connect to the twin testnet:

```bash
libra config set --url https://twin-testnet-rpc.libra.org
```

2. Verify your connection:

```bash
libra info
```

## FILO Migration Features

### Feature 1: V7 Accounts as Slow Wallets

### Description
In V8, all V7 accounts have been converted to slow wallets. This means previously unlocked balances are now considered locked until reauthorization with Vouch is completed.

### Testing Steps

1. Check your account balance:

```bash
libra query balance
```

2. Verify that:
   - Previously unlocked balances show as 0 unlocked
   - Your total balance shows the full amount (same as your previous balance)

3. Try to make a transfer (this should fail):

```bash
libra transfer --to <RECIPIENT_ADDRESS> --amount 10
```

4. Complete reauthorization through vouching:
   - Ask other testnet participants to vouch for you using:
   ```bash
   libra txs user vouch --vouch-for <YOUR_ADDRESS>
   ```

   - After each vouch, check your vouch score increasing:
   ```bash
   libra query view --function 0x1::vouch::get_vouch_score --args <YOUR_ADDRESS>
   ```

   - Continue until you have enough vouches to unlock your balance

5. Verify unlocked balance after receiving sufficient vouches:

```bash
libra query balance
```

6. Try the transfer again (should succeed now):

```bash
libra transfer --to <RECIPIENT_ADDRESS> --amount 10
```

### Expected Outcome
- Initial balance check shows 0 unlocked tokens with full total balance
- First transfer attempt fails with an error about insufficient unlocked tokens
- Vouch score increases with each received vouch
- After receiving sufficient vouches, balance shows unlocked tokens
- Second transfer attempt completes successfully

### Feature 2: Verify Founder Status

### Description
The Founder status is granted to accounts that have received a sufficient number of vouches. This status is tracked in the founder module and provides special privileges within the network.

### Testing Steps

1. First, complete the vouching process as described in Feature 1

2. Once you have received enough vouches, check your Founder status:

```bash
libra query view --function 0x1::founder::is_founder --args <YOUR_ADDRESS>
```

3. Verify additional Founder details:

```bash
libra query view --function 0x1::founder::get_founder_info --args <YOUR_ADDRESS>
```

### Expected Outcome
- After receiving sufficient vouches, the `is_founder` function should return `true`
- The `get_founder_info` function should return details about your Founder status, including when it was granted

### Feature 3: Epoch-Based Token Unlocks

### Description
Users with Founder status receive gradual token unlocks with each new epoch. The twin testnet has accelerated epochs of approximately 15 minutes (compared to 24 hours on mainnet) to allow for quicker testing of this feature.

### Testing Steps

1. First, complete the vouching process and verify Founder status as described in Features 1 and 2

2. Check your initial unlocked balance:

```bash
libra query balance
```

3. Wait for approximately 15 minutes (one epoch)

4. Check your balance again to observe the increase in unlocked tokens:

```bash
libra query balance
```

5. Repeat steps 3-4 several times to confirm that unlocks occur consistently with each epoch

### Expected Outcome
- After each epoch (approximately 15 minutes), your unlocked balance should increase
- The increase should follow a predictable pattern based on your total balance and Founder status

## Community Wallet Reauthorization Votes

### Feature 4: Submit Vote for Community Wallet Reauthorization

### Description
This feature allows community members to vote on reauthorizing community wallet spending. It's part of the governance improvements in V8.

### Testing Steps

1. Check the list of pending community wallet reauthorization proposals:

```bash
libra query view --function 0x1::community_wallet::get_pending_proposals
```

2. Submit your vote for a community wallet reauthorization:

```bash
libra txs community reauthorize --community-wallet <COMMUNITY_WALLET_ADDRESS>
```

3. Verify your vote was recorded:

```bash
libra query view --function 0x1::community_wallet::get_vote --args <YOUR_ADDRESS> <COMMUNITY_WALLET_ADDRESS>
```

4. Check the total votes on the reauthorization:

```bash
libra query view --function 0x1::community_wallet::get_proposal_votes --args <COMMUNITY_WALLET_ADDRESS>
```

### Expected Outcome
- Your vote is recorded successfully
- The proposal's vote count increases accordingly
- Once enough votes are collected, the proposal state should change to either approved or rejected

## Rotate Root of Trust

### Feature 5: Monitor Root of Trust Rotation

### Description
In V8, the root of trust can be rotated through a community-based process. This feature allows you to monitor the rotation process and verify the new root of trust.

### Testing Steps

1. Check the current root of trust:

```bash
libra query view --function 0x1::root_of_trust::get_current_root
```

2. Check if there's an ongoing rotation process:

```bash
libra query view --function 0x1::root_of_trust::get_rotation_status
```

3. If a rotation is in progress, view the details:

```bash
libra query view --function 0x1::root_of_trust::get_rotation_info
```

4. After rotation completes, verify the new root of trust:

```bash
libra query view --function 0x1::root_of_trust::get_current_root
```

5. Verify the rotation history:

```bash
libra query view --function 0x1::root_of_trust::get_rotation_history
```

### Expected Outcome
- You can successfully view the current root of trust
- If a rotation is in progress, details are displayed correctly
- After rotation, the new root is reflected in the system
- The rotation history shows a record of all previous root changes

## Reporting Issues

If you encounter any issues during testing, please report them with the following information:

1. Feature being tested
2. Exact command that failed
3. Error message or unexpected behavior
4. Any additional context that might be helpful

Please submit issues to our [GitHub repository](https://github.com/libra-framework/issues) or contact the development team at testnet-support@libra.org.

## Feedback

Your feedback is valuable! After completing the tests, please fill out our feedback form at [https://forms.libra.org/twin-testnet-feedback](https://forms.libra.org/twin-testnet-feedback).

Thank you for helping improve Libra!
