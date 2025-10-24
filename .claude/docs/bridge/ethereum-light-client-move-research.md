# Research: Ethereum Light Client in Move

## Summary of Findings

After researching existing Move implementations of Ethereum light clients, I found **one major project** and identified key insights about the feasibility of implementing an Ethereum light client on the Libra (OL) chain using Move.

## 1. Prior Art: Argument Computer Corporation

### 1.1 Project Overview

**Source:** https://argument.xyz/blog/aptos-eth/ and https://github.com/argumentcomputer/zk-light-clients

**Key Achievement:** Bi-directional ZK-bridge between Ethereum and Aptos using Move

**Components:**
1. **Ethereum Light Client**: ZK-proof of Deneb sync protocol + Move verifier
2. **Aptos Light Client**: ZK-proof of Aptos light client protocol + Solidity verifier

### 1.2 Technical Architecture

**For Ethereum → Aptos verification:**

```
Ethereum Beacon Chain
    ↓
Deneb Sync Protocol (sync committee signatures)
    ↓
Sphinx zkVM generates STARK proof
    ↓
Convert STARK → SNARK (Plonk with BN254)
    ↓
Move Verifier on Aptos verifies SNARK
    ↓
Ethereum state verified on Aptos
```

**Key Innovation: Plonk Verifier in Move**

They built a Plonk verifier compatible with Move that works with proofs from the gnark Go library.

### 1.3 Performance Metrics

**End-to-end proving:**
- Ethereum light client: **11 min 40 sec**
- Total VM cycles: **10,430,605**

**Verification on-chain:**
- Move verifier validates Plonk proof
- Cryptographic security: BN254 curve

### 1.4 Code Repository

**GitHub:** https://github.com/argumentcomputer/zk-light-clients

**Repository structure:**
- Rust: 94.2% (proof generation)
- Solidity: 2.8% (Aptos light client verifier on Ethereum)
- **Move: 2.0%** (Ethereum light client verifier on Aptos)
- Active development on `dev` branch

**Documentation:** https://argumentcomputer.github.io/zk-light-clients

### 1.5 Cryptographic Primitives

**Uses:**
- **BLS signatures** (Ethereum sync committee)
- **Plonk proofs** with BN254 curve
- **STARK proofs** (converted to SNARKs through recursion)
- **Sphinx zkVM** (fork of SP1)

## 2. Alternative Approaches Found

### 2.1 Traditional Bridges (Not Light Clients)

**LayerZero Aptos Bridge:**
- Uses relayers + oracles (not light client)
- Handles $5B+ in transfers
- NOT trustless (relies on LayerZero infrastructure)

**Celer cBridge:**
- Liquidity network model
- NOT a light client
- Trusted validator set

**CheckDot.AptosBridgeContract:**
- Move smart contract for token bridging
- Manual oracle-based, not light client
- Handles decimal conversion (EVM 18 decimals → Aptos 8 decimals)

### 2.2 Sui Light Client (Native)

**Source:** https://github.com/MystenLabs/sui/tree/main/crates/sui-light-client

Sui has its own light client implementation, but this is for:
- Verifying **Sui** state (not Ethereum)
- Sync end-of-epoch checkpoints
- Committee rotation tracking

**Not applicable** to our use case (we need Ethereum → Libra verification).

## 3. Key Insights for Libra Implementation

### 3.1 Why ZK Proofs?

**The problem Argument Computer solved:**

Ethereum sync committee has 512 validators signing each block. Verifying 512 BLS signatures on-chain is expensive:

**Naive approach:**
```
512 BLS signature verifications
= ~512 * 150k gas per signature
= ~77M gas
= IMPRACTICAL on any chain
```

**ZK approach:**
```
Off-chain: Verify 512 signatures in zkVM
Generate proof: "I verified all signatures correctly"
On-chain: Verify single SNARK proof (~300k gas)
```

### 3.2 Components Needed for Libra

To implement Ethereum light client on Libra, we need:

**1. Cryptographic primitives (Move native or library):**
- BLS12-381 signature verification
- Or: SNARK verifier (Plonk/Groth16)
- Merkle proof verification (already available)
- Keccak256 hashing (for Ethereum compatibility)

**2. Sync committee tracking:**
```move
struct SyncCommittee has store {
    pubkeys: vector<vector<u8>>,  // 512 BLS pubkeys
    aggregate_pubkey: vector<u8>,
    period: u64,
}
```

**3. State root verification:**
```move
struct EthereumHeader has store {
    slot: u64,
    state_root: vector<u8>,      // This is what we need!
    // ... other fields
}
```

**4. Two implementation paths:**

**Path A: Native BLS verification (if Move supports it)**
```move
public fun verify_sync_committee_signature(
    signature: vector<u8>,
    message: vector<u8>,
    sync_committee: &SyncCommittee,
    participation_bits: vector<u8>,
) {
    // Aggregate pubkeys based on participation
    let aggregate_pubkey = aggregate_bls_pubkeys(
        sync_committee.pubkeys,
        participation_bits
    );

    // Verify signature
    assert!(bls12381::verify(signature, message, aggregate_pubkey), E_INVALID_SIG);
}
```

**Path B: SNARK verification (like Argument Computer)**
```move
public fun verify_ethereum_sync_proof(
    proof: vector<u8>,
    public_inputs: vector<vector<u8>>,
) {
    // Verify Plonk proof
    assert!(plonk::verify(proof, public_inputs), E_INVALID_PROOF);
}
```

### 3.3 Pros/Cons of Each Approach

**Native BLS Verification:**

Pros:
- ✅ No proof generation latency (instant)
- ✅ Simpler (no zkVM needed)
- ✅ Deterministic gas cost

Cons:
- ❌ High on-chain cost (~77M gas equivalent)
- ❌ Requires Move to have BLS12-381 support
- ❌ May not fit in block gas limit

**SNARK Verification:**

Pros:
- ✅ Low on-chain cost (~300k gas equivalent)
- ✅ Constant cost (regardless of committee size)
- ✅ Proven approach (Argument Computer)

Cons:
- ❌ Requires proof generation (11 min latency)
- ❌ Need zkVM infrastructure (Sphinx/SP1)
- ❌ Need Plonk verifier in Move (complex)
- ❌ High off-chain compute cost

## 4. Practical Recommendation for Libra

### 4.1 Start with State Root Checkpoints (No Full Light Client)

**Don't implement full light client initially.** Instead:

```move
module ol_framework::ethereum_checkpoints {
    struct EthereumCheckpoint has store {
        state_root: vector<u8>,    // Just 32 bytes!
        block_number: u64,
        timestamp: u64,
    }

    struct CheckpointRegistry has key {
        checkpoints: Table<u64, EthereumCheckpoint>,
        latest_checkpoint: u64,
    }

    /// Submit checkpoint with proof
    public entry fun submit_checkpoint(
        state_root: vector<u8>,
        block_number: u64,
        proof: vector<u8>,  // Could be ZK proof or signature aggregate
    ) {
        // Verify proof (details depend on approach)
        assert!(verify_checkpoint_proof(state_root, block_number, proof), E_INVALID);

        // Store checkpoint
        // ... implementation
    }
}
```

**Benefits:**
- No continuous sync required
- Submit checkpoints on-demand (when bounties exist)
- Can upgrade verification method later

### 4.2 Hybrid Approach: Optimistic + Optional ZK

**Phase 1: Optimistic checkpoints (MVP)**
```move
public entry fun submit_checkpoint_optimistic(
    submitter: &signer,
    state_root: vector<u8>,
    block_number: u64,
    bond: u64,
) {
    // Post bond
    coin::withdraw<LibraCoin>(submitter, bond);

    // Submit without immediate verification
    // Challenge period: 1 hour
    // ... implementation
}

public entry fun challenge_checkpoint(
    challenger: &signer,
    checkpoint_id: u64,
    proof_of_fraud: vector<u8>,
) {
    // Prove checkpoint was invalid
    // Challenger gets bond
    // ... implementation
}
```

**Phase 2: Add ZK verification (optional)**
```move
public entry fun submit_checkpoint_with_proof(
    submitter: &signer,
    state_root: vector<u8>,
    block_number: u64,
    zk_proof: vector<u8>,
) {
    // Verify ZK proof immediately
    assert!(plonk::verify(zk_proof, ...), E_INVALID_PROOF);

    // No bond needed, immediate acceptance
    // ... implementation
}
```

**Users can choose:**
- Optimistic (fast, cheap, requires bond)
- ZK-proven (slower, more expensive, no bond)

### 4.3 Leveraging Argument Computer's Work

**What we can reuse:**

1. **Plonk verifier in Move** (if they open-source it)
   - They already built this for Aptos
   - Should work on Libra with minimal changes

2. **Sphinx zkVM setup**
   - Fork their repo: https://github.com/argumentcomputer/sphinx
   - Generate proofs off-chain for Ethereum sync committee

3. **Architecture pattern**
   - Proven to work (production ready)
   - 11 min proof generation is acceptable for checkpoints

**What we'd need to add:**

1. **Libra-specific adaptations**
   - Deploy Move verifier on Libra
   - Adapt for Libra's Move version (if different from Aptos)

2. **Integration with bounty system**
   - Submit checkpoint → claim bounty
   - Economic incentives

3. **Checkpoint registry**
   - Storage for state roots
   - Merkle proof verification against checkpoints

## 5. Alternative: Simpler Approaches

### 5.1 Validator Signature Verification (No ZK)

**If Libra supports BLS or has crypto precompiles:**

```move
public entry fun submit_checkpoint_with_signatures(
    state_root: vector<u8>,
    block_number: u64,
    signatures: vector<vector<u8>>,
    signer_indices: vector<u64>,
) {
    // Verify we have >2/3 of sync committee
    assert!(vector::length(&signatures) >= 342, E_INSUFFICIENT_SIGS);

    // Verify each signature
    let message = compute_signing_root(state_root, block_number);
    verify_sync_committee_signatures(
        message,
        signatures,
        signer_indices,
        &current_sync_committee
    );

    // Store checkpoint
    // ... implementation
}
```

**Requirements:**
- BLS12-381 support in Move
- Gas cost must be reasonable (< 10M gas equivalent)

**Check if Libra/Aptos has:**
- Native BLS operations
- Crypto module with BLS12-381
- Gas metering allows this scale

### 5.2 Merkle Mountain Range Checkpoints

**For sparse checkpoints:**

```move
/// Only store checkpoints when needed (on-demand)
/// Use MMR to prove checkpoint history
struct CheckpointMMR has key {
    peaks: vector<vector<u8>>,
    leaf_count: u64,
}

public fun verify_checkpoint_in_mmr(
    checkpoint: &EthereumCheckpoint,
    proof: vector<vector<u8>>,
    mmr_root: vector<u8>,
) {
    // Verify checkpoint is in MMR
    // Allows proving historical checkpoints exist
    // ... implementation
}
```

**Benefits:**
- Compact storage
- Can prove checkpoint lineage
- Good for infrequent updates

## 6. Implementation Checklist

### Research Phase (Week 1)

- [ ] Check Libra's Move version compatibility with Aptos
- [ ] Verify BLS12-381 support in Libra's Move
- [ ] Check gas costs for crypto operations
- [ ] Review Argument Computer's code (if open-source)
- [ ] Benchmark Merkle proof verification costs

### Decision Phase (Week 2)

**Choose approach based on findings:**

**If BLS12-381 available:**
→ Use native verification (simpler)

**If not:**
→ Use ZK proofs (Argument Computer approach)

**If gas costs too high:**
→ Use optimistic checkpoints (MVP)

### MVP Implementation (Week 3-5)

**Minimum viable light client:**

```
Week 3: Checkpoint storage + Merkle verification
Week 4: Optimistic submission + challenge
Week 5: Integration with bounty system
```

### Advanced Implementation (Week 6-8)

**Add ZK verification:**

```
Week 6: Deploy Plonk verifier (from Argument Computer)
Week 7: Set up Sphinx zkVM for proof generation
Week 8: End-to-end testing
```

## 7. Cost Analysis

### 7.1 Using ZK Proofs (Argument Computer Approach)

**Off-chain costs:**
- Proof generation: 11 min 40 sec
- Compute: ~$0.50 - $5.00 (depending on hardware)

**On-chain costs:**
- Plonk verification: ~300k gas
- At 20 gwei, 2000 ETH/USD: ~$12
- On Libra (cheaper): ~$0.10 - $1.00

**Total per checkpoint:** ~$1-6

### 7.2 Using Optimistic Checkpoints

**On-chain costs:**
- Submit checkpoint: ~50k gas → ~$0.05 on Libra
- Post bond: $30 (refundable)

**Challenge costs (only if fraud):**
- ZK proof verification: ~$1-6
- Challenger gets bond

**Normal case:** ~$0.05 (very cheap!)

### 7.3 Economic Viability

**For bounty system:**

```
Chicken fee: $20
Checkpoint cost: $0.05 - $6
Bounty claimable: $20 - checkpoint cost
Net profit: $14 - $20

Profitable! ✓
```

## 8. Recommended Path Forward

### Phase 1: MVP (Optimistic)

**Week 1-2: Research & Design**
- Verify Libra's crypto capabilities
- Design checkpoint registry
- Plan optimistic verification

**Week 3-5: Implementation**
- Checkpoint storage (Move)
- Optimistic submission with bonds
- Challenge mechanism
- Merkle proof verification

**Week 6: Integration**
- Connect to bounty system
- Test with real Ethereum data
- Optimize gas costs

### Phase 2: Add ZK (Optional)

**Week 7-8: ZK Integration**
- Deploy Argument Computer's Plonk verifier
- Set up Sphinx zkVM
- Generate test proofs

**Week 9-10: Production**
- Optimize proof generation
- Add caching/batching
- Security audit

### Phase 3: Optimization

**Week 11-12: Advanced Features**
- Checkpoint batching
- MMR for history
- Gas optimizations

## 9. Resources & References

### Code Repositories

1. **Argument Computer ZK Light Clients**
   - https://github.com/argumentcomputer/zk-light-clients
   - Move verifier code (2% of repo)
   - Ethereum sync protocol implementation

2. **Sphinx zkVM**
   - https://github.com/argumentcomputer/sphinx
   - Fork of SP1
   - Proof generation

3. **Ethereum Consensus Specs**
   - https://github.com/ethereum/consensus-specs
   - Light client sync protocol
   - Deneb specification

4. **Ethereum Beacon APIs**
   - https://github.com/ethereum/beacon-APIs
   - Light client endpoints
   - Sync committee data

### Documentation

1. **Argument Computer Blog**
   - https://argument.xyz/blog/aptos-eth/
   - Architecture overview
   - Performance metrics

2. **Ethereum Light Client Docs**
   - https://notes.ethereum.org/@ralexstokes/S1RSe1JlF
   - Beacon chain light client design
   - Sync committee protocol

3. **Aptos Move Documentation**
   - https://aptos.dev/build/smart-contracts
   - Move language reference
   - Crypto modules

### Community

1. **Argument Computer**
   - Contact for Move verifier code
   - Potential collaboration

2. **Aptos Discord/Forums**
   - Move developer community
   - Crypto primitives discussion

## 10. Conclusion

### What Exists

**✓ Argument Computer has proven it's possible**
- Ethereum light client in Move works
- Plonk verifier on Aptos deployed
- Production-grade implementation

**✓ Open-source code available**
- Can fork and adapt for Libra
- Sphinx zkVM for proof generation
- Well-documented approach

### What We Need

**? Verify Libra compatibility**
- Check Move version vs. Aptos
- Verify crypto primitive availability
- Test gas costs

**✓ Adapt for our use case**
- Integrate with checkpoint-bounty system
- On-demand submission (not continuous)
- Optimize for cost

### Recommended Approach

**Start simple (optimistic), add ZK later:**

1. **MVP:** Optimistic checkpoints with bonds ($0.05 cost)
2. **V2:** Add ZK proofs using Argument Computer's verifier ($1-6 cost)
3. **V3:** Optimize with batching/caching

**Timeline:** 6-12 weeks to production

**Risk:** Low - proven approach, existing code

This is the most practical path to a trustless Ethereum → Libra light client.
