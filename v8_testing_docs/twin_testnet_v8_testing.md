# Twin Testnet V8 Features Testing Guide

Thank you for participating in testing the new V8 features on our twin testnet. This document provides step-by-step instructions for using the Libra CLI to execute test transactions.

## Important Note: Using The correct Network
The instructions below will help configure a proper `~/.libra/libra-cli-config.yaml` to use for testing. It will setup to include the chain id 2 (in configs as `chain_name: TESTNET`).

### Be extra safe
If you are using a device that has had production keys and settings in the past, you should be explicit with the arguments in the CLI.

For belt-and-suspenders testing, you should also explicitly include the chain ID in your CLI arguments for testing.

**Always include `--chain-id=2` and `--url <TESTNET URL>` immediately after the `txs` command when using the twin testnet.**

This parameter specifies that you're interacting with the twin testnet (Chain ID 2) rather than the mainnet (Chain ID 1). The correct format is:

```bash
libra txs --chain-id=2 --url https://twin-testnet-rpc.libra.org [subcommand] [options]
```

Without this parameter in the correct position, your transactions will attempt to target the mainnet and might succeed, or worse, could be used for replay attacks.


## Prerequisites

- Libra CLI installed (version 8.0.0-rc.4 or higher)
- An account previously existing on mainnet

## Setup

1. Configure your CLI to connect to the twin testnet:

  ```bash
  # config for testnet and the mnemonic to set up addresses and authkeys

  libra config --chain-name=testnet \
  init \
  --fullnode-url=https://twin-testnet-rpc.libra.org

  # if you do not wish to enter a mnemonic on config you can enter the address and authkey directly.

  libra config --chain-name=testnet \
  init \
  --fullnode-url https://twin-testnet-rpc.libra.org \
  --force-address <ADDRESS> \
  --force-authkey <AUTHKEY>

  ```

2. Verify your connection:

```bash
# check the epoch
libra query epoch
# check block height
libra query block-height
```

## FILO Migration Features

### Feature 1: V7 Accounts as Slow Wallets

### Description
In V8, all V7 accounts have been converted to slow wallets. This means previously unlocked balances are now considered dormant until human reauthorization with Vouch is completed.

### Testing Steps

1. Check your account balance:

```bash
libra query balance <ACCOUNT>
# will display [<unlocked>, <total>]
```

2. Verify that:
   - Previously unlocked balances show as 0 unlocked
   - Your total balance shows the full amount (same as your previous balance)

3. Try to make a transfer (this should fail):

  ```bash
  libra txs --chain-name=testnet \
  transfer \
  --to-account=<RECIPIENT_ADDRESS> \
  --amount=10
  ```

4. Complete reauthorization through vouching:
   - Ask other testnet participants to vouch for you using:
   ```bash
   libra txs --chain-name=testnet \
   user vouch \
   --vouch-for=<SOME ADDRESS>
   ```

   - A user can check how many remaining vouches they have to give with:

  ```bash
   libra query view --function 0x1::vouch_limits::get_remaining_vouches --args <YOUR_ADDRESS>
   ```

   - After each vouch, check your vouch score increasing:

   ```bash
   libra query view --function 0x1::page_rank_lazy::get_cached_score --args <YOUR_ADDRESS>
   ```

   - Continue until you have enough vouches to unlock your balance

5. After sufficient number of vouches you should see a the `Founder` status and that the account is reauthorized:

  ```bash
  libra query view --function 0x1::founder::is_founder --args <YOUR_ADDRESS>
  ```

  ```bash
    libra query view --function 0x1::reauthorization::is_v8_reauthorized --args <YOUR_ADDRESS>
  ```

6. After every epoch boundary (15 minutes in testnet), you should see the unlocked balance increase

  ```bash
  libra query balance <YOUR_ADDRESS>
  ```

6. Assuming you have some unlocked balance, try the transfer again (should succeed now):

  ```bash
  libra txs --chain-id=2 transfer --to <RECIPIENT_ADDRESS> --amount 10
  ```

### Expected Outcome
- Initial balance check shows 0 unlocked tokens with full total balance
- First transfer attempt fails with an error about insufficient unlocked tokens
- Vouch score increases with each received vouch
- After receiving sufficient vouches, balance shows unlocked tokens
- Second transfer attempt completes successfully


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
libra txs --chain-id=2 community reauthorize --community-wallet <COMMUNITY_WALLET_ADDRESS>
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
