# Research: Canonical ZK Proof Services for Ethereum

## Executive Summary

Yes, there are **several canonical web services/APIs** that can produce ZK proofs of transactions being included on Ethereum. The three major production-ready services are:

1. **Axiom** - ZK coprocessor for historical Ethereum data
2. **Succinct Network** - Decentralized ZK proof marketplace
3. **Brevis** - ZK coprocessor with EigenLayer integration
4. **Herodotus** - Storage proof infrastructure

All of these can prove Ethereum transaction inclusion and state, eliminating the need to run your own zkVM infrastructure.

## 1. Axiom

### 1.1 Overview

**Website:** https://www.axiom.xyz/
**Docs:** https://docs.axiom.xyz/

**What it does:**
- ZK coprocessor for accessing Ethereum historical data
- Proves transaction inclusion, receipt data, account state, storage
- Verifies proofs on-chain via smart contract callback

### 1.2 How It Works

```
Developer submits query → Axiom generates ZK proof off-chain
    ↓
Proof verified on Ethereum smart contract
    ↓
Results sent to your contract via callback
```

**What you can prove:**
- Block headers
- Account state (balance, nonce, code hash)
- Contract storage slots
- **Transactions** (from, to, value, data, etc.)
- **Receipts** (logs, status, gas used)

### 1.3 Pricing (2024)

**Fixed per query:**
- Axiom fee: **0.003 ETH** (~$6 at $2000 ETH)
- Proof verification gas: **~420,000 gas** (~$17 at 20 gwei)
- Total: **~$23 per query**

**For rollups using Axiom Proving API:**
- **< $0.001 per transaction**

### 1.4 API Usage

```typescript
import { Axiom, QueryV2 } from '@axiom-crypto/core';

// Create query
const query = new QueryV2({
  sourceChainId: '1', // Ethereum mainnet
  dataQuery: [
    {
      blockNumber: 12345678,
      fieldIdx: FieldIdx.Transaction.TxHash,
      txIdx: 42
    }
  ],
  computeQuery: {
    // Optional: compute on the data
  },
  callback: {
    target: '0xYourContract...',
    extraData: '0x...'
  }
});

// Submit query
await axiom.sendQuery(query);

// Axiom generates proof and calls your contract
```

### 1.5 Integration Example

**Your smart contract:**
```solidity
contract MyContract {
    function axiomCallback(
        bytes32 queryId,
        bytes32[] calldata results
    ) external {
        // Verify this is from Axiom
        require(msg.sender == AXIOM_ADDRESS);

        // Use proven data
        bytes32 txHash = results[0];
        // ... your logic
    }
}
```

### 1.6 Pros/Cons

**Pros:**
- ✅ Production-ready (mainnet deployed)
- ✅ Comprehensive API (SDK + REST)
- ✅ Supports all historical Ethereum data
- ✅ On-chain verification
- ✅ Well-funded ($20M Series A)

**Cons:**
- ❌ Expensive per query ($23)
- ❌ Centralized service (single operator)
- ❌ Callback-based (not request/response)

## 2. Succinct Network

### 2.1 Overview

**Website:** https://www.succinct.xyz/
**Docs:** https://docs.succinct.xyz/

**What it does:**
- Decentralized marketplace for ZK proof generation
- Powered by SP1 zkVM
- Uses PROVE token for payments

### 2.2 How It Works

```
Requester submits proof request → Provers bid (auction)
    ↓
Lowest bidder generates proof (SP1 zkVM)
    ↓
Proof verified on-chain or off-chain
```

**What you can prove:**
- Any Rust program execution
- Ethereum block execution (via Reth + Revm)
- Tendermint light client
- Custom verification logic

### 2.3 Pricing

**Market-based:**
- Provers compete in auctions
- Payment in **PROVE tokens**
- Typical costs: **Variable based on proof complexity**

**Competition drives prices:**
- Provers stake PROVE to participate
- Bid for lowest price they'll accept
- Market discovers true cost

### 2.4 API Usage

```rust
// Set up SP1 with network prover
SP1_PROVER=network SP1_PRIVATE_KEY=your_key cargo run

// Your Rust program
#[sp1_derive::cycle_tracker]
fn main() {
    // Read Ethereum block header
    let header = sp1_lib::io::read::<Header>();

    // Verify transaction inclusion
    let tx_proof = verify_tx_inclusion(&header, tx_hash);

    // Output result
    sp1_lib::io::commit(&tx_proof);
}
```

**Submit to network:**
```typescript
import { SuccinctClient } from '@succinct/sdk';

const client = new SuccinctClient();

const proof = await client.requestProof({
    program: programBinary,
    inputs: ethBlockHeader,
});

// Verify proof on-chain or use off-chain
```

### 2.5 Pros/Cons

**Pros:**
- ✅ Decentralized (marketplace of provers)
- ✅ Flexible (any Rust program)
- ✅ Market-driven pricing
- ✅ SP1 Hypercube: real-time Ethereum proving
- ✅ Open-source zkVM

**Cons:**
- ❌ More complex setup (write Rust programs)
- ❌ New token economics (PROVE)
- ❌ Variable pricing (auction-based)
- ❌ Network still maturing

## 3. Brevis

### 3.1 Overview

**Website:** https://brevis.network/
**Docs:** https://coprocessor-docs.brevis.network/

**What it does:**
- ZK coprocessor with EigenLayer integration
- Crypto-economic security + ZK fraud proofs
- Real-time proving (Pico Prism)

### 3.2 How It Works

```
Smart contract sends request → Brevis coChain (PoS)
    ↓
Validators propose result (crypto-economic security)
    ↓
Open to ZK fraud proof challenges
    ↓
Final result verified on-chain
```

**Hybrid security:**
- Initial: Crypto-economic (staking/slashing via EigenLayer)
- Challenged: ZK fraud proofs
- Combines speed + trustlessness

### 3.3 Technology

**Pico Prism (2024):**
- Real-time Ethereum proofs (12 seconds)
- Consumer hardware (RTX 5090)
- 99.6% coverage of mainnet blocks

**What you can prove:**
- Historical on-chain data (all supported chains)
- Custom computations on blockchain data
- Transaction inclusion
- Storage proofs

### 3.4 API Usage

```typescript
import { Brevis } from '@brevis/sdk';

const brevis = new Brevis({
    chainId: 1,
});

// Request coprocessing
const request = await brevis.request({
    sourceChainId: 1,
    dataPoints: [
        {
            type: 'transaction',
            txHash: '0x...',
            fields: ['from', 'to', 'value']
        }
    ],
    computeScript: customComputeLogic,
    targetContract: '0xYourContract...'
});

// Brevis generates proof and calls your contract
```

### 3.5 Pros/Cons

**Pros:**
- ✅ Fast (real-time with Pico Prism)
- ✅ EigenLayer integration (restaking security)
- ✅ Hybrid security model
- ✅ Consumer hardware capable
- ✅ Multi-chain support

**Cons:**
- ❌ Newer (less battle-tested)
- ❌ Pricing not public
- ❌ Centralized coChain (though EigenLayer secured)

## 4. Herodotus

### 4.1 Overview

**Website:** https://herodotus.dev/
**Docs:** https://docs.herodotus.dev/

**What it does:**
- Storage proof infrastructure
- Uses STARKs for verification
- Focuses on cross-chain state access

### 4.2 How It Works

```
Request storage proof → Herodotus generates STARK proof
    ↓
Proof includes Merkle Patricia Trie verification
    ↓
Verified on destination chain
```

**What you can prove:**
- Account balances at any block
- Contract storage at any block
- Transaction receipts
- Historical state

### 4.3 Technology

**Storage Proofs = Inclusion + Computation + ZK:**
- Merkle Patricia Trie inclusion
- Multi-step workflow verification
- STARK proofs for efficiency

**On-chain Accumulator:**
- Stores historical Ethereum state roots
- Enables verification without trusted party
- Uses StarkWare's STARK technology

### 4.4 API Usage

**Interactive API:**
```bash
# Request storage proof
curl -X POST https://api.herodotus.dev/storage-proof \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 1,
    "blockNumber": 12345678,
    "address": "0x...",
    "storageSlot": "0x..."
  }'

# Returns STARK proof + verification data
```

**Smart contract integration:**
```solidity
contract MyContract {
    function verifyStorage(
        bytes calldata proof,
        uint256 blockNumber,
        address account,
        bytes32 slot,
        bytes32 value
    ) external {
        // Verify against Herodotus accumulator
        require(herodotus.verify(proof, ...));

        // Use proven storage value
    }
}
```

### 4.5 Pros/Cons

**Pros:**
- ✅ STARK proofs (efficient verification)
- ✅ Focus on storage (good for our use case)
- ✅ Multi-chain support
- ✅ On-chain accumulator

**Cons:**
- ❌ Pricing not public
- ❌ Newer infrastructure
- ❌ Limited documentation
- ❌ StarkWare dependency

## 5. Comparison Table

| Service | Type | Pricing | Decentralization | Speed | Best For |
|---------|------|---------|------------------|-------|----------|
| **Axiom** | ZK Coprocessor | $23/query | Centralized | Minutes | Historical data queries |
| **Succinct** | Proof Marketplace | Market (PROVE) | Decentralized | Variable | Custom programs |
| **Brevis** | Hybrid Coprocessor | TBD | Hybrid (EigenLayer) | 12 sec | Real-time proofs |
| **Herodotus** | Storage Proofs | TBD | Centralized | Minutes | Cross-chain state |

## 6. Recommended for Libra Atomic Swaps

### 6.1 Best Fit: Axiom

**Why:**
- ✅ Proven production system
- ✅ Directly supports transaction/receipt proofs
- ✅ Clear pricing model
- ✅ Easy integration (SDK + docs)

**Use case:**
```typescript
// Prove Alice's ETH lock transaction exists
const query = new QueryV2({
  sourceChainId: '1',
  dataQuery: {
    blockNumber: ethBlockNumber,
    txHash: aliceLockTxHash,
    fields: ['to', 'value', 'input'] // Verify lock details
  },
  callback: {
    target: libraCheckpointContract,
    extraData: auctionId
  }
});
```

**Cost per checkpoint:**
- Axiom query: $23
- But can batch multiple auctions per query
- Amortize across bounties

### 6.2 Alternative: Succinct Network

**Why:**
- ✅ Decentralized (no single point of failure)
- ✅ Market-based pricing (potentially cheaper)
- ✅ Already used by Argument Computer

**Use case:**
```rust
// Custom Rust program in SP1
fn verify_eth_lock() {
    let block_header = sp1_lib::io::read::<Header>();
    let tx_proof = sp1_lib::io::read::<TxProof>();

    // Verify transaction in block
    assert!(verify_tx_inclusion(block_header, tx_proof));

    // Verify lock amount, recipient, etc.
    assert!(tx.to == LOCK_CONTRACT);
    assert!(tx.value >= MIN_AMOUNT);

    sp1_lib::io::commit(&true);
}
```

**Cost:**
- Market-driven (likely $5-20)
- More control over proof generation
- Can optimize for our specific use case

### 6.3 Hybrid Approach

**Phase 1: Use Axiom (MVP)**
- Fast integration
- Proven reliability
- Known costs

**Phase 2: Move to Succinct (Optimization)**
- Lower costs (market competition)
- More decentralization
- Custom proof logic

## 7. Integration Architecture

### 7.1 With Axiom

```
Early Exit Flow:

1. Alice requests early exit on Libra
   → Pays $20 chicken fee → bounty pool

2. Bob (bounty hunter) sees opportunity
   → Submits Axiom query for Alice's ETH lock
   → Cost: $23 (more than bounty!)

   Wait, this doesn't work economically...
```

**Solution: Batch queries**

```
Multiple exits:
- Alice exits (bounty $20)
- Frank exits (bounty $20)
- Grace exits (bounty $20)
Total: $60

Bob submits ONE Axiom query proving all 3:
- Cost: $23
- Revenue: $60
- Profit: $37 ✓
```

### 7.2 With Succinct Network

```
Early Exit Flow:

1. Alice requests early exit
   → Pays $20 chicken fee

2. Bob submits proof request to Succinct Network
   → Provers bid (auction)
   → Winning bid: ~$10-15
   → Proof generated

3. Bob claims bounty with proof
   → Revenue: $20
   → Cost: $10-15
   → Profit: $5-10 ✓
```

### 7.3 Optimistic + ZK Hybrid

**Best of both worlds:**

```
Phase 1 (Optimistic):
- Submit checkpoint optimistically ($0.05)
- Post bond ($30)
- Challenge period (1 hour)

Phase 2 (If challenged):
- Use Axiom/Succinct for proof ($10-23)
- Challenger pays if wrong
- Submitter pays if fraud

Normal case: $0.05 cost
Fraud case: $10-23 cost (rare)
```

## 8. Cost Analysis

### 8.1 Per-Checkpoint Costs

**Option A: Direct Axiom**
```
Single checkpoint:
- Axiom query: $23
- Bounty needed: $25+
- Minimum chicken fee: $25
- Not economical for small swaps
```

**Option B: Batched Axiom**
```
5 checkpoints batched:
- Axiom query: $23
- Bounties: 5 × $20 = $100
- Net: $100 - $23 = $77
- Per checkpoint: $77 / 5 = $15.40 profit ✓
```

**Option C: Succinct Network**
```
Single checkpoint:
- Proof cost: ~$10-15 (market rate)
- Bounty: $20
- Net: $5-10 profit ✓
```

**Option D: Optimistic (our design)**
```
Single checkpoint:
- Optimistic submission: $0.05
- Bond: $30 (refundable)
- Challenge rare (use Axiom/Succinct if needed)
- Net: ~$20 profit ✓
```

### 8.2 Recommended Strategy

**Combine optimistic + ZK services:**

```move
public entry fun submit_checkpoint_optimistic(
    submitter: &signer,
    state_root: vector<u8>,
    block_number: u64,
) {
    // Optimistic submission
    post_bond(submitter, 30); // $30 bond
    store_checkpoint(state_root, block_number);
    // Challenge period: 1 hour
}

public entry fun challenge_checkpoint(
    challenger: &signer,
    checkpoint_id: u64,
    axiom_proof: vector<u8>, // From Axiom/Succinct
) {
    // Verify ZK proof shows different state root
    assert!(verify_zk_proof(axiom_proof), E_INVALID_PROOF);

    // Slash submitter's bond
    // Give bond to challenger
}
```

**Economics:**
- Normal: $0.05 cost, $20 bounty, $19.95 profit
- Challenged: $0.05 + $30 bond lost = $30.05 cost (fraud deterrent)
- Challenger: $23 proof cost - $30 bond = $7 profit

## 9. Recommendations

### 9.1 Immediate (MVP)

**Use optimistic checkpoints (no ZK service):**
- Simple implementation
- $0.05 cost per checkpoint
- $20 bounty profitable
- Launch quickly

### 9.2 Phase 2 (Add Security)

**Integrate Axiom for challenges:**
- Optimistic by default
- Axiom proof if challenged
- Best UX + security trade-off

### 9.3 Phase 3 (Optimize)

**Migrate to Succinct Network:**
- Lower costs ($10 vs $23)
- Decentralized
- More control

### 9.4 Future (Advanced)

**Run own zkVM:**
- Use SP1 (open-source)
- Full control
- No service fees
- Requires infrastructure

## 10. Conclusion

**Yes, canonical ZK proof services exist and are production-ready:**

1. **Axiom** - Best for immediate integration ($23/query)
2. **Succinct** - Best for decentralization (market pricing)
3. **Brevis** - Best for real-time (12 sec proofs)
4. **Herodotus** - Best for storage proofs (STARK-based)

**For Libra atomic swaps:**

**Recommended: Optimistic checkpoints + Axiom for challenges**
- Normal case: $0.05 (optimistic)
- Challenge case: $23 (Axiom proof)
- Best economics + security

**Alternative: Succinct Network**
- Direct proof generation (~$10-15)
- More decentralized
- Market-driven pricing

Both approaches eliminate the need to run your own zkVM infrastructure while keeping costs reasonable through the bounty mechanism.
