
# Product Spec: Trustless Ethereum State Verification on Home Chain

## Overview

This system enables a Home chain (e.g., Aptos, Sui, or other Move-based chain) to interact with Ethereum state in a **trustless, permissionless, and storage-efficient** manner.

Key objectives:

- Store minimal Ethereum state on-chain.
- Allow users to prove Ethereum headers and transaction inclusion.
- Allow volunteers to increment Ethereum state roots as a public good.
- Leverage **Succinct Labs zk-light-client technology** for trustless proof generation and verification.

---

## Goals

- **Minimal on-chain storage:** Store only the latest zk-verified Ethereum accumulator root.
- **Trustless verification:** Anyone can submit proofs without being trusted.
- **Supported actions:**
  - Header validity verification
  - Transaction inclusion verification
  - Accumulator root updates by volunteers

---

## Trust Model

| Actor                      | Trust Required?                                          |
| -------------------------- | -------------------------------------------------------- |
| Volunteer updating headers | None (zk proof enforces correctness)                     |
| User submitting tx proof   | None (zk proof enforces correctness)                     |
| Home chain                 | Must trust zk-verifier correctness (public, open-source) |

---

# Move Modules
## State Storage
We need to store all known ethereum headers (or a window). However this would take a lot of space over time.
There is a pattern in the Ethereum ecosystem of using an Accumulator which can be incremented. There are a number of techniques (e.g. Merkle Mountain Range). However Succinct Labs has production deployed SNARK proof accumulators (which we can check against accumulator hashes published by other ecosystem participants).

### Storage Requirements

* **Accumulator root:** 32 bytes (constant size)
* **Verifier parameters:** Fixed, constant size
* **Transaction proofs:** Ephemeral; verified on submission, not stored permanently

### Stub

```move
struct AccumulatorState has key {
    blob: vector<u8>,        // State of all known headers
    last_header: vector<u8>,
    block_number: u64,       // Block number of the last verified header
}

struct ZKVerifierParams {
  // ** TBD parameters for all ZK verification ** //
}
```

---

## Header Proof Submission

Allows volunteers to submit zk proofs that extend the Ethereum accumulator root.

### Workflow Header Update (Volunteer)
1. Volunteer fetches latest Ethereum finalized headers.
2. Generates zk proof that headers extend the current accumulator root (using **Succinct Labs zk-light-client tech**).
3. Submits zk proof + new accumulator root to Home chain.
4. Home chain verifies proof → updates `AccumulatorRoot`.


### Stub
```move
public fun submit_header_proof(
    proof: ProofData,
    new_root: vector<u8>,
    params: &ZKVerifierParams,
    accumulator: &mut AccumulatorRoot
) {
    assert!(verify_header_zk(proof, params, accumulator.root), 1);
    accumulator.root = new_root;
    accumulator.block_number = proof.final_block_number;
}
```

* **Input:** zk proof, new Ethereum accumulator root, verifier params
* **Effect:** Updates `AccumulatorRoot` if proof is valid
* **Trust model:** Volunteer is untrusted; correctness enforced by zk proof

---

## ETH Transaction Inclusion Proof

Allows users to prove that a transaction was committed on Ethereum.

### Workflow Transaction Inclusion (User)

1. User fetches Ethereum transaction receipt + Merkle-Patricia proof.
2. Optionally compresses proof into a zk proof.
3. Submits proof to Home chain referencing current `AccumulatorRoot`.
4. Home chain verifies proof → confirms transaction inclusion.


```move
public fun submit_tx_inclusion_proof(
    tx_proof: TxProof,
    accumulator: &AccumulatorRoot
) {
    assert!(verify_tx_zk(tx_proof, accumulator.root), 2);
    // Optional: emit event or trigger application logic
}
```

* **Input:** Transaction proof (receipt + optional zk compression)
* **Effect:** Verifies transaction inclusion against canonical Ethereum accumulator root
* **Storage:** Ephemeral; no historical headers or receipts stored

---


## Optional Enhancements

* **Batch proofs:** Submit multiple headers in a single proof to reduce gas per block
* **Event logging:** Emit events on accumulator update or transaction inclusion for off-chain indexers
* **User zk compression:** Transaction inclusion proofs can be zk-compressed to reduce verification cost

---

## Open Questions

### Chain Reorganization Handling

**Question:** How does Optimism or SP1 handle Ethereum chain reorganizations?

**Context:** While Ethereum post-merge reorgs are rare (especially after finality), they can still occur. The system needs to define behavior when:
- A previously "finalized" block gets reorganized (extremely rare but theoretically possible)
- Headers are submitted that conflict with the canonical chain
- The accumulator includes headers from a non-canonical fork

**Research needed:**
- Review SP1/Optimism implementation for reorg handling mechanisms
- Determine if relying on Ethereum's finality (64+ slots) is sufficient
- Define recovery procedures if reorg is detected
- Consider whether accumulator needs reorg protection or if finality guarantees are adequate

---

## Implementation Recommendation

* Use **Succinct Labs zk-light-client technology** to:

  * Generate zk proofs for header extensions
  * Verify proofs of Ethereum transaction inclusion
  * Maintain a trustless, minimal-storage Ethereum accumulator root on the Home chain

* Benefits:

  * **Permissionless participation:** Any volunteer or user can submit proofs
  * **Constant on-chain storage:** Only one root and verifier parameters
  * **Scalability and efficiency:** No historical headers or receipts need storing

1. SP1

Description: SP1 is a high-performance zero-knowledge virtual machine (zkVM) that allows developers to write programs in Rust (or any LLVM-compiled language) and generate zero-knowledge proofs of their execution.

Use Case: Ideal for generating ZK proofs of Ethereum block execution or header validity.

Features:

Supports Rust standard library.

Customizable precompiles for performance.

Utilizes the latest techniques in STARKs for performant recursion and on-chain verification.

2. RSP (Reth Succinct Processor)

Description: RSP is a minimal implementation of generating zero-knowledge proofs of EVM block execution using Reth. It supports both Ethereum and the Optimism Stack.

Use Case: Suitable for generating ZK proofs of Ethereum block execution, ensuring correctness without trusting the execution environment.

Features:

Generates ZK proofs for Ethereum block execution.

Supports both Ethereum and Optimism, facilitating interoperability between different Ethereum-compatible chains.
GitHub

## On-Chain Precompile of Rust Verifier

### Using the sp1-verifier Crate

The `sp1-verifier` crate is designed for verifying ZK proofs produced by SP1. It is compatible with Rust and can be integrated into your application to validate proofs off-chain or compiled as a precompile for on-chain verification.

To include the `sp1-verifier` crate in your Rust project, add the following to your `Cargo.toml`:

```toml
[dependencies]
sp1-verifier = "1.0"  # Check for latest version
```

### Usage Example

Here's a basic example of how to use the `sp1-verifier` crate to verify a ZK proof:

```rust
use sp1_verifier::{verify_groth16, verify_plonk};

fn main() {
    // Load your proof data
    let proof_data = load_proof_data();

    // Verify Groth16 proof
    match verify_groth16(&proof_data) {
        Ok(is_valid) => println!("Groth16 proof valid: {}", is_valid),
        Err(e) => eprintln!("Error verifying Groth16 proof: {}", e),
    }

    // Verify Plonk proof
    match verify_plonk(&proof_data) {
        Ok(is_valid) => println!("Plonk proof valid: {}", is_valid),
        Err(e) => eprintln!("Error verifying Plonk proof: {}", e),
    }
}

fn load_proof_data() -> Vec<u8> {
    // Implement loading of proof data
    vec![]
}
```

This example demonstrates how to verify both Groth16 and Plonk proofs. You'll need to implement the load_proof_data function to load your specific proof data.
