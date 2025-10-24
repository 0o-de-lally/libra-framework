# Trustless Light Client Synchronization with Bounty Incentives

## The Trust Problem

**Current bounty design assumes:**
- Someone claims "Libra accumulator root is 0xabc123"
- Someone claims "Ethereum accumulator root is 0xabc123"
- If they match → bounty paid

**But who verifies these claims are true?**

Without trustless verification, the prover could lie:
```
Actual Libra root:    0xabc123...
Actual Ethereum root: 0xdef456...
Prover claims both:   0x999999... (fake)
→ Claims bounty fraudulently
```

**Solution: Light client verification with cryptographic proofs**

## 1. Trustless Verification Architecture

### 1.1 Core Concept

Each chain runs a **light client** of the other chain:
- Ethereum contract verifies Libra consensus
- Libra contract verifies Ethereum consensus
- No trust in relayers/provers (cryptographically verified)

**Light client components:**
1. **Block header relay** (minimal data, just headers)
2. **Consensus verification** (validator signatures)
3. **State proof verification** (Merkle proofs against verified headers)

### 1.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Ethereum Chain                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │  Libra Light Client Contract                      │ │
│  │  - Stores Libra block headers                     │ │
│  │  - Verifies BFT signatures                        │ │
│  │  - Maintains validator set                        │ │
│  │  - Verifies state proofs                          │ │
│  └───────────────────────────────────────────────────┘ │
│                       ↑                                 │
│                       │ Block headers + signatures      │
│                       │                                 │
└───────────────────────┼─────────────────────────────────┘
                        │
                        │ Sync Prover (permissionless)
                        │ - Fetches Libra headers
                        │ - Submits to Ethereum
                        │ - Earns bounty
                        │
┌───────────────────────┼─────────────────────────────────┐
│                       ↓                                 │
│  Libra Chain                                            │
│  ┌───────────────────────────────────────────────────┐ │
│  │  Ethereum Light Client Contract                   │ │
│  │  - Stores Ethereum block headers                  │ │
│  │  - Verifies PoS signatures (sync committee)       │ │
│  │  - Verifies state proofs                          │ │
│  └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 2. Ethereum → Libra Verification

### 2.1 Ethereum Consensus (Proof of Stake)

**Ethereum post-merge uses:**
- Beacon chain (consensus layer)
- Sync committees (512 validators per period)
- BLS signatures (aggregatable)

**Light client approach:**
```
1. Store sync committee pubkeys (~512 validators)
2. Verify sync committee signatures on block headers
3. Accept headers with >2/3 signatures
4. Update sync committee periodically (~27 hours)
```

### 2.2 Libra Light Client Contract (Move)

```move
module ol_framework::ethereum_light_client {
    use std::vector;
    use aptos_framework::timestamp;

    /// Ethereum beacon chain header (simplified)
    struct BeaconHeader has store, drop, copy {
        slot: u64,
        proposer_index: u64,
        parent_root: vector<u8>,
        state_root: vector<u8>,      // THIS is what we need!
        body_root: vector<u8>,
    }

    /// Sync committee (512 validators)
    struct SyncCommittee has store {
        pubkeys: vector<vector<u8>>,  // 512 BLS pubkeys
        aggregate_pubkey: vector<u8>,
        period: u64,
    }

    /// Light client state
    struct LightClient has key {
        latest_header: BeaconHeader,
        current_sync_committee: SyncCommittee,
        next_sync_committee: SyncCommittee,
        finalized_headers: Table<u64, BeaconHeader>,  // slot -> header
    }

    /// Update light client with new Ethereum header
    public entry fun update_header(
        caller: &signer,
        header: BeaconHeader,
        sync_committee_bits: vector<u8>,    // Bitfield: which validators signed
        sync_committee_signature: vector<u8>, // Aggregated BLS signature
        execution_state_root: vector<u8>,   // Execution layer state root
        execution_state_proof: vector<vector<u8>>, // Merkle proof
    ) acquires LightClient {
        let lc = borrow_global_mut<LightClient>(@ol_framework);

        // 1. Verify header is newer than stored header
        assert!(header.slot > lc.latest_header.slot, E_HEADER_TOO_OLD);

        // 2. Verify sync committee signature
        let signing_root = compute_signing_root(header);
        assert!(
            verify_bls_signature(
                sync_committee_signature,
                signing_root,
                lc.current_sync_committee.pubkeys,
                sync_committee_bits
            ),
            E_INVALID_SIGNATURE
        );

        // 3. Verify >2/3 validators signed
        let participants = count_bits(sync_committee_bits);
        assert!(participants >= 342, E_INSUFFICIENT_PARTICIPANTS); // 2/3 of 512

        // 4. Verify execution state root is in beacon state
        assert!(
            verify_execution_state_proof(
                execution_state_root,
                header.state_root,
                execution_state_proof
            ),
            E_INVALID_STATE_PROOF
        );

        // 5. Store header
        lc.latest_header = header;
        table::add(&mut lc.finalized_headers, header.slot, header);

        // Now we cryptographically know Ethereum's state root!
    }

    /// Get verified Ethereum state root at slot
    public fun get_ethereum_state_root(slot: u64): vector<u8> acquires LightClient {
        let lc = borrow_global<LightClient>(@ol_framework);
        let header = table::borrow(&lc.finalized_headers, slot);
        header.state_root
    }

    /// Verify BLS signature (uses native crypto)
    fun verify_bls_signature(
        signature: vector<u8>,
        message: vector<u8>,
        pubkeys: vector<vector<u8>>,
        bits: vector<u8>,
    ): bool {
        // Aggregate pubkeys for validators who signed
        let aggregate_pubkey = aggregate_pubkeys_by_bits(pubkeys, bits);

        // Verify signature using BLS12-381
        bls12381::verify(signature, message, aggregate_pubkey)
    }

    /// Verify execution state root is in beacon state
    fun verify_execution_state_proof(
        execution_state_root: vector<u8>,
        beacon_state_root: vector<u8>,
        proof: vector<vector<u8>>,
    ): bool {
        // Merkle proof that execution_state_root is in beacon state
        verify_merkle_proof(
            execution_state_root,
            beacon_state_root,
            proof,
            EXECUTION_STATE_ROOT_INDEX  // Known index in beacon state
        )
    }
}
```

### 2.3 Proving Ethereum Accumulator to Libra

**Sync prover workflow:**
```rust
async fn prove_ethereum_accumulator_to_libra(&self) -> Result<()> {
    // 1. Get latest Ethereum beacon header
    let beacon_header = self.fetch_beacon_header().await?;

    // 2. Get sync committee signature on header
    let sync_aggregate = self.fetch_sync_aggregate(beacon_header.slot).await?;

    // 3. Get execution state root (where accumulator lives)
    let execution_state_root = self.fetch_execution_state_root().await?;

    // 4. Get proof that execution state is in beacon state
    let execution_proof = self.get_execution_state_proof(beacon_header).await?;

    // 5. Get proof that accumulator is in execution state
    let accumulator_storage_proof = self.get_accumulator_storage_proof().await?;

    // 6. Submit to Libra
    self.libra_client.execute_transaction(
        "ethereum_light_client::update_header",
        vec![
            beacon_header,
            sync_aggregate.sync_committee_bits,
            sync_aggregate.sync_committee_signature,
            execution_state_root,
            execution_proof,
        ]
    ).await?;

    // 7. Verify accumulator value
    self.libra_client.execute_transaction(
        "bounty_sync::verify_ethereum_accumulator",
        vec![
            ethereum_accumulator_root,
            accumulator_storage_proof,
            beacon_header.slot,
        ]
    ).await?;

    Ok(())
}
```

## 3. Libra → Ethereum Verification

### 3.1 Libra Consensus (BFT)

**Libra uses:**
- BFT consensus (like Aptos/Diem)
- Validator set with voting power
- Quorum signatures on blocks

**Light client approach:**
```
1. Store validator set (addresses + voting power)
2. Verify quorum signatures on block headers (>2/3 voting power)
3. Accept headers with valid quorum
4. Update validator set when epoch changes
```

### 3.2 Ethereum Light Client Contract (Solidity)

```solidity
contract LibraLightClient {
    struct BlockHeader {
        uint64 epoch;
        uint64 round;
        uint64 timestamp;
        bytes32 blockHash;
        bytes32 stateRoot;        // THIS is what we need!
        bytes32 previousBlockHash;
    }

    struct Validator {
        address account;
        uint256 votingPower;
        bytes publicKey;          // Ed25519 or BLS
    }

    struct ValidatorSet {
        Validator[] validators;
        uint256 totalVotingPower;
        uint64 epoch;
    }

    ValidatorSet public currentValidatorSet;
    mapping(bytes32 => BlockHeader) public finalizedBlocks;
    BlockHeader public latestBlock;

    /// Update light client with new Libra block
    function updateBlock(
        BlockHeader calldata header,
        bytes[] calldata signatures,     // Validator signatures
        uint256[] calldata signerIndices  // Which validators signed
    ) external {
        // 1. Verify block is newer
        require(header.round > latestBlock.round, "Block too old");

        // 2. Verify signatures from validators
        bytes32 signedHash = keccak256(abi.encode(header));
        uint256 votingPower = 0;

        for (uint i = 0; i < signatures.length; i++) {
            uint256 validatorIdx = signerIndices[i];
            Validator memory validator = currentValidatorSet.validators[validatorIdx];

            // Verify Ed25519 signature
            require(
                verifyEd25519(
                    signedHash,
                    signatures[i],
                    validator.publicKey
                ),
                "Invalid signature"
            );

            votingPower += validator.votingPower;
        }

        // 3. Verify >2/3 voting power signed
        require(
            votingPower * 3 > currentValidatorSet.totalVotingPower * 2,
            "Insufficient voting power"
        );

        // 4. Store block
        finalizedBlocks[header.blockHash] = header;
        latestBlock = header;

        // Now we cryptographically know Libra's state root!
    }

    /// Get verified Libra state root
    function getLibraStateRoot(bytes32 blockHash) external view returns (bytes32) {
        return finalizedBlocks[blockHash].stateRoot;
    }

    /// Verify Ed25519 signature (precompile or library)
    function verifyEd25519(
        bytes32 message,
        bytes memory signature,
        bytes memory publicKey
    ) internal view returns (bool) {
        // Use Ed25519 precompile or library
        // EIP-xxx for Ed25519 verification
        // Or use existing library like OpenZeppelin
        return ed25519Verify(message, signature, publicKey);
    }
}
```

### 3.3 Proving Libra Accumulator to Ethereum

```rust
async fn prove_libra_accumulator_to_ethereum(&self) -> Result<()> {
    // 1. Get latest Libra block with quorum cert
    let block_info = self.fetch_libra_block().await?;

    // 2. Get validator signatures on block
    let quorum_cert = self.fetch_quorum_cert(block_info.round).await?;

    // 3. Get proof that accumulator is in Libra state
    let accumulator_proof = self.get_libra_state_proof(
        "auction_accumulator::Accumulator",
        block_info.state_root
    ).await?;

    // 4. Submit to Ethereum
    let tx = self.ethereum_client.send_transaction(
        libra_light_client.updateBlock(
            block_info.header,
            quorum_cert.signatures,
            quorum_cert.signer_indices
        )
    ).await?;

    // 5. Verify accumulator value
    let tx2 = self.ethereum_client.send_transaction(
        bounty_sync.verifyLibraAccumulator(
            libra_accumulator_root,
            accumulator_proof,
            block_info.block_hash
        )
    ).await?;

    Ok(())
}
```

## 4. Complete Trustless Sync Flow

### 4.1 Bounty Claim with Cryptographic Proofs

**Updated Libra contract:**
```move
module ol_framework::bounty_sync {
    /// Claim bounty by proving accumulators synced (trustless)
    public entry fun claim_sync_bounty<HomeCoin>(
        claimer: &signer,
        bounty_id: u64,

        // Ethereum proof
        ethereum_block_slot: u64,           // Which Ethereum block
        ethereum_accumulator_root: vector<u8>,
        ethereum_accumulator_proof: vector<vector<u8>>, // Merkle proof in Ethereum state

        // Libra proof (local)
        libra_block_height: u64,
        libra_accumulator_root: vector<u8>,
    ) acquires BountyRegistry {
        let bounty_registry = borrow_global_mut<BountyRegistry>(@ol_framework);
        let bounty = table::borrow_mut(&mut bounty_registry.bounties, bounty_id);

        assert!(!bounty.claimed, E_ALREADY_CLAIMED);

        // 1. Get verified Ethereum state root from light client
        let ethereum_state_root = ethereum_light_client::get_ethereum_state_root(
            ethereum_block_slot
        );

        // 2. Verify Ethereum accumulator is in verified state
        assert!(
            verify_merkle_proof(
                ethereum_accumulator_root,
                ethereum_state_root,
                ethereum_accumulator_proof,
                ETHEREUM_ACCUMULATOR_STORAGE_SLOT
            ),
            E_INVALID_ETHEREUM_PROOF
        );

        // 3. Get Libra accumulator root (local, trustless)
        let libra_accumulator_root_actual = auction_accumulator::get_root();
        assert!(
            libra_accumulator_root == libra_accumulator_root_actual,
            E_INVALID_LIBRA_ROOT
        );

        // 4. Verify accumulators represent same state
        // (Could verify they contain same auctions, or just check equality)
        assert!(
            ethereum_accumulator_root == libra_accumulator_root,
            E_ACCUMULATORS_MISMATCH
        );

        // 5. Verify exit state is in accumulator
        assert!(
            accumulator_includes_exit(libra_accumulator_root, bounty.auction_id),
            E_EXIT_NOT_INCLUDED
        );

        // All proofs verified cryptographically!
        // Pay bounty
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

**Updated Ethereum contract:**
```solidity
contract MultiPartyHTLC {
    function requestEarlyRefund(
        bytes32 lockId,

        // Libra proof
        bytes32 libraBlockHash,              // Which Libra block
        bytes32 libraAccumulatorRoot,
        bytes calldata libraAccumulatorProof, // Merkle proof in Libra state

        // Exit proof
        bytes calldata auctionStateProof,     // Proves auction exited
        AuctionState calldata auctionState    // Auction data
    ) external {
        Lock storage lock = locks[lockId];
        require(msg.sender == lock.initiator, "Not initiator");

        // 1. Get verified Libra state root from light client
        bytes32 libraStateRoot = libraLightClient.getLibraStateRoot(libraBlockHash);

        // 2. Verify Libra accumulator is in verified state
        require(
            verifyMerkleProof(
                libraAccumulatorRoot,
                libraStateRoot,
                libraAccumulatorProof,
                LIBRA_ACCUMULATOR_STORAGE_PATH
            ),
            "Invalid Libra accumulator proof"
        );

        // 3. Verify auction state is in accumulator
        bytes32 auctionHash = keccak256(abi.encode(auctionState));
        require(
            verifyMerkleProof(
                auctionHash,
                libraAccumulatorRoot,
                auctionStateProof,
                auctionState.auctionId  // Leaf index
            ),
            "Invalid auction proof"
        );

        // 4. Verify auction actually exited/failed
        require(
            auctionState.status == EXITING || auctionState.status == FAILED,
            "Auction not exited"
        );

        // 5. Verify this auction matches this lock
        require(auctionState.hashLock == lock.hashLock, "Wrong auction");

        // All proofs verified cryptographically!
        // Allow early refund
        lock.refunded = true;
        lock.initiator.transfer(lock.totalAmount);
    }
}
```

### 4.2 Complete Trustless Flow

```
Hour 0:
- Alice locks 10 ETH on Ethereum
- Ethereum accumulator updates
- Alice creates auction on Libra
- Libra accumulator updates

Hour 3:
- Alice requests early exit
- Pays $10 chicken fee
- Bounty created

Sync Prover (Bob) sees opportunity:

Step 1: Update Ethereum light client on Libra
  → Submit Ethereum beacon header
  → Submit sync committee signature
  → Libra verifies BLS signatures (>2/3 validators)
  → Libra cryptographically knows Ethereum state root
  Cost: ~$0.05 on Libra

Step 2: Update Libra light client on Ethereum
  → Submit Libra block header
  → Submit validator signatures
  → Ethereum verifies Ed25519 signatures (>2/3 voting power)
  → Ethereum cryptographically knows Libra state root
  Cost: ~$15 on Ethereum

Step 3: Claim bounty on Libra
  → Prove Ethereum accumulator in verified Ethereum state
  → Prove Libra accumulator matches
  → Get $10 bounty
  Cost: ~$0.02 on Libra

Step 4: Alice gets early refund on Ethereum
  → Prove Libra accumulator in verified Libra state
  → Prove auction exited in accumulator
  → Get 10 ETH back
  Cost: ~$5 on Ethereum

Total costs:
- Bob: ~$15 (Ethereum light client update) + $0.07 (Libra) = $15.07
- Bob earns: $10 bounty
- Bob net: -$5.07 (LOSS!)

Wait, this doesn't work economically...
```

## 5. The Economic Problem

### 5.1 Light Client Update Costs

**Problem:** Updating light clients is expensive:

**Ethereum light client update (on Libra):**
- Verify 512 BLS signatures: Expensive!
- Or verify aggregated signature: Still costly
- Cost: ~$0.05-0.10 on Libra (cheap)

**Libra light client update (on Ethereum):**
- Verify quorum signatures (>100 validators)
- Ed25519 verification: ~3000 gas per signature
- Total: ~300k gas (~$30 on Ethereum!)

**Total cost:** ~$30 for light client updates
**Bounty:** $10
**Profit:** -$20 (LOSS!)

### 5.2 Solutions to Economic Problem

#### Option A: Higher Chicken Fees

**Increase chicken fee to cover costs:**
```
Chicken fee: $50 (instead of $10)
Light client update cost: $30
Prover profit: $50 - $30 = $20 ✓
```

**Trade-off:** Makes early exit expensive (might be OK)

#### Option B: Shared Light Client Updates

**Key insight:** Light client updates help ALL future bounties!

```
Bounty 1: Alice pays $10
Bounty 2: Bob pays $10
Bounty 3: Carol pays $10
Total pool: $30

First prover:
- Updates light clients ($30 cost)
- Claims all 3 bounties ($30 reward)
- Breaks even ✓

Future bounties (light client already synced):
- Just prove against existing light client
- Cost: ~$5
- Profit: $10 - $5 = $5 ✓
```

**Implementation:**
```move
struct BountyRegistry has key {
    bounties: Table<u64, SyncBounty>,
    unclaimed_pool: u64,          // Total unclaimed bounties
    last_sync_height: u64,        // Last time light client synced
}

public entry fun claim_all_pending_bounties(
    claimer: &signer,
    // Light client proofs...
) {
    // Claim ALL unclaimed bounties at once
    // Amortize light client update cost across multiple bounties
}
```

#### Option C: Optimistic Sync with Challenge Period

**Hybrid approach:**
```
1. Prover posts claim optimistically (no light client update)
   - Claims: "Accumulators synced at roots X and Y"
   - Posts bond: $20
   - Challenge period: 1 hour

2. If challenged:
   - Challenger posts counter-proof with light client update
   - If prover was wrong → lose bond
   - If prover was right → challenger loses bond

3. If not challenged:
   - Claim succeeds after 1 hour
   - Low cost ($3 gas)
```

**Economics:**
- Honest prover: $10 bounty - $3 gas = $7 profit ✓
- Dishonest prover: Loses $20 bond (deterred)
- Challenger: Only challenges if profitable (catches fraud)

#### Option D: Incremental Light Client Updates

**Optimized light client:**
```
Instead of full validator set verification:

1. Store validator set hash (32 bytes)
2. On update, submit:
   - Only signatures from ~20 validators (not all 512)
   - Prove these validators have >2/3 voting power
   - Verify just these signatures

Cost: ~20 signature verifications instead of 512
Gas: ~60k instead of 300k
Cost: ~$6 instead of $30 ✓
```

**With this optimization:**
- Light client update: $6
- Bounty: $10
- Profit: $4 ✓

## 6. Recommended Hybrid Approach

### 6.1 Optimistic Sync with Light Client Fallback

**Phase 1: Optimistic (fast & cheap)**
```
1. Prover claims sync without light client update
2. Posts bond ($20)
3. Challenge period (1 hour)
4. If not challenged → bounty paid
5. Cost: ~$3, Profit: ~$7 ✓
```

**Phase 2: Challenge (slow but trustless)**
```
1. Anyone can challenge by updating light client
2. Challenger proves actual accumulator roots
3. If prover was wrong → challenger gets bond + bounty
4. If prover was right → challenger loses challenge bond
```

**Phase 3: Fallback (timelock)**
```
1. If 1 hour passes with no challenge
2. Claim automatically succeeds
3. Assumes economic security (bond > potential fraud value)
```

### 6.2 Implementation

```move
module ol_framework::optimistic_bounty_sync {
    struct OptimisticClaim has store {
        claimer: address,
        bounty_id: u64,
        claimed_libra_root: vector<u8>,
        claimed_ethereum_root: vector<u8>,
        bond_amount: u64,
        claim_timestamp: u64,
        challenged: bool,
    }

    struct ClaimRegistry has key {
        claims: Table<u64, OptimisticClaim>,
        next_claim_id: u64,
    }

    /// Make optimistic claim (fast, cheap)
    public entry fun claim_optimistic<HomeCoin>(
        claimer: &signer,
        bounty_id: u64,
        libra_accumulator_root: vector<u8>,
        ethereum_accumulator_root: vector<u8>,
    ) acquires ClaimRegistry, BountyRegistry {
        // 1. Verify bounty exists and unclaimed
        let bounty = get_bounty(bounty_id);
        assert!(!bounty.claimed, E_ALREADY_CLAIMED);

        // 2. Charge bond
        let bond = coin::withdraw<HomeCoin>(claimer, BOND_AMOUNT);
        // Store bond in escrow

        // 3. Create optimistic claim
        let claim = OptimisticClaim {
            claimer: signer::address_of(claimer),
            bounty_id,
            claimed_libra_root: libra_accumulator_root,
            claimed_ethereum_root: ethereum_accumulator_root,
            bond_amount: BOND_AMOUNT,
            claim_timestamp: timestamp::now_seconds(),
            challenged: false,
        };

        // 4. Store claim (challenge period starts)
        let registry = borrow_global_mut<ClaimRegistry>(@ol_framework);
        table::add(&mut registry.claims, registry.next_claim_id, claim);
        registry.next_claim_id = registry.next_claim_id + 1;
    }

    /// Challenge claim with light client proof (expensive but trustless)
    public entry fun challenge_claim<HomeCoin>(
        challenger: &signer,
        claim_id: u64,

        // Light client proofs
        ethereum_state_proof: EthereumStateProof,
        libra_state_proof: LibraStateProof,
    ) acquires ClaimRegistry, BountyRegistry {
        let claim_registry = borrow_global_mut<ClaimRegistry>(@ol_framework);
        let claim = table::borrow_mut(&mut claim_registry.claims, claim_id);

        assert!(!claim.challenged, E_ALREADY_CHALLENGED);
        assert!(
            timestamp::now_seconds() < claim.claim_timestamp + CHALLENGE_PERIOD,
            E_CHALLENGE_PERIOD_EXPIRED
        );

        // 1. Update light client with proof
        ethereum_light_client::update_with_proof(ethereum_state_proof);

        // 2. Get actual accumulator roots
        let actual_ethereum_root = get_ethereum_accumulator_from_light_client();
        let actual_libra_root = auction_accumulator::get_root();

        // 3. Check if claim was fraudulent
        let claim_was_fraud =
            claim.claimed_ethereum_root != actual_ethereum_root ||
            claim.claimed_libra_root != actual_libra_root;

        if (claim_was_fraud) {
            // Challenger wins!
            // - Gets claimer's bond
            // - Gets bounty
            claim.challenged = true;

            // Pay challenger
            let bounty = get_bounty(claim.bounty_id);
            coin::transfer<HomeCoin>(
                @ol_framework,
                signer::address_of(challenger),
                claim.bond_amount + bounty.bounty_amount
            );
        } else {
            // Claimer was honest, challenger loses
            // Challenger pays for wasting everyone's time
            let challenge_penalty = coin::withdraw<HomeCoin>(
                challenger,
                CHALLENGE_PENALTY
            );
            // Penalty goes to claimer
        }
    }

    /// Finalize claim after challenge period (automatic)
    public entry fun finalize_claim<HomeCoin>(
        claim_id: u64,
    ) acquires ClaimRegistry, BountyRegistry {
        let claim_registry = borrow_global_mut<ClaimRegistry>(@ol_framework);
        let claim = table::borrow(&claim_registry.claims, claim_id);

        // Check challenge period expired
        assert!(
            timestamp::now_seconds() >= claim.claim_timestamp + CHALLENGE_PERIOD,
            E_CHALLENGE_PERIOD_NOT_EXPIRED
        );

        assert!(!claim.challenged, E_CLAIM_CHALLENGED);

        // Claim succeeded!
        let bounty = get_bounty_mut(claim.bounty_id);
        bounty.claimed = true;
        bounty.claimer = claim.claimer;

        // Pay bounty + return bond
        coin::transfer<HomeCoin>(
            @ol_framework,
            claim.claimer,
            bounty.bounty_amount + claim.bond_amount
        );
    }
}
```

### 6.3 Economic Analysis

**Honest prover (99% of cases):**
```
1. Make optimistic claim
   Cost: $3 gas
   Bond: $20 (refundable)

2. Wait 1 hour (no challenge)

3. Get bounty + bond back
   Receive: $10 + $20 = $30
   Net: $10 - $3 = $7 profit ✓
```

**Dishonest prover:**
```
1. Make fraudulent claim
   Cost: $3 gas
   Bond: $20

2. Honest actor challenges (updates light client)
   Challenger cost: $30

3. Fraud detected
   Prover loses: $20 bond
   Challenger gets: $20 bond + $10 bounty = $30
   Challenger net: $0 (break even)

Result: Fraud deterred (lose $23 total)
```

**Challenger economics:**
```
Only challenge if profitable:
- Challenger cost: $30 (light client update)
- Challenger reward if fraud: $20 bond + $10 bounty = $30
- Break even on catching fraud
- Lose money if false challenge

Result: Only challenges real fraud
```

## 7. Final Architecture

### 7.1 Three-Tier System

**Tier 1: Optimistic (fast, 99% of cases)**
- Prover claims sync optimistically
- Posts bond
- 1 hour challenge period
- Cost: $3
- Profit: $7

**Tier 2: Challenge (trustless verification)**
- Anyone can challenge with light client proof
- Expensive ($30) but catches fraud
- Challenger breaks even if fraud caught
- Deterrent mechanism

**Tier 3: Fallback (timelock)**
- If no challenge, claim succeeds
- If challenged and proven wrong, lose bond
- Safety net: can always wait for 24h timelock

### 7.2 Trust Model

**What we trust:**
- Economic rationality (bond > fraud value)
- At least one challenger exists (if fraud occurs)
- Light client cryptography (when challenged)

**What we don't trust:**
- Optimistic claimers (they post bond)
- Specific validators/oracles (light client verifies consensus)

**Security:**
- Optimistic layer: Economic security (bonds)
- Challenge layer: Cryptographic security (light client)
- Fallback layer: Time security (timelocks)

### 7.3 Comparison

| Approach | Cost | Speed | Trust | Complexity |
|----------|------|-------|-------|------------|
| **Full light client** | $30 | Slow (blocks) | None (crypto) | High |
| **Cooperative oracle** | $5 (subsidy) | Fast | M-of-N | Medium |
| **Optimistic + challenge** | **$3** | **Fast** | **Economic** | **Medium** |

## 8. Recommendation

**Use optimistic sync with light client challenge mechanism:**

**Why this wins:**
- ✅ Fast (1 hour vs. days for zkBridge)
- ✅ Cheap ($3 vs. $30-50 for full verification)
- ✅ Trustless when challenged (light client crypto)
- ✅ Economic security (bond deterrence)
- ✅ Self-correcting (challengers incentivized)
- ✅ Graceful degradation (timelock fallback)

**Implementation priority:**
1. **Week 1-3:** Accumulator + optimistic claims
2. **Week 4-6:** Light client contracts (fallback)
3. **Week 7-8:** Challenge mechanism + integration

**Launch strategy:**
1. **Phase 1:** Launch with just optimistic (trust economic security)
2. **Phase 2:** Add light client challenge (full trustlessness)
3. **Phase 3:** Optimize light client (reduce costs)

This achieves **practical trustlessness**: optimistic for speed, cryptographic for security when needed.
