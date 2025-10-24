# Practical Checkpoint-Based Bounty Sync (No Light Client)

## The Problem with Light Clients

**Light client approach requires:**
- Processing validator signatures for every block update
- For high-throughput chains (hundreds of thousands tx/min): IMPRACTICAL
- Cost: $30+ per update
- Complexity: Very high

**We need a better approach.**

## The Solution: State Root Checkpoints

### Core Insight (from research-atomic-swap.md)

**You don't need to process every transaction. You only need:**
1. **State root** at block N (32 bytes)
2. **Merkle proof** that your data is in that state
3. **Proof of state transition** (block headers, not full state)

**This works for ANY throughput** - doesn't matter if chain does 10 tx/sec or 1 million tx/sec.

## 1. Checkpoint Architecture

### 1.1 What's in a Checkpoint?

```solidity
struct StateCheckpoint {
    bytes32 libraStateRoot;      // Libra state root at block N (32 bytes)
    uint256 libraBlockHeight;    // Which Libra block
    bytes32 prevCheckpointHash;  // Forms checkpoint chain
    uint256 ethBlockNumber;      // When submitted to Ethereum
}
```

**That's it! Just 128 bytes total.**

No need to store:
- ❌ All transactions
- ❌ All validator signatures (hundreds of them)
- ❌ Full block data

Just the **state root** - a cryptographic commitment to the entire chain state.

### 1.2 How Checkpoints Get Submitted

**On-demand by users who need them:**

```
Alice wants early refund:
1. Check latest checkpoint on Ethereum
2. Is it recent enough (< 1 hour)?
   - Yes → Use it
   - No → Submit new checkpoint first

Checkpoint submission:
1. Get Libra state root at block N
2. Get validator signatures on that block
3. Submit to Ethereum:
   submitCheckpoint(
       libraStateRoot,
       libraBlockHeight,
       validatorSignatures,  // Proof state root is valid
       prevCheckpointHash
   )
4. Cost: ~$20-30 (one-time, amortized across users)
```

### 1.3 Why This Scales

**High-throughput doesn't matter:**
- Libra processes 500,000 tx/min → State root at block N is still 32 bytes
- Libra processes 10 tx/min → State root at block N is still 32 bytes

**State root is constant size regardless of throughput.**

## 2. Bounty-Driven Checkpoint Sync

### 2.1 The Mechanism

**Early exiter pays for checkpoint maintenance:**

```
Alice wants early exit:

Step 1: Pay chicken fee ($20)
   → Goes to bounty pool
   → Auction marked EXITING

Step 2: Anyone can claim bounty by:
   → Submitting valid checkpoint to Ethereum
   → Proving Libra state contains Alice's exit
   → Proving accumulators synced

Checkpoint prover (Bob):
1. Submits Libra state root to Ethereum (~$20)
2. Proves Alice's auction exit is in that state (Merkle proof)
3. Claims $20 bounty
4. Net cost: $0 (breaks even)
```

### 2.2 Why This Works Economically

**Chicken fee covers checkpoint cost:**
- Checkpoint submission: $20
- Bounty: $20
- Prover breaks even (or small profit if gas < $20)

**No continuous monitoring needed:**
- Checkpoints only submitted when bounties exist
- Self-correcting (profit motive)
- No infrastructure required

## 3. Implementation

### 3.1 Ethereum Side: Checkpoint Registry

```solidity
contract CheckpointRegistry {
    struct StateCheckpoint {
        bytes32 libraStateRoot;
        uint256 libraBlockHeight;
        bytes32 prevCheckpointHash;
        uint256 submittedAt;
    }

    bytes32 public latestCheckpointHash;
    mapping(bytes32 => StateCheckpoint) public checkpoints;

    /// Submit new Libra checkpoint
    function submitCheckpoint(
        bytes32 libraStateRoot,
        uint256 libraBlockHeight,
        bytes[] calldata validatorSignatures,  // BFT quorum sigs
        uint256[] calldata validatorIndices,
        bytes32 prevCheckpointHash
    ) external returns (bytes32 checkpointHash) {
        // 1. Verify this builds on previous checkpoint
        if (prevCheckpointHash != bytes32(0)) {
            StateCheckpoint storage prev = checkpoints[prevCheckpointHash];
            require(prev.libraBlockHeight > 0, "Invalid prev checkpoint");
            require(libraBlockHeight > prev.libraBlockHeight, "Not advancing");
        }

        // 2. Verify validator signatures on state root
        //    (BFT consensus: need >2/3 voting power)
        uint256 votingPower = verifyValidatorSignatures(
            libraStateRoot,
            libraBlockHeight,
            validatorSignatures,
            validatorIndices
        );

        require(votingPower >= QUORUM_THRESHOLD, "Insufficient signatures");

        // 3. Store checkpoint
        checkpointHash = keccak256(abi.encodePacked(
            libraStateRoot,
            libraBlockHeight,
            prevCheckpointHash,
            block.number
        ));

        checkpoints[checkpointHash] = StateCheckpoint({
            libraStateRoot: libraStateRoot,
            libraBlockHeight: libraBlockHeight,
            prevCheckpointHash: prevCheckpointHash,
            submittedAt: block.timestamp
        });

        latestCheckpointHash = checkpointHash;

        emit CheckpointSubmitted(checkpointHash, libraBlockHeight, libraStateRoot);

        return checkpointHash;
    }

    /// Verify BFT validator signatures
    function verifyValidatorSignatures(
        bytes32 stateRoot,
        uint256 blockHeight,
        bytes[] calldata signatures,
        uint256[] calldata indices
    ) internal view returns (uint256 totalVotingPower) {
        bytes32 message = keccak256(abi.encodePacked(stateRoot, blockHeight));

        for (uint i = 0; i < signatures.length; i++) {
            address validator = validatorSet[indices[i]];
            uint256 votingPower = validatorVotingPower[validator];

            // Verify Ed25519 signature
            require(
                verifyEd25519(message, signatures[i], validatorPubkeys[validator]),
                "Invalid signature"
            );

            totalVotingPower += votingPower;
        }
    }
}
```

### 3.2 Libra Side: Mirror Checkpoint Registry

```move
module ol_framework::checkpoint_registry {
    struct StateCheckpoint has store, copy, drop {
        eth_state_root: vector<u8>,
        eth_block_number: u64,
        prev_checkpoint_hash: vector<u8>,
        submitted_at: u64,
    }

    struct CheckpointRegistry has key {
        latest_checkpoint_hash: vector<u8>,
        checkpoints: Table<vector<u8>, StateCheckpoint>,
    }

    /// Submit new Ethereum checkpoint
    public entry fun submit_checkpoint(
        submitter: &signer,
        eth_state_root: vector<u8>,
        eth_block_number: u64,
        sync_committee_signature: vector<u8>,  // Aggregated BLS
        sync_committee_bits: vector<u8>,       // Which validators signed
        prev_checkpoint_hash: vector<u8>,
    ) acquires CheckpointRegistry {
        // 1. Verify builds on previous checkpoint
        if (vector::length(&prev_checkpoint_hash) > 0) {
            let registry = borrow_global<CheckpointRegistry>(@ol_framework);
            let prev = table::borrow(&registry.checkpoints, prev_checkpoint_hash);
            assert!(eth_block_number > prev.eth_block_number, E_NOT_ADVANCING);
        };

        // 2. Verify sync committee signature
        //    (Ethereum PoS: need >2/3 of 512 validators)
        let participants = verify_eth_sync_committee(
            eth_state_root,
            eth_block_number,
            sync_committee_signature,
            sync_committee_bits
        );

        assert!(participants >= 342, E_INSUFFICIENT_PARTICIPANTS); // 2/3 of 512

        // 3. Store checkpoint
        let checkpoint_hash = hash::keccak256(&vector::append_all(vector[
            eth_state_root,
            to_bytes(eth_block_number),
            prev_checkpoint_hash,
        ]));

        let checkpoint = StateCheckpoint {
            eth_state_root,
            eth_block_number,
            prev_checkpoint_hash,
            submitted_at: timestamp::now_seconds(),
        };

        let registry = borrow_global_mut<CheckpointRegistry>(@ol_framework);
        table::upsert(&mut registry.checkpoints, checkpoint_hash, checkpoint);
        registry.latest_checkpoint_hash = checkpoint_hash;
    }
}
```

### 3.3 Bounty Claim with Checkpoint Proof

```move
module ol_framework::bounty_sync {
    /// Claim bounty by proving sync (using checkpoints)
    public entry fun claim_sync_bounty<HomeCoin>(
        claimer: &signer,
        bounty_id: u64,

        // Ethereum checkpoint proof
        eth_checkpoint_hash: vector<u8>,
        eth_accumulator_proof: vector<vector<u8>>,  // Merkle proof

        // Local verification
        libra_accumulator_root: vector<u8>,
    ) acquires BountyRegistry {
        let bounty = get_bounty(bounty_id);
        assert!(!bounty.claimed, E_ALREADY_CLAIMED);

        // 1. Get verified Ethereum state root from checkpoint
        let checkpoint = checkpoint_registry::get_checkpoint(eth_checkpoint_hash);

        // 2. Verify Ethereum accumulator is in verified state
        //    (Merkle proof: accumulator is in Ethereum state tree)
        assert!(
            verify_merkle_proof(
                eth_accumulator_root,
                checkpoint.eth_state_root,
                eth_accumulator_proof,
                ETHEREUM_ACCUMULATOR_STORAGE_SLOT
            ),
            E_INVALID_ETH_PROOF
        );

        // 3. Get Libra accumulator (local, no proof needed)
        let libra_accumulator_root_actual = auction_accumulator::get_root();
        assert!(
            libra_accumulator_root == libra_accumulator_root_actual,
            E_INVALID_LIBRA_ROOT
        );

        // 4. Verify accumulators match (both chains synced)
        assert!(
            eth_accumulator_root == libra_accumulator_root,
            E_ACCUMULATORS_MISMATCH
        );

        // 5. Verify exit is in accumulator
        assert!(
            accumulator_contains_exit(bounty.auction_id, libra_accumulator_root),
            E_EXIT_NOT_IN_ACCUMULATOR
        );

        // All verified! Pay bounty
        bounty.claimed = true;
        bounty.claimer = signer::address_of(claimer);

        coin::transfer<HomeCoin>(
            @ol_framework,
            signer::address_of(claimer),
            bounty.bounty_amount
        );
    }
}
```

## 4. Complete Flow with Checkpoints

### 4.1 Normal Flow (No Early Exit)

```
Hour 0: Alice locks 10 ETH, creates auction
Hour 2: Auction settles normally
Hour 3: Winners withdraw

No checkpoints needed!
No bounties created!
Cost: Standard gas only
```

### 4.2 Early Exit Flow

```
Hour 0: Alice locks 10 ETH (timelock: 24h)
Hour 2: Auction fails (insufficient bids)
Hour 3: Alice wants early refund

Alice's actions:
1. Call request_early_exit() on Libra
   Cost: $0.01 + $20 chicken fee
   Result: Bounty created

2. Wait for someone to claim bounty

Bob sees bounty:
1. Check if Ethereum has recent Libra checkpoint
   - Latest checkpoint: 2 hours old (STALE)
   - Bob needs to submit new checkpoint

2. Get Libra state root at current block
   - Query Libra node for state root
   - Get validator signatures (BFT quorum cert)

3. Submit checkpoint to Ethereum
   Call: submitCheckpoint(
       libraStateRoot,
       libraBlockHeight,
       validatorSignatures,
       prevCheckpointHash
   )
   Cost: ~$20 gas

4. Prove accumulators synced and claim bounty
   Call: claim_sync_bounty(
       bounty_id,
       eth_checkpoint_hash,  // Checkpoint Bob just submitted
       accumulator_proof     // Merkle proof
   )
   Cost: ~$0.02 on Libra
   Reward: $20

Bob's economics:
- Cost: $20 (checkpoint) + $0.02 (claim) = $20.02
- Reward: $20
- Net: -$0.02 (breaks even!)

Alice completes exit:
1. Submit early refund request to Ethereum
   - Reference checkpoint
   - Prove auction failed (Merkle proof against Libra state)
   Cost: ~$5

Alice's total:
- Chicken fee: $20
- Ethereum tx: ~$5
- Total: $25 for instant refund vs. waiting 21h
```

## 5. Checkpoint Economics

### 5.1 Cost Breakdown

**Checkpoint submission:**
```
Validator signature verification: ~15k gas per signature
Quorum: ~100 signatures needed (2/3 of 150 validators)
Total: ~1.5M gas
At 20 gwei, 2000 ETH/USD: ~$60

Wait, that's too expensive!
```

### 5.2 Optimization: Signature Aggregation

**Problem:** Verifying 100 Ed25519 signatures costs $60

**Solution:** BLS signature aggregation (if Libra uses BLS)

```
Instead of 100 signatures:
1. Validators sign with BLS keys
2. Aggregate into single signature
3. Verify single aggregated signature
4. Cost: ~50k gas (~$5)
```

**If Libra uses Ed25519 (not BLS):**

**Option A: Checkpoint batching**
```
Instead of checkpoint per block:
- Checkpoint every 100 blocks
- Amortize cost across time
- Still provides recent state (< 1 min old)
```

**Option B: ZK proof of signatures**
```
Generate ZK proof: "100 validators signed this state root"
Verify ZK proof on Ethereum: ~300k gas (~$15)
Still cheaper than verifying 100 signatures individually
```

**Option C: Optimistic checkpoints with challenge**
```
Submit checkpoint optimistically (no sigs):
- Post bond ($30)
- Challenge period (1 hour)
- If challenged, must prove with signatures

Cost if unchallenged: ~$3
Cost if challenged: ~$60 (but challenger pays)
```

### 5.3 Recommended Hybrid

**Use optimistic checkpoints:**

```
Checkpoint submission:
1. Submit state root + post bond
   Cost: $3
   Bond: $30

2. Challenge period: 1 hour

3. If unchallenged → checkpoint accepted
   Submitter gets bond back
   Total cost: $3

4. If challenged:
   Submitter must prove with validator signatures
   Cost: $60 (but only if fraud)
   Honest submitter gets bond back + challenger's bond
   Fraudster loses bond

Result: Honest checkpoint costs $3, fraud costs $90
```

**Bounty prover workflow (optimistic):**
```
1. See $20 bounty
2. Submit optimistic checkpoint ($3 + $30 bond)
3. Wait 1 hour (no challenge)
4. Get bond back + claim bounty
5. Net: $20 bounty - $3 gas = $17 profit ✓
```

## 6. Scaling Properties

### 6.1 Throughput Independence

**Key insight: State root size doesn't depend on throughput**

```
Chain A: 10 tx/sec
- State root at block N: 32 bytes
- Checkpoint cost: $3

Chain B: 1,000,000 tx/sec
- State root at block N: 32 bytes
- Checkpoint cost: $3

Same cost regardless of throughput!
```

### 6.2 Checkpoint Frequency

**On-demand submission:**
```
High traffic (many early exits):
- Frequent bounties
- Frequent checkpoints (e.g., every 10 min)
- Cost amortized across many bounties

Low traffic (rare early exits):
- Rare bounties
- Rare checkpoints (e.g., once per day)
- Still works! No continuous monitoring needed
```

### 6.3 Checkpoint Reuse

**Multiple bounties can share one checkpoint:**

```
Scenario:
- Bounty 1: Alice exits ($20)
- Bounty 2: Bob exits ($20)
- Bounty 3: Carol exits ($20)
- Total pool: $60

Prover strategy:
1. Submit one checkpoint ($3)
2. Claim all 3 bounties ($60)
3. Net: $60 - $3 = $57 profit ✓

This incentivizes batching!
```

## 7. Security Analysis

### 7.1 Attack Vectors

**Attack 1: Submit fake checkpoint**

```
Attacker submits incorrect Libra state root

Defense (optimistic):
1. Honest actor challenges within 1 hour
2. Challenger proves actual state root (with validator sigs)
3. Attacker loses $30 bond
4. Challenger gets bond

Result: Attack costs $33 (bond + gas), gain $0
```

**Attack 2: Claim bounty with stale checkpoint**

```
Attacker uses 3-hour-old checkpoint to claim bounty

Defense:
1. Contract checks checkpoint age
2. require(checkpoint.submittedAt + 3600 > now, "Stale")
3. Transaction reverts

Result: Attack fails, costs gas only
```

**Attack 3: No one challenges bad checkpoint**

```
Bad checkpoint submitted, no one notices

Defense:
1. Anyone can challenge (permissionless)
2. Challenger earns bond ($30)
3. Economic incentive to challenge fraud

Result: Single honest actor sufficient
```

### 7.2 Trust Assumptions

**What we trust:**
- At least one honest challenger exists (for optimistic checkpoints)
- BFT consensus on Libra (>2/3 validators honest)
- PoS consensus on Ethereum (sync committee honest)

**What we don't trust:**
- Checkpoint submitters (they post bonds)
- Specific validators (we verify quorum)
- Oracles or relayers (permissionless participation)

### 7.3 Liveness

**If no one submits checkpoints:**
- New bounties accumulate
- Bounty pool grows larger
- Eventually attractive enough for someone
- Worst case: Exiter can submit checkpoint themselves

**If checkpoints stop for months:**
- Protocol still works!
- Next exiter submits checkpoint
- Continues from last valid checkpoint
- No continuous infrastructure required

## 8. Comparison Summary

| Approach | Checkpoint Cost | Throughput Limit | Trust | Complexity |
|----------|----------------|------------------|-------|------------|
| **Full light client** | $30-60 | IMPRACTICAL | None | Very High |
| **State root checkpoints** | $3-20 | **No limit** | Quorum | Medium |
| **Optimistic checkpoints** | **$3** | **No limit** | Single honest actor | **Low** |

## 9. Implementation Roadmap

### Phase 1: Optimistic Checkpoints (Weeks 1-3)
```
✓ Checkpoint registry contracts
✓ Optimistic submission with bonds
✓ Challenge mechanism
✓ Basic Merkle proof verification
```

### Phase 2: Bounty Integration (Weeks 4-5)
```
✓ Bounty claiming with checkpoint proofs
✓ Accumulator verification
✓ Early exit flow
```

### Phase 3: Optimization (Weeks 6-7)
```
✓ Signature aggregation (if possible)
✓ Checkpoint batching
✓ Gas optimization
```

### Phase 4: Testing & Launch (Week 8)
```
✓ E2E tests
✓ Economic simulations
✓ Security audit
✓ Mainnet deployment
```

## 10. Final Assessment

### What This Achieves

**✓ Scales to any throughput** (state roots are constant size)
**✓ No continuous infrastructure** (on-demand checkpoints)
**✓ Self-incentivizing** (bounties pay for checkpoints)
**✓ Optimistic execution** ($3 cost, not $60)
**✓ Challenge security** (fraud deterred by bonds)
**✓ Permissionless** (anyone can submit/challenge)

### Compared to Light Client Approach

**Light client problems:**
- Processes every block update
- Impractical for high-throughput chains
- Cost: $30-60 per update
- Continuous operation required

**Checkpoint approach:**
- Only state roots (32 bytes)
- Throughput-independent
- Cost: $3 per checkpoint (optimistic)
- On-demand only

### The Key Innovation

**State roots + optimistic verification:**
1. State root commits to entire chain state (32 bytes)
2. Merkle proofs verify specific data is in state
3. Optimistic submission with challenge period
4. Bonds ensure honest behavior

**Result:** Trustless, scalable, practical cross-chain verification without light clients.

This is the approach the research document already identified, now combined with bounty-driven incentives for a self-sustaining system.
