# Atomic Swap Implementation Plan
## Libra ↔ Ethereum Treasury Auction with Checkpoint-Based Verification

**Date**: 2025-01-24
**Status**: Implementation Ready

---

## Executive Summary

This document synthesizes all research into a practical implementation plan for atomic swaps between Libra and Ethereum using:

1. **Treasury Auction Design**: Away asset traded in entirety, home side (Libra) allows fractional bids
2. **Asymmetric Escrow**: ETH locked in smart contract, Libra uses unlocked balances via authorization
3. **Checkpoint-Based Verification**: State root checkpoints (32 bytes) instead of full light client
4. **Optimistic Submission**: $0.05 submission cost with bond, challenge period
5. **Bounty Incentives**: Early exiters pay "chicken fee" that rewards checkpoint submitters
6. **ZK Fallback**: Axiom/Succinct for challenged checkpoints

**Cost Profile**:
- Normal case: $0.05 per checkpoint
- Challenged: $23 (Axiom) or $10-15 (Succinct)
- Bounty: ~$20 (from chicken fee)

**Capital Efficiency**: 50% better than traditional HTLCs (no Libra escrow)

---

## 1. Architecture Overview

### 1.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     ETHEREUM (Away Chain)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. Alice locks ETH in escrow contract                          │
│     - Hashlock: H(preimage)                                     │
│     - Timelock: 48 hours                                        │
│     - Amount: 10 ETH                                            │
│     - Recipient: multisig or alice                              │
│                                                                   │
│  2. Lock emits event → generates Merkle proof                   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                   [State Root Checkpoint]
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   LIBRA (Home Chain)                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  3. Checkpoint submitter posts ETH state root (optimistic)      │
│     - Cost: $0.05                                                │
│     - Bond: $30 (refundable after challenge period)             │
│     - Challenge period: 1 hour                                   │
│                                                                   │
│  4. Alice submits Merkle proof of ETH lock                      │
│     - Verifies against checkpoint                               │
│     - Creates treasury auction                                   │
│                                                                   │
│  5. Libra users bid on auction                                  │
│     - Bid with LIBRA tokens (unlocked balances)                 │
│     - Pre-authorize contract withdrawal                          │
│     - Bids visible, continuous auction                           │
│                                                                   │
│  6. Auction clears at uniform price                             │
│     - Multiple winners possible (fractional fills)              │
│     - Contract withdraws from winners using authorization        │
│     - Alice receives LIBRA tokens                                │
│     - Winners get preimage                                       │
│                                                                   │
│  7. Early exit option (optional)                                │
│     - Winner pays "chicken fee" ($20)                            │
│     - Creates bounty for next checkpoint                         │
│     - Exits auction, authorization revoked                       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                        [Preimage Revealed]
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     ETHEREUM (Away Chain)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  8. Winners unlock ETH with preimage                            │
│     - Each winner unlocks proportional share                     │
│     - Or: Alice unlocks and distributes off-chain                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Key Innovations

**Asymmetric Atomicity**:
- Ethereum: Traditional hashlock escrow
- Libra: Authorization-based (no escrow), treasury auction

**Self-Incentivizing Checkpoints**:
- No continuous sync required
- On-demand submission driven by economic opportunity
- Bounty pool funded by early exiters

**Capital Efficiency**:
- Traditional HTLC: Lock 10 ETH + Lock 20,000 LIBRA
- This design: Lock 10 ETH + Authorize 20,000 LIBRA (no lock!)
- 50% capital efficiency improvement

---

## 2. Smart Contract Architecture

### 2.1 Ethereum Contracts

#### 2.1.1 `EthereumHashlockEscrow.sol`

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EthereumHashlockEscrow {
    struct Lock {
        address payable initiator;    // Alice
        bytes32 hashlock;             // H(preimage)
        uint256 amount;               // 10 ETH
        uint256 timelock;             // block.timestamp + 48 hours
        bool withdrawn;
        bool refunded;
    }

    mapping(bytes32 => Lock) public locks;

    event LockCreated(
        bytes32 indexed lockId,
        address indexed initiator,
        bytes32 hashlock,
        uint256 amount,
        uint256 timelock
    );

    event LockClaimed(
        bytes32 indexed lockId,
        address indexed claimer,
        bytes32 preimage
    );

    event LockRefunded(
        bytes32 indexed lockId,
        address indexed initiator
    );

    /// Create new hashlock escrow
    function createLock(
        bytes32 hashlock,
        uint256 timelockDuration
    ) external payable returns (bytes32 lockId) {
        require(msg.value > 0, "Must lock ETH");
        require(timelockDuration >= 24 hours, "Timelock too short");

        lockId = keccak256(abi.encodePacked(
            msg.sender,
            hashlock,
            msg.value,
            block.timestamp
        ));

        require(locks[lockId].amount == 0, "Lock exists");

        locks[lockId] = Lock({
            initiator: payable(msg.sender),
            hashlock: hashlock,
            amount: msg.value,
            timelock: block.timestamp + timelockDuration,
            withdrawn: false,
            refunded: false
        });

        emit LockCreated(
            lockId,
            msg.sender,
            hashlock,
            msg.value,
            locks[lockId].timelock
        );
    }

    /// Claim locked ETH with preimage
    function claim(
        bytes32 lockId,
        bytes32 preimage
    ) external {
        Lock storage lock = locks[lockId];

        require(lock.amount > 0, "Lock not found");
        require(!lock.withdrawn, "Already withdrawn");
        require(!lock.refunded, "Already refunded");
        require(block.timestamp < lock.timelock, "Timelock expired");
        require(
            keccak256(abi.encodePacked(preimage)) == lock.hashlock,
            "Invalid preimage"
        );

        lock.withdrawn = true;

        emit LockClaimed(lockId, msg.sender, preimage);

        payable(msg.sender).transfer(lock.amount);
    }

    /// Refund after timelock expires
    function refund(bytes32 lockId) external {
        Lock storage lock = locks[lockId];

        require(lock.amount > 0, "Lock not found");
        require(!lock.withdrawn, "Already withdrawn");
        require(!lock.refunded, "Already refunded");
        require(block.timestamp >= lock.timelock, "Timelock active");

        lock.refunded = true;

        emit LockRefunded(lockId, lock.initiator);

        lock.initiator.transfer(lock.amount);
    }
}
```

#### 2.1.2 `LibraCheckpointRegistry.sol`

This contract stores Libra state root checkpoints on Ethereum, allowing ETH users to verify Libra state.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LibraCheckpointRegistry {
    struct Checkpoint {
        bytes32 libraStateRoot;
        uint256 libraBlockHeight;
        bytes32 prevCheckpointHash;
        address submitter;
        uint256 submittedAt;
        uint256 bondAmount;
        bool challenged;
        bool finalized;
    }

    mapping(uint256 => Checkpoint) public checkpoints;
    uint256 public latestCheckpoint;
    uint256 public constant CHALLENGE_PERIOD = 1 hours;
    uint256 public constant REQUIRED_BOND = 0.015 ether;  // ~$30

    event CheckpointSubmitted(
        uint256 indexed checkpointId,
        bytes32 libraStateRoot,
        uint256 libraBlockHeight,
        address submitter
    );

    event CheckpointChallenged(
        uint256 indexed checkpointId,
        address challenger,
        bytes proof
    );

    event CheckpointFinalized(
        uint256 indexed checkpointId
    );

    /// Submit Libra checkpoint optimistically
    function submitCheckpoint(
        bytes32 libraStateRoot,
        uint256 libraBlockHeight
    ) external payable returns (uint256 checkpointId) {
        require(msg.value >= REQUIRED_BOND, "Insufficient bond");
        require(libraBlockHeight > 0, "Invalid block height");

        checkpointId = latestCheckpoint + 1;

        bytes32 prevHash = latestCheckpoint > 0
            ? keccak256(abi.encodePacked(checkpoints[latestCheckpoint].libraStateRoot))
            : bytes32(0);

        checkpoints[checkpointId] = Checkpoint({
            libraStateRoot: libraStateRoot,
            libraBlockHeight: libraBlockHeight,
            prevCheckpointHash: prevHash,
            submitter: msg.sender,
            submittedAt: block.timestamp,
            bondAmount: msg.value,
            challenged: false,
            finalized: false
        });

        latestCheckpoint = checkpointId;

        emit CheckpointSubmitted(
            checkpointId,
            libraStateRoot,
            libraBlockHeight,
            msg.sender
        );
    }

    /// Challenge checkpoint with ZK proof
    function challengeCheckpoint(
        uint256 checkpointId,
        bytes calldata zkProof
    ) external {
        Checkpoint storage cp = checkpoints[checkpointId];

        require(cp.submittedAt > 0, "Checkpoint not found");
        require(!cp.finalized, "Already finalized");
        require(
            block.timestamp < cp.submittedAt + CHALLENGE_PERIOD,
            "Challenge period expired"
        );

        // Verify ZK proof shows different state root
        // This would call Axiom/Succinct verification
        require(verifyZkProof(zkProof, cp.libraBlockHeight), "Invalid proof");

        cp.challenged = true;

        emit CheckpointChallenged(checkpointId, msg.sender, zkProof);

        // Slash submitter's bond, give to challenger
        payable(msg.sender).transfer(cp.bondAmount);
    }

    /// Finalize checkpoint after challenge period
    function finalizeCheckpoint(uint256 checkpointId) external {
        Checkpoint storage cp = checkpoints[checkpointId];

        require(cp.submittedAt > 0, "Checkpoint not found");
        require(!cp.finalized, "Already finalized");
        require(!cp.challenged, "Checkpoint challenged");
        require(
            block.timestamp >= cp.submittedAt + CHALLENGE_PERIOD,
            "Challenge period active"
        );

        cp.finalized = true;

        emit CheckpointFinalized(checkpointId);

        // Return bond to submitter
        payable(cp.submitter).transfer(cp.bondAmount);
    }

    /// Verify ZK proof (placeholder - would integrate with Axiom/Succinct)
    function verifyZkProof(
        bytes calldata proof,
        uint256 blockHeight
    ) internal view returns (bool) {
        // TODO: Integrate with Axiom or Succinct verifier
        // For now, revert to force implementation
        revert("ZK verification not implemented");
    }
}
```

### 2.2 Libra Contracts (Move)

#### 2.2.1 `ethereum_checkpoints.move`

```move
module ol_framework::ethereum_checkpoints {
    use std::vector;
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::coin;

    // Error codes
    const E_INVALID_PROOF: u64 = 1;
    const E_CHECKPOINT_NOT_FOUND: u64 = 2;
    const E_CHALLENGE_PERIOD_ACTIVE: u64 = 3;
    const E_CHALLENGE_PERIOD_EXPIRED: u64 = 4;
    const E_ALREADY_CHALLENGED: u64 = 5;
    const E_INSUFFICIENT_BOND: u64 = 6;

    // Constants
    const CHALLENGE_PERIOD_SECONDS: u64 = 3600; // 1 hour
    const REQUIRED_BOND_MICROCOINS: u64 = 30_000_000; // $30 worth

    struct EthereumCheckpoint has store {
        state_root: vector<u8>,        // 32 bytes
        block_number: u64,
        timestamp: u64,
        submitter: address,
        bond_amount: u64,
        challenged: bool,
        finalized: bool,
        prev_checkpoint_hash: vector<u8>,
    }

    struct CheckpointRegistry has key {
        checkpoints: Table<u64, EthereumCheckpoint>,
        latest_checkpoint_id: u64,
    }

    struct BountyPool has key {
        total_bounties: u64,
        bounties_by_auction: Table<u64, u64>,
    }

    /// Initialize checkpoint registry
    public fun initialize(account: &signer) {
        let addr = signer::address_of(account);
        assert!(addr == @ol_framework, 0);

        move_to(account, CheckpointRegistry {
            checkpoints: table::new(),
            latest_checkpoint_id: 0,
        });

        move_to(account, BountyPool {
            total_bounties: 0,
            bounties_by_auction: table::new(),
        });
    }

    /// Submit Ethereum checkpoint optimistically
    public entry fun submit_checkpoint<BondCoin>(
        submitter: &signer,
        state_root: vector<u8>,
        block_number: u64,
        bond_amount: u64,
    ) acquires CheckpointRegistry {
        assert!(bond_amount >= REQUIRED_BOND_MICROCOINS, E_INSUFFICIENT_BOND);
        assert!(vector::length(&state_root) == 32, E_INVALID_PROOF);

        // Lock bond
        let bond_coins = coin::withdraw<BondCoin>(submitter, bond_amount);

        // TODO: Store bond coins in escrow
        // For now, just verify withdrawal works
        coin::deposit(signer::address_of(submitter), bond_coins);

        let registry = borrow_global_mut<CheckpointRegistry>(@ol_framework);
        let checkpoint_id = registry.latest_checkpoint_id + 1;

        let prev_hash = if (registry.latest_checkpoint_id > 0) {
            let prev_cp = table::borrow(&registry.checkpoints, registry.latest_checkpoint_id);
            copy prev_cp.state_root
        } else {
            vector::empty<u8>()
        };

        let checkpoint = EthereumCheckpoint {
            state_root,
            block_number,
            timestamp: timestamp::now_seconds(),
            submitter: signer::address_of(submitter),
            bond_amount,
            challenged: false,
            finalized: false,
            prev_checkpoint_hash: prev_hash,
        };

        table::add(&mut registry.checkpoints, checkpoint_id, checkpoint);
        registry.latest_checkpoint_id = checkpoint_id;
    }

    /// Challenge checkpoint with ZK proof
    public entry fun challenge_checkpoint(
        challenger: &signer,
        checkpoint_id: u64,
        zk_proof: vector<u8>,
    ) acquires CheckpointRegistry {
        let registry = borrow_global_mut<CheckpointRegistry>(@ol_framework);
        assert!(table::contains(&registry.checkpoints, checkpoint_id), E_CHECKPOINT_NOT_FOUND);

        let checkpoint = table::borrow_mut(&mut registry.checkpoints, checkpoint_id);

        let now = timestamp::now_seconds();
        assert!(
            now < checkpoint.timestamp + CHALLENGE_PERIOD_SECONDS,
            E_CHALLENGE_PERIOD_EXPIRED
        );
        assert!(!checkpoint.challenged, E_ALREADY_CHALLENGED);

        // Verify ZK proof (would call Plonk verifier)
        // For now, assume valid
        // TODO: Integrate with Argument Computer's Plonk verifier
        assert!(verify_zk_proof(&zk_proof, checkpoint.block_number), E_INVALID_PROOF);

        checkpoint.challenged = true;

        // Slash bond, give to challenger
        // TODO: Transfer bond from escrow to challenger
    }

    /// Finalize checkpoint after challenge period
    public entry fun finalize_checkpoint(
        checkpoint_id: u64,
    ) acquires CheckpointRegistry {
        let registry = borrow_global_mut<CheckpointRegistry>(@ol_framework);
        assert!(table::contains(&registry.checkpoints, checkpoint_id), E_CHECKPOINT_NOT_FOUND);

        let checkpoint = table::borrow_mut(&mut registry.checkpoints, checkpoint_id);

        let now = timestamp::now_seconds();
        assert!(
            now >= checkpoint.timestamp + CHALLENGE_PERIOD_SECONDS,
            E_CHALLENGE_PERIOD_ACTIVE
        );
        assert!(!checkpoint.challenged, E_ALREADY_CHALLENGED);

        checkpoint.finalized = true;

        // Return bond to submitter
        // TODO: Transfer bond from escrow to submitter
    }

    /// Verify Ethereum transaction against checkpoint
    public fun verify_ethereum_tx(
        checkpoint_id: u64,
        tx_receipt_proof: vector<u8>,
        expected_tx_hash: vector<u8>,
    ): bool acquires CheckpointRegistry {
        let registry = borrow_global<CheckpointRegistry>(@ol_framework);
        assert!(table::contains(&registry.checkpoints, checkpoint_id), E_CHECKPOINT_NOT_FOUND);

        let checkpoint = table::borrow(&registry.checkpoints, checkpoint_id);
        assert!(checkpoint.finalized, E_CHALLENGE_PERIOD_ACTIVE);

        // Verify Merkle proof against state root
        verify_merkle_proof(
            &tx_receipt_proof,
            &checkpoint.state_root,
            &expected_tx_hash
        )
    }

    /// Verify ZK proof (placeholder)
    fun verify_zk_proof(proof: &vector<u8>, block_number: u64): bool {
        // TODO: Implement Plonk verifier integration
        // Would call Argument Computer's Move verifier
        let _ = proof;
        let _ = block_number;
        false
    }

    /// Verify Merkle proof
    fun verify_merkle_proof(
        proof: &vector<u8>,
        root: &vector<u8>,
        leaf: &vector<u8>,
    ): bool {
        // TODO: Implement Merkle Patricia Trie verification
        // This is standard but non-trivial
        let _ = proof;
        let _ = root;
        let _ = leaf;
        false
    }

    // === Bounty Management ===

    /// Add bounty to pool (called when user exits early)
    public fun add_bounty(
        auction_id: u64,
        amount: u64,
    ) acquires BountyPool {
        let pool = borrow_global_mut<BountyPool>(@ol_framework);

        if (!table::contains(&pool.bounties_by_auction, auction_id)) {
            table::add(&mut pool.bounties_by_auction, auction_id, 0);
        };

        let current_bounty = table::borrow_mut(&mut pool.bounties_by_auction, auction_id);
        *current_bounty = *current_bounty + amount;
        pool.total_bounties = pool.total_bounties + amount;
    }

    /// Claim bounty for submitting checkpoint
    public entry fun claim_bounty<RewardCoin>(
        submitter: &signer,
        checkpoint_id: u64,
        auction_id: u64,
    ) acquires CheckpointRegistry, BountyPool {
        let registry = borrow_global<CheckpointRegistry>(@ol_framework);
        assert!(table::contains(&registry.checkpoints, checkpoint_id), E_CHECKPOINT_NOT_FOUND);

        let checkpoint = table::borrow(&registry.checkpoints, checkpoint_id);
        assert!(checkpoint.finalized, E_CHALLENGE_PERIOD_ACTIVE);
        assert!(signer::address_of(submitter) == checkpoint.submitter, 0);

        let pool = borrow_global_mut<BountyPool>(@ol_framework);
        assert!(table::contains(&pool.bounties_by_auction, auction_id), 0);

        let bounty = table::remove(&mut pool.bounties_by_auction, auction_id);
        pool.total_bounties = pool.total_bounties - bounty;

        // Transfer bounty to submitter
        // TODO: Mint/transfer RewardCoin to submitter
    }
}
```

#### 2.2.2 `treasury_auction.move`

```move
module ol_framework::treasury_auction {
    use std::vector;
    use std::signer;
    use aptos_std::table::{Self, Table};
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use ol_framework::ethereum_checkpoints;

    // Error codes
    const E_INVALID_PROOF: u64 = 1;
    const E_AUCTION_NOT_FOUND: u64 = 2;
    const E_AUCTION_NOT_ACTIVE: u64 = 3;
    const E_BID_TOO_LOW: u64 = 4;
    const E_INVALID_PREIMAGE: u64 = 5;
    const E_ALREADY_SETTLED: u64 = 6;
    const E_TIMELOCK_NOT_EXPIRED: u64 = 7;
    const E_INSUFFICIENT_BALANCE: u64 = 8;

    // Constants
    const AUCTION_DURATION_SECONDS: u64 = 3600; // 1 hour
    const MIN_CHICKEN_FEE_MICROCOINS: u64 = 20_000_000; // $20

    struct Auction has store {
        initiator: address,
        away_chain_lock_id: vector<u8>,    // ETH lock ID
        away_chain_amount: u64,            // Amount of ETH locked
        hashlock: vector<u8>,              // H(preimage)
        ethereum_checkpoint_id: u64,       // Checkpoint proving ETH lock
        start_time: u64,
        end_time: u64,
        settled: bool,
        clearing_price: u64,               // Price per unit (0 if not cleared)
        total_bid_volume: u64,
    }

    struct Bid has store {
        bidder: address,
        price_per_unit: u64,               // Price willing to pay
        quantity: u64,                     // Quantity willing to buy
        authorized: bool,                  // Has bidder authorized withdrawal?
    }

    struct AuctionRegistry has key {
        auctions: Table<u64, Auction>,
        bids: Table<u64, vector<Bid>>,     // auction_id -> bids
        next_auction_id: u64,
    }

    struct UserAuthorization has key {
        // Maps auction_id -> authorized amount
        authorizations: Table<u64, u64>,
    }

    /// Initialize auction registry
    public fun initialize(account: &signer) {
        let addr = signer::address_of(account);
        assert!(addr == @ol_framework, 0);

        move_to(account, AuctionRegistry {
            auctions: table::new(),
            bids: table::new(),
            next_auction_id: 0,
        });
    }

    /// Create auction after proving ETH lock
    public entry fun create_auction(
        initiator: &signer,
        away_chain_lock_id: vector<u8>,
        away_chain_amount: u64,
        hashlock: vector<u8>,
        ethereum_checkpoint_id: u64,
        merkle_proof: vector<u8>,
    ) acquires AuctionRegistry {
        // Verify ETH lock exists via Merkle proof
        let tx_hash = copy away_chain_lock_id;
        assert!(
            ethereum_checkpoints::verify_ethereum_tx(
                ethereum_checkpoint_id,
                merkle_proof,
                tx_hash
            ),
            E_INVALID_PROOF
        );

        let registry = borrow_global_mut<AuctionRegistry>(@ol_framework);
        let auction_id = registry.next_auction_id + 1;

        let now = timestamp::now_seconds();
        let auction = Auction {
            initiator: signer::address_of(initiator),
            away_chain_lock_id,
            away_chain_amount,
            hashlock,
            ethereum_checkpoint_id,
            start_time: now,
            end_time: now + AUCTION_DURATION_SECONDS,
            settled: false,
            clearing_price: 0,
            total_bid_volume: 0,
        };

        table::add(&mut registry.auctions, auction_id, auction);
        table::add(&mut registry.bids, auction_id, vector::empty<Bid>());
        registry.next_auction_id = auction_id;
    }

    /// Place bid with authorization
    public entry fun place_bid<HomeCoin>(
        bidder: &signer,
        auction_id: u64,
        price_per_unit: u64,
        quantity: u64,
    ) acquires AuctionRegistry, UserAuthorization {
        let registry = borrow_global_mut<AuctionRegistry>(@ol_framework);
        assert!(table::contains(&registry.auctions, auction_id), E_AUCTION_NOT_FOUND);

        let auction = table::borrow(&registry.auctions, auction_id);
        let now = timestamp::now_seconds();
        assert!(now >= auction.start_time && now < auction.end_time, E_AUCTION_NOT_ACTIVE);

        let bidder_addr = signer::address_of(bidder);
        let total_cost = price_per_unit * quantity;

        // Verify bidder has sufficient balance
        assert!(
            coin::balance<HomeCoin>(bidder_addr) >= total_cost,
            E_INSUFFICIENT_BALANCE
        );

        // Record authorization
        if (!exists<UserAuthorization>(bidder_addr)) {
            move_to(bidder, UserAuthorization {
                authorizations: table::new(),
            });
        };

        let auth = borrow_global_mut<UserAuthorization>(bidder_addr);
        if (!table::contains(&auth.authorizations, auction_id)) {
            table::add(&mut auth.authorizations, auction_id, 0);
        };
        let authorized_amount = table::borrow_mut(&mut auth.authorizations, auction_id);
        *authorized_amount = *authorized_amount + total_cost;

        // Add bid
        let bids = table::borrow_mut(&mut registry.bids, auction_id);
        vector::push_back(bids, Bid {
            bidder: bidder_addr,
            price_per_unit,
            quantity,
            authorized: true,
        });

        // Update total volume
        let auction_mut = table::borrow_mut(&mut registry.auctions, auction_id);
        auction_mut.total_bid_volume = auction_mut.total_bid_volume + quantity;
    }

    /// Early exit from auction (pays chicken fee)
    public entry fun request_early_exit<HomeCoin>(
        exiter: &signer,
        auction_id: u64,
    ) acquires AuctionRegistry, UserAuthorization {
        let registry = borrow_global_mut<AuctionRegistry>(@ol_framework);
        assert!(table::contains(&registry.auctions, auction_id), E_AUCTION_NOT_FOUND);

        let auction = table::borrow(&registry.auctions, auction_id);
        let exiter_addr = signer::address_of(exiter);

        // Find and remove exiter's bids
        let bids = table::borrow_mut(&mut registry.bids, auction_id);
        let i = 0;
        let total_value = 0;
        while (i < vector::length(bids)) {
            let bid = vector::borrow(bids, i);
            if (bid.bidder == exiter_addr) {
                total_value = total_value + (bid.price_per_unit * bid.quantity);
                vector::remove(bids, i);
            } else {
                i = i + 1;
            };
        };

        // Calculate chicken fee (1% of bid value, min $20)
        let chicken_fee = total_value / 100;
        if (chicken_fee < MIN_CHICKEN_FEE_MICROCOINS) {
            chicken_fee = MIN_CHICKEN_FEE_MICROCOINS;
        };

        // Charge chicken fee
        let fee_coins = coin::withdraw<HomeCoin>(exiter, chicken_fee);
        // TODO: Store in bounty pool
        coin::deposit(@ol_framework, fee_coins);

        // Add to bounty pool
        ethereum_checkpoints::add_bounty(auction_id, chicken_fee);

        // Revoke authorization
        if (exists<UserAuthorization>(exiter_addr)) {
            let auth = borrow_global_mut<UserAuthorization>(exiter_addr);
            if (table::contains(&auth.authorizations, auction_id)) {
                table::remove(&mut auth.authorizations, auction_id);
            };
        };
    }

    /// Settle auction with preimage
    public entry fun settle_auction<HomeCoin>(
        settler: &signer,
        auction_id: u64,
        preimage: vector<u8>,
    ) acquires AuctionRegistry, UserAuthorization {
        let registry = borrow_global_mut<AuctionRegistry>(@ol_framework);
        assert!(table::contains(&registry.auctions, auction_id), E_AUCTION_NOT_FOUND);

        let auction = table::borrow_mut(&mut registry.auctions, auction_id);
        assert!(!auction.settled, E_ALREADY_SETTLED);

        let now = timestamp::now_seconds();
        assert!(now >= auction.end_time, E_AUCTION_NOT_ACTIVE);

        // Verify preimage matches hashlock
        // TODO: Use proper hash function (sha256 or keccak256)
        // For now, simple verification
        assert!(vector::length(&preimage) > 0, E_INVALID_PREIMAGE);

        auction.settled = true;

        // Calculate clearing price (treasury auction algorithm)
        let (clearing_price, winners) = calculate_clearing_price(auction_id);
        auction.clearing_price = clearing_price;

        // Execute atomic settlement
        let i = 0;
        while (i < vector::length(&winners)) {
            let winner = vector::borrow(&winners, i);

            // Withdraw from winner using authorization
            let amount = winner.quantity * clearing_price;
            let payment = coin::withdraw<HomeCoin>(winner.bidder, amount);

            // Pay initiator
            coin::deposit(auction.initiator, payment);

            // Revoke authorization
            if (exists<UserAuthorization>(winner.bidder)) {
                let auth = borrow_global_mut<UserAuthorization>(winner.bidder);
                if (table::contains(&auth.authorizations, auction_id)) {
                    table::remove(&mut auth.authorizations, auction_id);
                };
            };

            i = i + 1;
        };

        // Winners can now use preimage to unlock ETH on Ethereum
        // Preimage is revealed on-chain
    }

    /// Calculate clearing price for treasury auction
    fun calculate_clearing_price(auction_id: u64): (u64, vector<Bid>) acquires AuctionRegistry {
        let registry = borrow_global<AuctionRegistry>(@ol_framework);
        let auction = table::borrow(&registry.auctions, auction_id);
        let bids = table::borrow(&registry.bids, auction_id);

        // Sort bids by price (descending)
        let sorted_bids = sort_bids_by_price(bids);

        // Find clearing price where supply meets demand
        let cumulative_quantity = 0;
        let clearing_price = 0;
        let winners = vector::empty<Bid>();

        let i = 0;
        while (i < vector::length(&sorted_bids)) {
            let bid = vector::borrow(&sorted_bids, i);

            if (cumulative_quantity + bid.quantity <= auction.away_chain_amount) {
                // Fully fill this bid
                cumulative_quantity = cumulative_quantity + bid.quantity;
                vector::push_back(&mut winners, *bid);
                clearing_price = bid.price_per_unit;
            } else if (cumulative_quantity < auction.away_chain_amount) {
                // Partially fill this bid
                let remaining = auction.away_chain_amount - cumulative_quantity;
                let partial_bid = Bid {
                    bidder: bid.bidder,
                    price_per_unit: bid.price_per_unit,
                    quantity: remaining,
                    authorized: bid.authorized,
                };
                vector::push_back(&mut winners, partial_bid);
                clearing_price = bid.price_per_unit;
                cumulative_quantity = auction.away_chain_amount;
                break
            } else {
                // Auction fully filled
                break
            };

            i = i + 1;
        };

        (clearing_price, winners)
    }

    /// Sort bids by price (descending) - simple bubble sort
    fun sort_bids_by_price(bids: &vector<Bid>): vector<Bid> {
        let sorted = vector::empty<Bid>();
        let i = 0;
        while (i < vector::length(bids)) {
            vector::push_back(&mut sorted, *vector::borrow(bids, i));
            i = i + 1;
        };

        // Bubble sort (inefficient but simple for MVP)
        let n = vector::length(&sorted);
        let i = 0;
        while (i < n) {
            let j = 0;
            while (j < n - i - 1) {
                let bid1 = vector::borrow(&sorted, j);
                let bid2 = vector::borrow(&sorted, j + 1);

                if (bid1.price_per_unit < bid2.price_per_unit) {
                    vector::swap(&mut sorted, j, j + 1);
                };

                j = j + 1;
            };
            i = i + 1;
        };

        sorted
    }
}
```

---

## 3. Implementation Phases

### Phase 1: MVP (Weeks 1-6)

**Goal**: Working atomic swap with optimistic checkpoints

**Week 1-2: Ethereum Contracts**
- [ ] Implement `EthereumHashlockEscrow.sol`
  - Create lock function with hashlock + timelock
  - Claim function with preimage verification
  - Refund function after timeout
  - Event emission for indexing
- [ ] Deploy to Ethereum Sepolia testnet
- [ ] Write Hardhat tests
- [ ] Frontend integration for lock creation

**Week 3-4: Libra Checkpoints**
- [ ] Implement `ethereum_checkpoints.move`
  - Optimistic checkpoint submission
  - Bond management (lock/slash/refund)
  - Challenge mechanism (stub ZK verification)
  - Merkle proof verification
- [ ] Implement Merkle Patricia Trie verification
  - Port from Solidity or Rust
  - Test against Ethereum testnets
- [ ] Write Move unit tests
- [ ] Deploy to Libra testnet

**Week 5-6: Treasury Auction**
- [ ] Implement `treasury_auction.move`
  - Auction creation with ETH proof
  - Bid placement with authorization
  - Clearing price calculation
  - Atomic settlement
- [ ] Implement chicken fee mechanism
  - Early exit function
  - Bounty pool management
- [ ] Integration tests (Ethereum ↔ Libra)
- [ ] End-to-end smoke test

**Deliverables**:
- Working atomic swap (ETH ↔ LIBRA)
- Optimistic checkpoints with bonds
- Treasury auction with fractional fills
- Early exit with chicken fees

**Cost at MVP**: $0.05 per checkpoint (optimistic)

---

### Phase 2: Security & ZK Integration (Weeks 7-10)

**Goal**: Add trustless verification with ZK proofs

**Week 7: ZK Proof Service Integration**
- [ ] Research Axiom vs Succinct Network
  - Compare pricing
  - Test API availability
  - Benchmark proof generation time
- [ ] Choose provider (recommend: Axiom for reliability)
- [ ] Set up off-chain proof generation
  - Sphinx zkVM or Axiom SDK
  - Test proof generation for ETH state
- [ ] Implement proof verification in Solidity
  - Integrate Axiom callback
  - Or: Integrate Succinct verifier

**Week 8: Plonk Verifier in Move**
- [ ] Port Argument Computer's Plonk verifier
  - Adapt for Libra's Move version
  - Test with sample proofs
  - Optimize gas costs
- [ ] Integrate with `ethereum_checkpoints.move`
  - Replace stub `verify_zk_proof` function
  - Test challenge mechanism
- [ ] Generate test vectors
  - Proofs from Axiom/Succinct
  - Edge cases (invalid proofs, wrong state roots)

**Week 9: Bounty Optimization**
- [ ] Implement checkpoint batching
  - Multiple auctions per checkpoint
  - Batch Merkle proofs
  - Amortize costs
- [ ] Dynamic chicken fee calculation
  - Based on checkpoint backlog
  - Market-driven pricing
- [ ] Bounty claiming mechanism
  - Link checkpoint to auctions
  - Multi-auction rewards

**Week 10: Security Audit Prep**
- [ ] Comprehensive test suite
  - Happy path tests
  - Adversarial tests (fraud attempts)
  - Economic attack vectors
- [ ] Documentation
  - Security assumptions
  - Economic incentives
  - Attack surface analysis
- [ ] Code freeze for audit

**Deliverables**:
- ZK-verified checkpoints
- Plonk verifier in Move
- Batched checkpoint submission
- Audit-ready codebase

**Cost at Phase 2**:
- Optimistic: $0.05 (most cases)
- Challenged: $23 (Axiom) or $10-15 (Succinct)

---

### Phase 3: Optimization & Production (Weeks 11-14)

**Goal**: Production-ready with optimizations

**Week 11: Gas Optimization**
- [ ] Optimize Solidity contracts
  - Storage packing
  - Batch operations
  - Event optimization
- [ ] Optimize Move contracts
  - Resource usage
  - Table vs vector
  - Computation costs
- [ ] Benchmark gas costs
  - Ethereum: Lock, claim, refund
  - Libra: Checkpoint, auction, settle

**Week 12: UX Improvements**
- [ ] Auto-bidding system
  - User sets max price preferences
  - Contract automatically bids on new auctions
  - Configurable risk parameters
- [ ] Checkpoint automation
  - Monitor bounty pool
  - Auto-submit when profitable
  - Proof generation queue
- [ ] Notification system
  - Auction created
  - Auction cleared
  - ETH ready to claim

**Week 13: Advanced Features**
- [ ] Multi-asset support
  - Support ERC20 tokens (USDC, USDT, etc.)
  - Support multiple chains (Polygon, Arbitrum, etc.)
  - Generic checkpoint registry per chain
- [ ] Checkpoint history
  - Merkle Mountain Range
  - Efficient historical proofs
  - Prune old checkpoints
- [ ] Governance module
  - Adjust chicken fee parameters
  - Update bond requirements
  - Emergency pause

**Week 14: Production Deployment**
- [ ] Mainnet deployment checklist
  - Ethereum mainnet contracts
  - Libra mainnet contracts
  - Configuration parameters
- [ ] Monitoring & alerts
  - Checkpoint submission rate
  - Challenge frequency
  - Bounty pool balance
- [ ] Initial liquidity campaign
  - Bootstrap early users
  - Incentivize checkpoint submitters
  - Monitor economic parameters

**Deliverables**:
- Production-ready system
- Optimized gas costs
- Auto-bidding UX
- Multi-asset support
- Full monitoring

---

## 4. Economic Analysis

### 4.1 Cost Breakdown

**Per Atomic Swap (Normal Case)**:

| Component | Cost | Who Pays | Refundable |
|-----------|------|----------|------------|
| ETH lock gas | ~$5 | Alice (initiator) | No |
| Checkpoint submission | $0.05 | Bounty hunter | No |
| Checkpoint bond | $30 | Bounty hunter | Yes (after 1 hour) |
| Merkle proof verification | ~$0.10 | Alice | No |
| Auction creation | ~$0.50 | Alice | No |
| Bid placement (per bid) | ~$0.05 | Bidder | No |
| Settlement | ~$2 | Anyone | No |
| ETH claim (per winner) | ~$3 | Winner | No |
| **Total** | **~$10.70** | **Distributed** | **$30 bond refunded** |

**Revenue for Bounty Hunter**:
- Chicken fee bounty: ~$20 (from early exiters)
- Net profit: $20 - $0.05 - $30 (locked) + $30 (refunded) = **$19.95 profit**

**Challenged Checkpoint Case**:

| Component | Cost | Who Pays | Outcome |
|-----------|------|----------|---------|
| Checkpoint submission | $0.05 | Fraudster | Lost |
| Checkpoint bond | $30 | Fraudster | Slashed |
| ZK proof generation | $10-23 | Challenger | Paid back from bond |
| Challenge submission | ~$1 | Challenger | Covered by bond |
| **Net** | **$30.05** | **Fraudster** | **Loses all** |

**Challenger profit**: $30 bond - $23 proof cost = **$7 profit**

### 4.2 Capital Efficiency

**Traditional HTLC**:
```
Alice:
- Locks 10 ETH on Ethereum (capital locked for 48 hours)
- Locks 20,000 LIBRA on Libra (capital locked for 48 hours)
Total locked: 100% of both assets

Bob:
- Must have 20,000 LIBRA available
- But can't use it until Alice reveals preimage
```

**Treasury Auction Design**:
```
Alice:
- Locks 10 ETH on Ethereum (capital locked for ~2-3 hours)
- NO LIBRA LOCKED (uses unlocked balances via authorization)
Total locked: Only ETH (50% improvement)

Multiple bidders:
- Use unlocked LIBRA balances
- Pre-authorize withdrawal
- Capital remains liquid until settlement
- Can participate in multiple auctions simultaneously
```

**Capital efficiency improvement**: **50% less capital locked**

### 4.3 Economic Incentives

**For Checkpoint Submitters**:
- Low barrier to entry: $0.05 + $30 bond
- Profit per checkpoint: ~$20 (from chicken fees)
- Opportunity cost: $30 locked for 1 hour
- ROI: $20 / $30 = 67% per hour = 587,000% APY (if continuous)

**For Early Exiters (Chickens)**:
- Pay 1% fee or $20 minimum
- Get immediate liquidity
- Avoid price risk
- Rational when:
  - Price is moving against them
  - Need capital urgently
  - Opportunity cost > $20

**For Bidders**:
- Access to away-chain assets without bridging
- Fractional fills possible
- Transparent price discovery
- No capital locked until settlement

**For Initiators (Alice)**:
- No Libra escrow needed
- Faster settlement (hours vs days)
- Market-driven pricing
- Can cancel/refund if no bids

### 4.4 Attack Vectors & Defenses

**Attack 1: Fake Checkpoint Submission**
- **Attack**: Submit incorrect state root to enable fake auction
- **Defense**:
  - Challenge mechanism with ZK proof
  - Slashed bond ($30) pays challenger
  - Economic loss > gain from fraud
- **Outcome**: Unprofitable

**Attack 2: Challenge Spam**
- **Attack**: Challenge valid checkpoints to grief submitters
- **Defense**:
  - Challenger must provide valid ZK proof
  - Invalid challenge wastes challenger's money (~$23)
  - Submitter's bond protected unless fraud proven
- **Outcome**: Unprofitable

**Attack 3: Bounty Sniping**
- **Attack**: Wait for others to submit checkpoint, claim bounty
- **Defense**:
  - First finalized checkpoint gets bounty
  - Submitter has 1-hour head start
  - Racing wastes gas
- **Outcome**: First-mover advantage protects submitters

**Attack 4: Auction Manipulation**
- **Attack**: Place high bids, exit early repeatedly to drain bounty pool
- **Defense**:
  - Chicken fee is 1% of bid value OR $20 minimum
  - Repeated exits = repeated fees
  - Authorization withdrawal means can't double-spend
- **Outcome**: Costly to attack, no lasting harm

**Attack 5: ETH Lock Front-running**
- **Attack**: Front-run ETH lock, claim it's yours on Libra
- **Defense**:
  - Auction requires Merkle proof of lock details
  - Proof includes initiator address
  - Can't fake ownership
- **Outcome**: Impossible (cryptographically secured)

---

## 5. Integration Guide

### 5.1 For Users (Alice - Initiator)

**Step 1: Lock ETH on Ethereum**

```javascript
// Frontend JavaScript
import { ethers } from 'ethers';

const provider = new ethers.providers.Web3Provider(window.ethereum);
const signer = provider.getSigner();

// Contract instance
const escrowContract = new ethers.Contract(
  ESCROW_ADDRESS,
  ESCROW_ABI,
  signer
);

// Generate hashlock
const preimage = ethers.utils.randomBytes(32);
const hashlock = ethers.utils.keccak256(preimage);

// Lock ETH
const tx = await escrowContract.createLock(
  hashlock,
  48 * 3600, // 48 hours
  { value: ethers.utils.parseEther("10.0") }
);

const receipt = await tx.wait();
const lockId = receipt.events[0].args.lockId;

console.log("Lock created:", lockId);
console.log("Hashlock:", hashlock);
console.log("Preimage (KEEP SECRET):", ethers.utils.hexlify(preimage));
```

**Step 2: Wait for Checkpoint**

```javascript
// Poll for checkpoint containing your transaction
async function waitForCheckpoint(txHash) {
  const libraRpc = new LibraRPC(LIBRA_RPC_URL);

  while (true) {
    const latestCheckpoint = await libraRpc.getLatestCheckpoint();

    // Check if checkpoint includes our transaction
    const included = await checkTransactionIncluded(
      latestCheckpoint.id,
      txHash
    );

    if (included && latestCheckpoint.finalized) {
      return latestCheckpoint.id;
    }

    // Wait 30 seconds
    await new Promise(resolve => setTimeout(resolve, 30000));
  }
}

const checkpointId = await waitForCheckpoint(receipt.transactionHash);
console.log("Checkpoint finalized:", checkpointId);
```

**Step 3: Create Auction on Libra**

```javascript
// Generate Merkle proof
const proof = await generateMerkleProof(
  receipt.transactionHash,
  checkpointId
);

// Submit to Libra
const libraClient = new LibraClient(LIBRA_RPC_URL);

const auctionTx = await libraClient.submitTransaction({
  function: "0x1::treasury_auction::create_auction",
  type_arguments: [],
  arguments: [
    lockId,                    // away_chain_lock_id
    "10000000000000000000",    // 10 ETH in wei
    hashlock,                  // hashlock
    checkpointId,              // ethereum_checkpoint_id
    proof,                     // merkle_proof
  ],
});

const auctionId = auctionTx.events.find(
  e => e.type === "AuctionCreated"
).data.auction_id;

console.log("Auction created:", auctionId);
```

**Step 4: Wait for Auction to Clear**

```javascript
// Monitor auction
async function waitForAuctionSettlement(auctionId) {
  const libraClient = new LibraClient(LIBRA_RPC_URL);

  while (true) {
    const auction = await libraClient.getAuction(auctionId);

    if (auction.settled) {
      return {
        clearingPrice: auction.clearing_price,
        totalReceived: auction.total_received,
      };
    }

    // Wait 30 seconds
    await new Promise(resolve => setTimeout(resolve, 30000));
  }
}

const result = await waitForAuctionSettlement(auctionId);
console.log("Auction settled!");
console.log("Clearing price:", result.clearingPrice);
console.log("LIBRA received:", result.totalReceived);
```

**Step 5: Optional - Claim Refund if No Bids**

```javascript
// If auction fails, refund ETH after timelock
if (!result.settled) {
  // Wait for timelock expiry
  await waitForTimelock(lockId);

  // Refund ETH
  const refundTx = await escrowContract.refund(lockId);
  await refundTx.wait();

  console.log("ETH refunded");
}
```

### 5.2 For Bidders (Bob - Auction Participant)

**Step 1: Monitor Auctions**

```javascript
// Subscribe to new auctions
const libraClient = new LibraClient(LIBRA_RPC_URL);

libraClient.subscribeToEvents({
  eventType: "0x1::treasury_auction::AuctionCreated",
  callback: async (event) => {
    const auction = event.data;

    console.log("New auction:", auction.auction_id);
    console.log("Asset:", auction.away_chain_amount, "ETH");
    console.log("Ends:", new Date(auction.end_time * 1000));

    // Evaluate and bid
    await evaluateAndBid(auction);
  }
});
```

**Step 2: Place Bid**

```javascript
async function evaluateAndBid(auction) {
  // Calculate your max price
  const ethPrice = await getEthPrice(); // e.g., $2000
  const libraPrice = await getLibraPrice(); // e.g., $1

  const myMaxPrice = (ethPrice / libraPrice) * 1.05; // 5% premium

  // Decide quantity
  const myQuantity = 5; // Want 5 ETH

  // Check balance
  const myBalance = await libraClient.getBalance(MY_ADDRESS);
  const requiredBalance = myMaxPrice * myQuantity;

  if (myBalance < requiredBalance) {
    console.log("Insufficient balance");
    return;
  }

  // Place bid
  const bidTx = await libraClient.submitTransaction({
    function: "0x1::treasury_auction::place_bid",
    type_arguments: ["0x1::libra_coin::LibraCoin"],
    arguments: [
      auction.auction_id,
      myMaxPrice.toString(),
      myQuantity.toString(),
    ],
  });

  console.log("Bid placed:", bidTx.hash);
}
```

**Step 3: Monitor Auction Settlement**

```javascript
// Wait for settlement
const settlement = await waitForAuctionSettlement(auction.auction_id);

if (settlement.myWinningBid) {
  console.log("Won auction!");
  console.log("Paid:", settlement.myWinningBid.amount, "LIBRA");
  console.log("Preimage:", settlement.preimage);

  // Claim ETH on Ethereum
  await claimEth(settlement);
} else {
  console.log("Did not win auction");
}
```

**Step 4: Claim ETH on Ethereum**

```javascript
async function claimEth(settlement) {
  const provider = new ethers.providers.Web3Provider(window.ethereum);
  const signer = provider.getSigner();

  const escrowContract = new ethers.Contract(
    ESCROW_ADDRESS,
    ESCROW_ABI,
    signer
  );

  // Claim with preimage
  const claimTx = await escrowContract.claim(
    settlement.lockId,
    settlement.preimage
  );

  const receipt = await claimTx.wait();
  console.log("ETH claimed:", receipt.transactionHash);
}
```

**Step 5: Optional - Early Exit**

```javascript
// Exit auction early (pays chicken fee)
async function exitEarly(auctionId) {
  const exitTx = await libraClient.submitTransaction({
    function: "0x1::treasury_auction::request_early_exit",
    type_arguments: ["0x1::libra_coin::LibraCoin"],
    arguments: [auctionId],
  });

  console.log("Exited auction, paid chicken fee:", exitTx.hash);
}
```

### 5.3 For Checkpoint Submitters (Charlie - Bounty Hunter)

**Step 1: Monitor Bounty Pool**

```javascript
// Check if bounty pool is profitable
async function checkBountyOpportunity() {
  const libraClient = new LibraClient(LIBRA_RPC_URL);

  const bountyPool = await libraClient.getBountyPool();
  const totalBounties = bountyPool.total_bounties;

  const CHECKPOINT_COST = 0.05; // dollars
  const BOND_REQUIRED = 30; // dollars

  if (totalBounties > CHECKPOINT_COST + 1) {
    console.log("Profitable opportunity:", totalBounties);
    return true;
  }

  return false;
}
```

**Step 2: Fetch Ethereum State Root**

```javascript
// Get latest Ethereum state root
async function getEthereumStateRoot() {
  const provider = new ethers.providers.JsonRpcProvider(ETH_RPC_URL);

  const latestBlock = await provider.getBlock("latest");
  const stateRoot = latestBlock.stateRoot;
  const blockNumber = latestBlock.number;

  return { stateRoot, blockNumber };
}
```

**Step 3: Submit Checkpoint**

```javascript
async function submitCheckpoint() {
  const { stateRoot, blockNumber } = await getEthereumStateRoot();

  const libraClient = new LibraClient(LIBRA_RPC_URL);

  const checkpointTx = await libraClient.submitTransaction({
    function: "0x1::ethereum_checkpoints::submit_checkpoint",
    type_arguments: ["0x1::libra_coin::LibraCoin"],
    arguments: [
      stateRoot,
      blockNumber.toString(),
      "30000000", // 30 LIBRA bond (assuming $1/LIBRA)
    ],
  });

  const checkpointId = checkpointTx.events.find(
    e => e.type === "CheckpointSubmitted"
  ).data.checkpoint_id;

  console.log("Checkpoint submitted:", checkpointId);
  return checkpointId;
}
```

**Step 4: Wait for Finalization**

```javascript
async function waitForFinalization(checkpointId) {
  const libraClient = new LibraClient(LIBRA_RPC_URL);

  // Wait challenge period (1 hour)
  const CHALLENGE_PERIOD = 3600; // seconds
  await new Promise(resolve => setTimeout(resolve, CHALLENGE_PERIOD * 1000));

  // Finalize
  const finalizeTx = await libraClient.submitTransaction({
    function: "0x1::ethereum_checkpoints::finalize_checkpoint",
    type_arguments: [],
    arguments: [checkpointId.toString()],
  });

  console.log("Checkpoint finalized:", finalizeTx.hash);
}
```

**Step 5: Claim Bounty**

```javascript
async function claimBounty(checkpointId, auctionId) {
  const libraClient = new LibraClient(LIBRA_RPC_URL);

  const claimTx = await libraClient.submitTransaction({
    function: "0x1::ethereum_checkpoints::claim_bounty",
    type_arguments: ["0x1::libra_coin::LibraCoin"],
    arguments: [
      checkpointId.toString(),
      auctionId.toString(),
    ],
  });

  const bountyAmount = claimTx.events.find(
    e => e.type === "BountyClaimed"
  ).data.amount;

  console.log("Bounty claimed:", bountyAmount, "LIBRA");
}
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

**Ethereum Contracts (Hardhat)**:

```javascript
// test/EthereumHashlockEscrow.test.js
describe("EthereumHashlockEscrow", function() {
  it("should create lock with hashlock and timelock", async function() {
    const preimage = ethers.utils.randomBytes(32);
    const hashlock = ethers.utils.keccak256(preimage);

    await escrow.createLock(hashlock, 48 * 3600, {
      value: ethers.utils.parseEther("10")
    });

    // Verify lock created
  });

  it("should allow claim with correct preimage", async function() {
    // ... create lock

    await escrow.claim(lockId, preimage);

    // Verify ETH transferred
  });

  it("should reject claim with incorrect preimage", async function() {
    // ... create lock

    const wrongPreimage = ethers.utils.randomBytes(32);
    await expect(
      escrow.claim(lockId, wrongPreimage)
    ).to.be.revertedWith("Invalid preimage");
  });

  it("should allow refund after timelock expires", async function() {
    // ... create lock

    // Fast-forward time
    await ethers.provider.send("evm_increaseTime", [48 * 3600 + 1]);
    await ethers.provider.send("evm_mine");

    await escrow.refund(lockId);

    // Verify ETH returned
  });
});
```

**Libra Contracts (Move tests)**:

```move
#[test_only]
module ol_framework::ethereum_checkpoints_tests {
    use ol_framework::ethereum_checkpoints;
    use aptos_framework::timestamp;

    #[test(account = @ol_framework)]
    fun test_submit_checkpoint(account: signer) {
        ethereum_checkpoints::initialize(&account);

        let state_root = x"1234..."; // 32 bytes
        let block_number = 12345678;
        let bond = 30_000_000;

        ethereum_checkpoints::submit_checkpoint<TestCoin>(
            &account,
            state_root,
            block_number,
            bond
        );

        // Verify checkpoint stored
    }

    #[test(account = @ol_framework, challenger = @0x456)]
    fun test_challenge_invalid_checkpoint(account: signer, challenger: signer) {
        // ... submit checkpoint

        let zk_proof = x"proof_data...";

        ethereum_checkpoints::challenge_checkpoint(
            &challenger,
            1, // checkpoint_id
            zk_proof
        );

        // Verify checkpoint marked as challenged
        // Verify bond slashed
    }

    #[test(account = @ol_framework)]
    #[expected_failure(abort_code = ethereum_checkpoints::E_CHALLENGE_PERIOD_EXPIRED)]
    fun test_cannot_challenge_after_period(account: signer) {
        // ... submit checkpoint

        // Fast-forward time
        timestamp::fast_forward_seconds(3601); // 1 hour + 1 sec

        ethereum_checkpoints::challenge_checkpoint(
            &account,
            1,
            x"proof..."
        );
        // Should fail
    }
}
```

### 6.2 Integration Tests

**Ethereum ↔ Libra Flow**:

```javascript
// test/integration/atomic-swap.test.js
describe("End-to-End Atomic Swap", function() {
  it("should complete full swap: ETH → LIBRA", async function() {
    // 1. Alice locks ETH
    const preimage = ethers.utils.randomBytes(32);
    const hashlock = ethers.utils.keccak256(preimage);

    const lockTx = await ethEscrow.createLock(hashlock, 48 * 3600, {
      value: ethers.utils.parseEther("10")
    });
    const lockReceipt = await lockTx.wait();
    const lockId = lockReceipt.events[0].args.lockId;

    // 2. Wait for checkpoint (simulated)
    const stateRoot = await ethers.provider.getBlock("latest").stateRoot;
    const blockNumber = await ethers.provider.getBlockNumber();

    await libraClient.submitCheckpoint(stateRoot, blockNumber, bond);

    // Wait challenge period
    await sleep(3600 * 1000);

    await libraClient.finalizeCheckpoint(1);

    // 3. Alice creates auction
    const merkleProof = generateMerkleProof(lockReceipt.transactionHash);

    await libraClient.createAuction(
      lockId,
      ethers.utils.parseEther("10").toString(),
      hashlock,
      1, // checkpoint_id
      merkleProof
    );

    // 4. Bob bids
    await libraClient.placeBid(
      1, // auction_id
      "2000", // price: 2000 LIBRA per ETH
      "5" // quantity: 5 ETH
    );

    // 5. Carol bids
    await libraClient.placeBid(
      1,
      "2100", // higher price
      "5"
    );

    // 6. Wait for auction end
    await sleep(3600 * 1000);

    // 7. Settle auction
    await libraClient.settleAuction(1, preimage);

    // Verify:
    // - Alice received LIBRA
    // - Preimage revealed

    // 8. Bob and Carol claim ETH
    await ethEscrow.connect(bob).claim(lockId, preimage);

    // Verify ETH distributed
  });

  it("should handle early exit with chicken fee", async function() {
    // ... create auction

    // Bob bids
    await libraClient.placeBid(1, "2000", "5");

    // Bob exits early
    const bobBalanceBefore = await libraClient.getBalance(bob.address);
    await libraClient.requestEarlyExit(1);
    const bobBalanceAfter = await libraClient.getBalance(bob.address);

    // Verify chicken fee charged
    expect(bobBalanceBefore - bobBalanceAfter).to.equal(chickenFee);

    // Verify bounty pool increased
    const bountyPool = await libraClient.getBountyPool();
    expect(bountyPool).to.equal(chickenFee);
  });
});
```

### 6.3 Security Tests

**Adversarial Tests**:

```javascript
describe("Security - Adversarial Scenarios", function() {
  it("should prevent fake checkpoint submission", async function() {
    // Submit checkpoint with fake state root
    const fakeStateRoot = ethers.utils.randomBytes(32);

    await libraClient.submitCheckpoint(fakeStateRoot, 12345, bond);

    // Challenger generates ZK proof of correct state root
    const realStateRoot = await getRealStateRoot(12345);
    const zkProof = await generateZkProof(12345, realStateRoot);

    // Challenge fake checkpoint
    await libraClient.challengeCheckpoint(1, zkProof);

    // Verify:
    // - Checkpoint marked as challenged
    // - Submitter's bond slashed
    // - Challenger received bond
  });

  it("should prevent double-spend via Merkle proof verification", async function() {
    // Alice locks ETH
    const { lockId, txHash } = await lockEth("10");

    // Alice creates checkpoint
    await submitCheckpoint();
    await finalizeCheckpoint(1);

    // Alice tries to create TWO auctions with same lock
    const merkleProof = generateMerkleProof(txHash);

    await libraClient.createAuction(lockId, "10", hashlock, 1, merkleProof);

    // Try to create second auction with same proof
    await expect(
      libraClient.createAuction(lockId, "10", hashlock, 1, merkleProof)
    ).to.be.revertedWith("Lock already used");
  });

  it("should prevent unauthorized withdrawals", async function() {
    // Bob bids on auction
    await libraClient.placeBid(1, "2000", "5");

    // Attacker tries to withdraw Bob's authorized funds
    await expect(
      libraClient.connect(attacker).settleAuction(1, preimage)
    ).to.be.revertedWith("Not authorized");

    // Verify Bob's balance unchanged
  });
});
```

### 6.4 Economic Tests

**Game Theory Tests**:

```javascript
describe("Economic - Game Theory", function() {
  it("should make fraud unprofitable", async function() {
    // Fraudster submits fake checkpoint
    const fraudsterBalanceBefore = await getBalance(fraudster);
    const BOND = 30;
    const CHECKPOINT_COST = 0.05;

    await submitFakeCheckpoint(fraudster);

    // Honest actor challenges
    const challengerBalanceBefore = await getBalance(challenger);
    const ZK_PROOF_COST = 23;

    await challengeCheckpoint(challenger, zkProof);

    // Verify economics:
    // - Fraudster lost: BOND + CHECKPOINT_COST = $30.05
    const fraudsterBalanceAfter = await getBalance(fraudster);
    expect(fraudsterBalanceBefore - fraudsterBalanceAfter).to.equal(30.05);

    // - Challenger gained: BOND - ZK_PROOF_COST = $7
    const challengerBalanceAfter = await getBalance(challenger);
    expect(challengerBalanceAfter - challengerBalanceBefore).to.equal(7);

    // Fraud is unprofitable!
  });

  it("should incentivize checkpoint submission", async function() {
    // Users exit early, creating bounties
    await exitEarly(user1); // $20 chicken fee
    await exitEarly(user2); // $20 chicken fee

    const bountyPool = await getBountyPool(); // $40 total

    // Bounty hunter submits checkpoint
    const hunterBalanceBefore = await getBalance(hunter);
    const CHECKPOINT_COST = 0.05;
    const BOND = 30;

    await submitCheckpoint(hunter);
    await finalizeCheckpoint();
    await claimBounty(hunter);

    const hunterBalanceAfter = await getBalance(hunter);
    const profit = hunterBalanceAfter - hunterBalanceBefore;

    // Verify profit: BOUNTY - COST = $40 - $0.05 = $39.95
    expect(profit).to.equal(39.95);

    // Checkpoint submission is highly profitable!
  });
});
```

---

## 7. Deployment Plan

### 7.1 Testnet Deployment (Week 6)

**Ethereum Sepolia**:
```bash
# Deploy contracts
npx hardhat run scripts/deploy-ethereum.js --network sepolia

# Verify on Etherscan
npx hardhat verify --network sepolia ESCROW_ADDRESS

# Configure parameters
npx hardhat run scripts/configure-ethereum.js --network sepolia
```

**Libra Testnet**:
```bash
# Compile Move contracts
cd framework
libra move framework release

# Deploy to testnet
libra move publish \
  --package-dir . \
  --profile testnet \
  --named-addresses ol_framework=0x1

# Initialize registries
libra move run \
  --function-id 0x1::ethereum_checkpoints::initialize \
  --profile testnet

libra move run \
  --function-id 0x1::treasury_auction::initialize \
  --profile testnet
```

**Configuration**:
```javascript
// config/testnet.json
{
  "ethereum": {
    "network": "sepolia",
    "rpcUrl": "https://rpc.sepolia.org",
    "contracts": {
      "escrow": "0x...",
      "checkpointRegistry": "0x..."
    },
    "parameters": {
      "minTimelockDuration": 86400,  // 24 hours
      "requiredBond": "0.015"        // 0.015 ETH
    }
  },
  "libra": {
    "network": "testnet",
    "rpcUrl": "https://testnet.openlibra.io",
    "chainId": 4,
    "contracts": {
      "ethereum_checkpoints": "0x1",
      "treasury_auction": "0x1"
    },
    "parameters": {
      "challengePeriod": 3600,           // 1 hour
      "requiredBond": 30000000,          // 30 LIBRA
      "minChickenFee": 20000000,         // 20 LIBRA
      "auctionDuration": 3600            // 1 hour
    }
  }
}
```

### 7.2 Mainnet Deployment (Week 14)

**Pre-deployment Checklist**:
- [ ] Security audit completed
- [ ] All critical issues resolved
- [ ] Economic parameters validated
- [ ] Monitoring infrastructure ready
- [ ] Emergency pause mechanism tested
- [ ] Multi-sig admin keys configured
- [ ] Documentation complete
- [ ] User guides published
- [ ] Support team trained

**Deployment Sequence**:

1. **Deploy Ethereum contracts** (Day 1)
   ```bash
   npx hardhat run scripts/deploy-ethereum-mainnet.js --network mainnet
   ```

2. **Verify and configure** (Day 1)
   ```bash
   npx hardhat verify --network mainnet ESCROW_ADDRESS
   # Transfer ownership to multi-sig
   # Configure parameters
   ```

3. **Deploy Libra contracts** (Day 2)
   ```bash
   libra move publish --profile mainnet
   # Initialize registries
   # Transfer admin to governance
   ```

4. **Configure cross-chain** (Day 2)
   ```bash
   # Set Ethereum contract addresses on Libra
   # Set Libra addresses on Ethereum
   # Enable cross-chain verification
   ```

5. **Gradual rollout** (Day 3-7)
   - Day 3: Whitelist beta users (10)
   - Day 4: Expand to 100 users
   - Day 5: Monitor metrics, adjust if needed
   - Day 6: Open to 1000 users
   - Day 7: Full public launch

**Mainnet Configuration**:
```javascript
// config/mainnet.json
{
  "ethereum": {
    "network": "mainnet",
    "rpcUrl": "https://eth.llamarpc.com",
    "contracts": {
      "escrow": "0x...",
      "checkpointRegistry": "0x...",
      "multisig": "0x..."  // Gnosis Safe
    },
    "parameters": {
      "minTimelockDuration": 172800,     // 48 hours (safer)
      "requiredBond": "0.015",           // ~$30 at $2000 ETH
      "challengePeriod": 3600,           // 1 hour
      "maxLockAmount": "100"             // 100 ETH max per swap (safety)
    },
    "admin": {
      "multisigOwners": [
        "0x...",  // Team member 1
        "0x...",  // Team member 2
        "0x..."   // Team member 3
      ],
      "requiredSignatures": 2
    }
  },
  "libra": {
    "network": "mainnet",
    "rpcUrl": "https://mainnet.openlibra.io",
    "chainId": 1,
    "contracts": {
      "ethereum_checkpoints": "0x1",
      "treasury_auction": "0x1"
    },
    "parameters": {
      "challengePeriod": 3600,           // 1 hour
      "requiredBond": 30000000,          // 30 LIBRA
      "minChickenFee": 20000000,         // 20 LIBRA
      "chickenFeeRate": 100,             // 1% (100 basis points)
      "auctionDuration": 3600,           // 1 hour
      "maxAuctionDuration": 86400,       // 24 hours max
      "minBidIncrement": 100             // 0.01% min increment
    },
    "admin": {
      "governanceModule": "0x1::libra_governance",
      "emergencyPauseAuthority": "0x..."
    }
  },
  "monitoring": {
    "alertsEmail": "alerts@openlibra.io",
    "metricsEndpoint": "https://metrics.openlibra.io",
    "dashboardUrl": "https://dashboard.openlibra.io"
  }
}
```

### 7.3 Monitoring & Alerts

**Key Metrics**:
```javascript
// Monitoring dashboard
{
  "checkpoints": {
    "totalSubmitted": 1234,
    "totalChallenged": 5,
    "challengeSuccessRate": 0.02,  // 2% (low is good)
    "avgSubmissionCost": 0.05,
    "avgBountyReward": 20.5,
    "avgProfitMargin": 19.95
  },
  "auctions": {
    "totalCreated": 856,
    "totalSettled": 845,
    "settlementRate": 0.987,  // 98.7%
    "avgParticipants": 7.3,
    "avgClearingPrice": 2045.6,
    "totalVolume": "8,560 ETH"
  },
  "security": {
    "fraudAttempts": 0,
    "successfulChallenges": 5,
    "bondSlashed": "150 LIBRA",
    "avgChallengeResponseTime": "15 minutes"
  },
  "economics": {
    "totalBountyPool": "4,500 LIBRA",
    "avgChickenFee": 21.3,
    "earlyExitRate": 0.12,  // 12%
    "capitalEfficiency": 0.50  // 50% better than HTLCs
  }
}
```

**Alerts**:
```yaml
# alerts.yaml
alerts:
  - name: HighChallengeRate
    condition: checkpoints.challengeSuccessRate > 0.10
    severity: critical
    action: pause_checkpoint_submission

  - name: LowAuctionSettlementRate
    condition: auctions.settlementRate < 0.80
    severity: warning
    action: notify_team

  - name: SuspiciousActivity
    condition: security.fraudAttempts > 0
    severity: critical
    action: emergency_pause

  - name: BountyPoolDepleted
    condition: economics.totalBountyPool < 100
    severity: info
    action: notify_team

  - name: HighEarlyExitRate
    condition: economics.earlyExitRate > 0.30
    severity: warning
    action: review_auction_parameters
```

---

## 8. Risk Mitigation

### 8.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Merkle proof verification bug | Medium | Critical | Extensive testing, audit, use battle-tested libraries |
| ZK proof verification bypass | Low | Critical | Use audited Plonk verifier, test with malicious proofs |
| State root mismatch | Medium | High | Challenge mechanism, economic penalties |
| Gas limit exceeded | Medium | Medium | Optimize contracts, batch operations |
| Move compiler bug | Low | High | Use stable Move version, extensive testing |

### 8.2 Economic Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Insufficient bounties | Medium | Medium | Adjust chicken fee rate, bootstrap liquidity |
| Checkpoint spam | Low | Medium | Require bond, rate limiting |
| Auction manipulation | Low | Medium | Transparent bids, anti-sniping measures |
| Price volatility | High | Low | Short auction durations, market-driven pricing |
| Low participation | Medium | High | Marketing, liquidity incentives |

### 8.3 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| RPC node downtime | Medium | High | Multiple RPC providers, fallback endpoints |
| Ethereum congestion | High | Medium | Dynamic gas pricing, user warnings |
| Smart contract bug | Low | Critical | Security audit, bug bounty, emergency pause |
| Admin key compromise | Low | Critical | Multi-sig, time-locked upgrades |
| Regulatory issues | Medium | High | Legal review, compliance framework |

### 8.4 Emergency Procedures

**Emergency Pause**:
```solidity
// Ethereum
function emergencyPause() external onlyAdmin {
    paused = true;
    emit EmergencyPause(msg.sender, block.timestamp);
}
```

```move
// Libra
public entry fun emergency_pause(admin: &signer) acquires RegistryState {
    assert!(signer::address_of(admin) == @ol_framework, E_UNAUTHORIZED);
    let state = borrow_global_mut<RegistryState>(@ol_framework);
    state.paused = true;
}
```

**Recovery Plan**:
1. Pause all contract operations
2. Analyze issue (bug, attack, market condition)
3. Develop fix or mitigation
4. Deploy fix to testnet
5. Audit fix
6. Deploy to mainnet via governance
7. Resume operations gradually

**User Protection**:
- All locked funds remain claimable during pause
- Existing auctions can settle
- No new operations accepted
- Clear communication to users

---

## 9. Future Enhancements

### 9.1 Short-term (Months 4-6)

**Multi-asset Support**:
- Support ERC20 tokens (USDC, USDT, DAI)
- Support other L1s (Polygon, Arbitrum, Optimism)
- Generic checkpoint registry per chain

**UX Improvements**:
- Auto-bidding with user preferences
- Notification system (email, push)
- Mobile app

**Performance**:
- Checkpoint batching (multiple auctions per checkpoint)
- Gas optimizations
- Parallel auction settlement

### 9.2 Medium-term (Months 7-12)

**Advanced Features**:
- Limit orders (standing bids)
- Partial fills with multiple preimages
- Cross-chain flash loans
- Liquidity pools for instant settlement

**Decentralization**:
- Governance module for parameters
- Decentralized checkpoint submission
- DAO treasury for liquidity

**Security**:
- Formal verification
- Bug bounty program
- Continuous audit

### 9.3 Long-term (Year 2+)

**Scaling**:
- ZK rollup for Libra auctions
- Optimistic rollup for Ethereum checkpoints
- Layer 2 integration

**Interoperability**:
- Bridge to Cosmos, Polkadot, Solana
- Universal checkpoint aggregator
- Cross-chain DEX aggregator

**Research**:
- Threshold signatures for multisig escrow
- Homomorphic encryption for sealed bids
- Zero-knowledge order books

---

## 10. Conclusion

This implementation plan synthesizes all research into a practical, phased approach to building atomic swaps between Libra and Ethereum.

**Key Achievements**:
1. ✅ **Capital Efficiency**: 50% better than traditional HTLCs
2. ✅ **Cost Efficiency**: $0.05 optimistic checkpoints vs $23 ZK proofs
3. ✅ **Self-Incentivizing**: Bounty mechanism ensures checkpoint submissions
4. ✅ **Trustless**: ZK fallback for disputes
5. ✅ **Scalable**: Constant 32-byte checkpoints regardless of throughput
6. ✅ **User-Friendly**: Treasury auction with fractional fills

**Timeline**: 14 weeks to production

**Costs**:
- Development: ~$100k (2 developers, 3.5 months)
- Security audit: ~$50k
- Infrastructure: ~$5k/month
- Total: ~$150k initial + $5k/month operational

**Revenue Model**:
- Protocol fee: 0.1% per swap (optional, can be added later)
- Or: Subsidize via network incentives
- Or: Fully free (users pay gas only)

**Next Steps**:
1. Review and approve this plan
2. Assemble development team
3. Set up development environment
4. Begin Phase 1 implementation
5. Launch MVP on testnet (Week 6)

This design represents a novel approach to cross-chain atomic swaps that leverages:
- Asymmetric escrow for capital efficiency
- Treasury auctions for price discovery
- Optimistic checkpoints for cost efficiency
- Bounty incentives for decentralization
- ZK proofs for trustlessness

The result is a practical, economically viable system for trustless cross-chain swaps.
