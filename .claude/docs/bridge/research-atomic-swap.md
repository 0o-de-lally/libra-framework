# Research: Atomic Swap Protocol for OL ↔ EVM Cross-Chain Exchange

## 1. Research Plan & Objectives

### 1.1 Project Overview

**Goal**: Design and implement a trustless, administrator-free atomic swap protocol enabling direct peer-to-peer asset exchanges between OL (Move-based blockchain) and EVM-compatible chains (e.g., Ethereum).

**Key Constraints**:
- No intermediaries, administrators, or validators
- Self-verifying through cryptographic protocols and on-chain metadata
- Compatible software for both OL and Ethereum transaction submission
- Move language on home chain (OL)
- Solidity on away chain (EVM)

### 1.2 Research Objectives

1. **Protocol Design**
   - Identify proven atomic swap patterns and mechanisms
   - Understand Hash Time Locked Contracts (HTLCs) - the foundational pattern
   - Research cross-chain communication patterns without oracles/bridges
   - Analyze security considerations and attack vectors

2. **Move Implementation**
   - Investigate Move language patterns for HTLCs
   - Research existing Move atomic swap implementations
   - Understand Move's resource model for secure asset handling
   - Identify testing patterns for Move smart contracts

3. **Solidity/EVM Implementation**
   - Study Solidity HTLC implementations
   - Review battle-tested EVM atomic swap contracts
   - Analyze gas optimization patterns
   - Understand Solidity testing frameworks

4. **Testing Strategy**
   - Unit testing for Move modules
   - Unit testing for Solidity contracts
   - Functional testing for both chains independently
   - E2E testing with docker-compose orchestration
   - Integration testing between chains

5. **Development Environment**
   - Move development and testing setup (already available in this repo)
   - Solidity development framework selection (Hardhat vs Foundry)
   - Docker compose architecture for dual-chain testnet
   - CLI tooling for transaction submission

### 1.3 Research Questions

**Protocol Level**:
- What is the exact cryptographic flow for trustless atomic swaps?
- What are the failure modes and how are they handled?
- What timelock values are safe for cross-chain swaps?
- How do users discover and match swap intentions off-chain?

**Implementation Level**:
- How do Move's linear types and resource safety affect HTLC design?
- What are the gas costs on EVM side and how to optimize?
- How can we ensure both contracts have matching logic?
- What events/logging is needed for UX and debugging?

**Testing Level**:
- How to simulate time advancement in both environments?
- How to test timeout/refund scenarios?
- How to coordinate dual-chain state in E2E tests?
- What test vectors ensure security properties?

### 1.4 Success Criteria

- Complete understanding of HTLC atomic swap protocol
- Identification of reference implementations in both Move and Solidity
- Clear specification of on-chain contract interfaces
- Documented testing strategy with specific frameworks
- Docker compose architecture design for E2E testing
- Security analysis of the protocol

---

## 2. Prior Art & Existing Patterns

### 2.1 Foundational Concepts

**Atomic Swaps** enable trustless cross-chain asset exchanges without intermediaries using Hash Time Locked Contracts (HTLCs). The protocol ensures that either both parties successfully exchange assets, or the swap is completely reverted - there is no partial completion.

### 2.2 Reference Implementations

#### Ethereum/EVM
- **chatch/hashed-timelock-contract-ethereum**: Production-ready implementation supporting ETH, ERC20, and ERC721
  - 39 comprehensive test scenarios
  - Used in real cross-chain swap applications
  - Clean interface: `newContract()`, `withdraw()`, `refund()`

- **movnetwork/swap**: Multi-chain swap framework
  - Ethereum HTLC contracts for both native ETH and ERC20
  - Python-based orchestration layer
  - Support for Bitcoin, Ethereum, and other chains

#### Move Language
- **MystenLabs awesome-move**: Generic "Offer" module for atomic swaps
  - Supports any pair of assets in the Move ecosystem
  - Leverages Move's resource safety for secure asset handling

- **SuiCross/Atomic Swap projects**: Cross-chain implementations between Sui and Ethereum
  - HTLC-based protocols ensuring atomicity
  - Automatic refund mechanisms
  - Modular architecture for multi-chain support

### 2.3 Cross-Chain Compatibility Requirements

For atomic swaps to work between two blockchains, both chains must support:
1. **Same hash function** (typically SHA-256 or Keccak-256)
2. **Time-lock operations** (relative or absolute)
3. **Ability to check preimage against hash**
4. **Conditional execution based on time**

### 2.4 Academic Research

- **"Universal Atomic Swaps"** (2021): Demonstrates secure exchange across all blockchain types
- **"Extending Atomic Cross-Chain Swaps"** (2019): Foundational research on cross-chain protocols
- **"4-Swap Protocol"** (2024): Addresses griefing and bribery attacks using four-transaction model

---

## 3. Hash Time Locked Contracts (HTLCs)

### 3.1 Core Mechanism

HTLCs combine two cryptographic primitives to create trustless escrow:

#### Hash Lock
Functions like two-factor authentication requiring the receiver to provide a secret preimage that hashes to a predetermined value. The preimage serves as cryptographic proof of intent to complete the swap.

**Example**:
```
hash_lock = SHA256(secret_preimage)
# Only someone with secret_preimage can unlock funds
```

#### Time Lock
Adds an expiration deadline. If the receiver doesn't claim funds before the deadline, the sender can reclaim them via refund.

**Example**:
```
if (current_time < timelock_expiry) {
    // Receiver can claim with secret
} else {
    // Sender can refund
}
```

### 3.2 Cross-Chain Atomic Swap Protocol

The typical flow involves 4 transactions across 2 chains:

**Setup Phase**:
1. Alice generates secret `S` and computes `H = hash(S)`
2. Alice creates HTLC on OL chain: "Lock 100 OL tokens for Bob, hashlock=H, timelock=48h"
3. Bob observes Alice's HTLC and verifies parameters
4. Bob creates HTLC on Ethereum: "Lock 1 ETH for Alice, hashlock=H, timelock=24h"

**Execution Phase**:
5. Alice observes Bob's HTLC and verifies it matches agreement
6. Alice withdraws from Bob's Ethereum HTLC by revealing secret `S`
7. Bob observes Alice's withdrawal, learns secret `S`
8. Bob withdraws from Alice's OL HTLC using the same secret `S`

**Why it's Atomic**:
- If Alice withdraws, she reveals `S`, allowing Bob to withdraw
- If Alice doesn't withdraw, Bob's timelock expires first (24h), Bob refunds
- Then Alice's timelock expires (48h), Alice refunds
- No scenario where only one party gets funds

### 3.3 Timelock Ordering (Critical!)

The timelock on Bob's contract MUST expire before Alice's contract:
- **Bob's timelock**: 24 hours (shorter)
- **Alice's timelock**: 48 hours (longer)

This prevents Alice from:
1. Withdrawing Bob's ETH (revealing secret)
2. Waiting for her own timelock to expire
3. Refunding her own OL tokens
4. Resulting in Alice getting both assets

### 3.4 Hash Function Selection

For cross-chain compatibility:
- **SHA-256**: Universal support, Bitcoin uses this
- **Keccak-256**: Ethereum native, but must be available on other chain
- **Recommendation for OL ↔ Ethereum**: Use SHA-256 since Move stdlib has `std::hash::sha2_256()` and Solidity has `sha256()`

---

## 4. Move Implementation Patterns

### 4.1 Move's Resource Safety Advantages

Move's linear type system provides inherent security for atomic swaps:
- **Resources cannot be copied or dropped**: Prevents asset duplication
- **Explicit transfer semantics**: Clear ownership tracking
- **Module-enforced invariants**: Compile-time safety guarantees

### 4.2 HTLC Module Structure (OL Chain)

```move
module ol_framework::atomic_swap {
    use std::hash;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};

    /// Represents a locked swap agreement
    struct SwapAgreement<phantom CoinType> has key {
        sender: address,
        receiver: address,
        amount: Coin<CoinType>,
        hash_lock: vector<u8>,  // SHA-256 hash of secret
        time_lock: u64,         // Unix timestamp
        withdrawn: bool,
        refunded: bool,
    }

    /// Initiator locks funds
    public entry fun new_swap<CoinType>(
        sender: &signer,
        receiver: address,
        amount: u64,
        hash_lock: vector<u8>,
        time_lock: u64,
    ) { /* ... */ }

    /// Receiver claims with secret preimage
    public entry fun withdraw<CoinType>(
        receiver: &signer,
        sender: address,
        preimage: vector<u8>,
    ) { /* ... */ }

    /// Sender reclaims after timelock
    public entry fun refund<CoinType>(
        sender: &signer,
        receiver: address,
    ) { /* ... */ }
}
```

### 4.3 Key Implementation Details

**Hash Verification**:
```move
let computed_hash = hash::sha2_256(preimage);
assert!(computed_hash == swap.hash_lock, E_INVALID_PREIMAGE);
```

**Timelock Verification**:
```move
let current_time = timestamp::now_seconds();
assert!(current_time >= swap.time_lock, E_TIME_LOCK_NOT_EXPIRED);
```

**State Management**:
```move
assert!(!swap.withdrawn, E_ALREADY_WITHDRAWN);
assert!(!swap.refunded, E_ALREADY_REFUNDED);
```

### 4.4 Move Testing Framework

Move provides native unit testing with these annotations:

```move
#[test(sender = @0x123, receiver = @0x456)]
fun test_successful_swap(sender: &signer, receiver: &signer) {
    // Setup
    timestamp::set_time_has_started_for_testing();

    // Create swap
    new_swap<AptosCoin>(sender, @0x456, 100, hash_lock, future_time);

    // Withdraw with correct preimage
    withdraw<AptosCoin>(receiver, @0x123, preimage);

    // Assert receiver got funds
    assert!(coin::balance<AptosCoin>(@0x456) == 100, 0);
}

#[test]
#[expected_failure(abort_code = E_INVALID_PREIMAGE)]
fun test_withdrawal_fails_with_wrong_preimage() {
    // Test that wrong preimage causes abort
}
```

**Running tests**:
```bash
aptos move test
```

### 4.5 Move Resources

- **Aptos Move Documentation**: https://aptos.dev/move/book/unit-testing/
- **awesome-move Generic Offer**: Reference implementation for asset swaps
- **Move Language Spec**: https://github.com/move-language/move

---

## 5. Solidity/EVM Implementation Patterns

### 5.1 Reference Implementation (chatch/hashed-timelock-contract-ethereum)

This battle-tested implementation provides the gold standard for Ethereum HTLCs:

**Core Contract Interface**:

```solidity
contract HashedTimelock {
    struct LockContract {
        address payable sender;
        address payable receiver;
        uint256 amount;
        bytes32 hashlock;
        uint256 timelock;
        bool withdrawn;
        bool refunded;
        bytes32 preimage;
    }

    mapping(bytes32 => LockContract) public contracts;

    function newContract(
        address payable _receiver,
        bytes32 _hashlock,
        uint256 _timelock
    ) external payable returns (bytes32 contractId) {
        require(msg.value > 0, "Amount must be > 0");
        require(_timelock > block.timestamp, "Timelock in past");

        contractId = keccak256(
            abi.encodePacked(msg.sender, _receiver, msg.value, _hashlock, _timelock)
        );

        contracts[contractId] = LockContract(
            payable(msg.sender),
            _receiver,
            msg.value,
            _hashlock,
            _timelock,
            false,
            false,
            0x0
        );
    }

    function withdraw(bytes32 _contractId, bytes32 _preimage)
        external
        returns (bool)
    {
        LockContract storage c = contracts[_contractId];
        require(c.receiver == msg.sender, "Not receiver");
        require(!c.withdrawn, "Already withdrawn");
        require(!c.refunded, "Already refunded");
        require(c.hashlock == sha256(abi.encodePacked(_preimage)), "Invalid preimage");

        c.preimage = _preimage;
        c.withdrawn = true;
        c.receiver.transfer(c.amount);

        return true;
    }

    function refund(bytes32 _contractId) external returns (bool) {
        LockContract storage c = contracts[_contractId];
        require(c.sender == msg.sender, "Not sender");
        require(!c.withdrawn, "Already withdrawn");
        require(!c.refunded, "Already refunded");
        require(block.timestamp >= c.timelock, "Timelock not expired");

        c.refunded = true;
        c.sender.transfer(c.amount);

        return true;
    }
}
```

### 5.2 ERC20 Variant

For token swaps, use `HashedTimelockERC20.sol`:

```solidity
function newContract(
    address _receiver,
    bytes32 _hashlock,
    uint256 _timelock,
    address _tokenContract,
    uint256 _amount
) external returns (bytes32) {
    IERC20 token = IERC20(_tokenContract);
    require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
    // ... rest similar to ETH version
}
```

### 5.3 Events for Observability

```solidity
event NewContract(
    bytes32 indexed contractId,
    address indexed sender,
    address indexed receiver,
    uint256 amount,
    bytes32 hashlock,
    uint256 timelock
);

event Withdrawn(bytes32 indexed contractId, bytes32 preimage);
event Refunded(bytes32 indexed contractId);
```

### 5.4 Gas Optimization Patterns

1. **Use `bytes32` for hashes** instead of `bytes` (fixed size, lower gas)
2. **Pack struct variables** to minimize storage slots
3. **Use `calldata` for function parameters** when not modifying
4. **Batch read operations** before state modifications
5. **Use events over storage** for historical data

---

## 6. Testing Architecture

### 6.1 Unit Testing Strategy

#### Move Unit Tests

**Location**: `framework/libra-framework/sources/ol_sources/tests/atomic_swap_tests.move`

**Test Coverage**:
```move
#[test_only]
module ol_framework::atomic_swap_tests {
    // 1. Successful swap flow
    #[test]
    fun test_successful_swap_flow() { }

    // 2. Invalid preimage rejection
    #[test]
    #[expected_failure(abort_code = E_INVALID_PREIMAGE)]
    fun test_rejects_invalid_preimage() { }

    // 3. Timelock enforcement
    #[test]
    #[expected_failure(abort_code = E_TIME_LOCK_NOT_EXPIRED)]
    fun test_refund_before_timelock_fails() { }

    // 4. Double withdrawal prevention
    #[test]
    #[expected_failure(abort_code = E_ALREADY_WITHDRAWN)]
    fun test_prevents_double_withdrawal() { }

    // 5. Unauthorized access
    #[test]
    #[expected_failure]
    fun test_only_receiver_can_withdraw() { }

    // 6. Refund after timelock
    #[test]
    fun test_sender_can_refund_after_timelock() { }
}
```

**Running**:
```bash
cd framework/libra-framework
libra move test --filter atomic_swap
```

#### Solidity Unit Tests (Foundry)

**Location**: `contracts/test/AtomicSwap.t.sol`

**Test Coverage**:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/HashedTimelock.sol";

contract HashedTimelockTest is Test {
    HashedTimelock htlc;
    address alice = address(0x1);
    address bob = address(0x2);

    bytes32 secret = keccak256("my_secret");
    bytes32 hashlock = sha256(abi.encodePacked(secret));

    function setUp() public {
        htlc = new HashedTimelock();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function testSuccessfulSwap() public {
        vm.prank(alice);
        bytes32 contractId = htlc.newContract{value: 1 ether}(
            payable(bob),
            hashlock,
            block.timestamp + 1 hours
        );

        vm.prank(bob);
        htlc.withdraw(contractId, secret);

        assertEq(bob.balance, 11 ether);
    }

    function testRefundAfterTimelock() public {
        vm.prank(alice);
        bytes32 contractId = htlc.newContract{value: 1 ether}(
            payable(bob),
            hashlock,
            block.timestamp + 1 hours
        );

        vm.warp(block.timestamp + 2 hours);

        vm.prank(alice);
        htlc.refund(contractId);

        assertEq(alice.balance, 10 ether);
    }

    function testFailWrongPreimage() public {
        vm.prank(alice);
        bytes32 contractId = htlc.newContract{value: 1 ether}(
            payable(bob),
            hashlock,
            block.timestamp + 1 hours
        );

        bytes32 wrongSecret = keccak256("wrong");
        vm.prank(bob);
        htlc.withdraw(contractId, wrongSecret); // Should fail
    }
}
```

**Running**:
```bash
cd contracts
forge test -vvv
```

### 6.2 Functional Testing

#### Move Functional Tests

Use the libra-smoke-tests framework:

```rust
// smoke-tests/tests/atomic_swap_flow.rs
#[tokio::test]
async fn test_atomic_swap_on_ol_chain() -> anyhow::Result<()> {
    let mut swarm = LibraSmoke::new(Some(1), None).await?;

    // Setup alice and bob accounts
    let alice = swarm.get_account(0);
    let bob = swarm.new_account()?;

    // Alice creates swap
    let secret = b"my_secret_preimage";
    let hash_lock = sha256(secret);
    let time_lock = now() + 3600; // 1 hour

    swarm.create_atomic_swap(
        &alice,
        bob.address(),
        100_000_000, // 100 OL tokens
        hash_lock,
        time_lock,
    ).await?;

    // Bob withdraws with secret
    swarm.withdraw_atomic_swap(
        &bob,
        alice.address(),
        secret,
    ).await?;

    // Verify bob received funds
    let balance = swarm.get_balance(bob.address()).await?;
    assert_eq!(balance, 100_000_000);

    Ok(())
}
```

#### Solidity Functional Tests (Hardhat Scripts)

```javascript
// test/integration/atomic-swap-flow.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Atomic Swap Flow", function() {
  it("Should complete full swap cycle", async function() {
    const [alice, bob] = await ethers.getSigners();
    const HTLC = await ethers.getContractFactory("HashedTimelock");
    const htlc = await HTLC.deploy();

    const secret = ethers.utils.formatBytes32String("my_secret");
    const hashlock = ethers.utils.sha256(secret);
    const timelock = Math.floor(Date.now() / 1000) + 3600;

    // Alice creates contract
    const tx = await htlc.connect(alice).newContract(
      bob.address,
      hashlock,
      timelock,
      { value: ethers.utils.parseEther("1.0") }
    );
    const receipt = await tx.wait();
    const contractId = receipt.events[0].args.contractId;

    // Bob withdraws
    await htlc.connect(bob).withdraw(contractId, secret);

    // Verify withdrawal
    const contract = await htlc.contracts(contractId);
    expect(contract.withdrawn).to.be.true;
  });
});
```

### 6.3 End-to-End Testing with Docker Compose

#### Architecture

```
docker-compose.yml
├── ol-testnet (libra smoke)
├── eth-testnet (anvil/geth)
├── swap-orchestrator (CLI tool)
└── monitoring (logs/events)
```

#### Docker Compose Configuration

```yaml
version: '3.8'

services:
  # OL Testnet
  ol-node:
    build:
      context: .
      dockerfile: testnet/Dockerfile
    environment:
      - DIEM_FORGE_NODE_BIN_PATH=/usr/local/bin/libra
    ports:
      - "8080:8080"  # REST API
    volumes:
      - ol-data:/opt/libra/data
    command: libra ops testnet smoke

  # Ethereum Testnet (Anvil)
  eth-node:
    image: ghcr.io/foundry-rs/foundry:latest
    ports:
      - "8545:8545"
    command: >
      anvil
      --host 0.0.0.0
      --accounts 10
      --balance 10000

  # Contract Deployment
  deploy-contracts:
    build:
      context: ./contracts
      dockerfile: Dockerfile
    depends_on:
      - eth-node
    environment:
      - ETH_RPC_URL=http://eth-node:8545
    command: forge script script/Deploy.s.sol --broadcast --rpc-url $ETH_RPC_URL

  # E2E Test Runner
  e2e-tests:
    build:
      context: ./e2e
      dockerfile: Dockerfile
    depends_on:
      - ol-node
      - eth-node
      - deploy-contracts
    environment:
      - OL_RPC_URL=http://ol-node:8080
      - ETH_RPC_URL=http://eth-node:8545
    volumes:
      - ./e2e/tests:/tests
    command: pytest /tests -v

volumes:
  ol-data:
```

#### E2E Test Script

```python
# e2e/tests/test_cross_chain_swap.py
import pytest
import hashlib
import time
from web3 import Web3
from ol_client import OLClient

@pytest.fixture
def setup():
    # Connect to both chains
    ol = OLClient("http://ol-node:8080")
    eth = Web3(Web3.HTTPProvider("http://eth-node:8545"))

    # Get test accounts
    alice_ol = ol.get_account("alice")
    bob_ol = ol.get_account("bob")
    alice_eth = eth.eth.accounts[0]
    bob_eth = eth.eth.accounts[1]

    return {
        "ol": ol,
        "eth": eth,
        "alice_ol": alice_ol,
        "bob_ol": bob_ol,
        "alice_eth": alice_eth,
        "bob_eth": bob_eth,
    }

def test_alice_bob_atomic_swap(setup):
    """
    Alice wants 1 ETH from Bob
    Bob wants 100 OL from Alice
    """
    ol = setup["ol"]
    eth = setup["eth"]

    # 1. Generate secret
    secret = b"my_secret_preimage_12345"
    hash_lock = hashlib.sha256(secret).digest()

    # 2. Alice locks 100 OL for Bob (48h timelock)
    alice_timelock = int(time.time()) + (48 * 3600)
    alice_tx = ol.create_swap(
        sender=setup["alice_ol"],
        receiver=setup["bob_ol"].address,
        amount=100_000_000,
        hash_lock=hash_lock,
        timelock=alice_timelock
    )
    assert alice_tx.success

    # 3. Bob observes and locks 1 ETH for Alice (24h timelock)
    bob_timelock = int(time.time()) + (24 * 3600)
    htlc = eth.eth.contract(address=HTLC_ADDRESS, abi=HTLC_ABI)

    bob_tx = htlc.functions.newContract(
        setup["alice_eth"],
        hash_lock,
        bob_timelock
    ).transact({
        'from': setup["bob_eth"],
        'value': eth.toWei(1, 'ether')
    })
    eth.eth.wait_for_transaction_receipt(bob_tx)

    # 4. Alice withdraws from Ethereum (reveals secret)
    contract_id = get_contract_id(bob_tx)
    alice_withdraw = htlc.functions.withdraw(
        contract_id,
        secret
    ).transact({'from': setup["alice_eth"]})
    eth.eth.wait_for_transaction_receipt(alice_withdraw)

    # 5. Bob learns secret from Ethereum event
    events = htlc.events.Withdrawn().getLogs()
    revealed_secret = events[-1]['args']['preimage']
    assert revealed_secret == secret

    # 6. Bob withdraws from OL using secret
    bob_withdraw = ol.withdraw_swap(
        receiver=setup["bob_ol"],
        sender=setup["alice_ol"].address,
        preimage=secret
    )
    assert bob_withdraw.success

    # 7. Verify final balances
    alice_eth_balance = eth.eth.get_balance(setup["alice_eth"])
    bob_ol_balance = ol.get_balance(setup["bob_ol"].address)

    assert alice_eth_balance >= eth.toWei(1, 'ether')
    assert bob_ol_balance >= 100_000_000
```

**Running E2E Tests**:
```bash
docker-compose up --build
# Tests run automatically and output results
docker-compose logs e2e-tests
```

---

## 7. Development Environment Setup

### 7.1 OL (Move) Development

**Already Available** in this repository:

```bash
# Build Move framework
cd framework
libra move framework release

# Run Move tests
cd framework/libra-framework
libra move test

# Start local testnet
libra ops testnet smoke
```

**Key Tools**:
- **libra CLI**: Transaction submission, testnet management
- **Move compiler**: Built into libra binary
- **LibraSmoke**: Integration test framework (in `smoke-tests/`)

### 7.2 Solidity/EVM Development

**Recommended: Foundry** (Fast, Solidity-native testing)

**Installation**:
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Create new project
mkdir contracts && cd contracts
forge init

# Project structure
contracts/
├── src/
│   ├── HashedTimelock.sol
│   └── HashedTimelockERC20.sol
├── test/
│   ├── HashedTimelock.t.sol
│   └── HashedTimelockERC20.t.sol
├── script/
│   └── Deploy.s.sol
└── foundry.toml
```

**foundry.toml**:
```toml
[profile.default]
src = 'src'
out = 'out'
libs = ['lib']
solc_version = '0.8.20'
optimizer = true
optimizer_runs = 200

[rpc_endpoints]
localhost = "http://localhost:8545"
```

**Key Commands**:
```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Build contracts
forge build

# Run tests
forge test -vvv

# Run specific test
forge test --match-test testSuccessfulSwap -vvv

# Deploy to local
forge script script/Deploy.s.sol --rpc-url localhost --broadcast

# Gas report
forge test --gas-report
```

**Alternative: Hardhat** (JavaScript/TypeScript ecosystem)

```bash
npm install --save-dev hardhat
npx hardhat init

# Useful for:
# - JS/TS integration tests
# - Frontend integration
# - Complex deployment scripts
```

### 7.3 Docker Compose Orchestration

**Directory Structure**:
```
atomic-swap/
├── contracts/           # Solidity contracts (Foundry)
├── framework/          # Move modules (existing OL framework)
├── e2e/               # End-to-end tests
│   ├── tests/
│   ├── clients/       # Python/JS clients for both chains
│   └── Dockerfile
├── testnet/           # OL testnet config
│   └── Dockerfile
└── docker-compose.yml
```

**OL Testnet Dockerfile**:
```dockerfile
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential

# Copy libra binary
COPY target/release/libra /usr/local/bin/libra
COPY framework/releases/head.mrb /opt/libra/head.mrb

# Expose ports
EXPOSE 8080

# Start testnet
CMD ["libra", "ops", "testnet", "smoke"]
```

### 7.4 Recommended Project Structure

```
atomic-swap-ol-eth/
├── move/
│   └── sources/
│       ├── atomic_swap.move
│       └── tests/
│           └── atomic_swap_tests.move
│
├── contracts/
│   ├── src/
│   │   ├── HashedTimelock.sol
│   │   └── HashedTimelockERC20.sol
│   ├── test/
│   │   └── HashedTimelock.t.sol
│   └── script/
│       └── Deploy.s.sol
│
├── e2e/
│   ├── tests/
│   │   └── test_cross_chain_swap.py
│   ├── clients/
│   │   ├── ol_client.py
│   │   └── eth_client.py
│   └── pytest.ini
│
├── cli/
│   └── swap-cli.py  # User-facing CLI for initiating swaps
│
├── docker-compose.yml
├── Makefile
└── README.md
```

---

## 8. Security Considerations

### 8.1 Attack Vectors

#### 1. Griefing Attacks
**Threat**: Initiator locks funds, then counterparty abandons swap, forcing initiator to wait for refund timelock.

**Mitigation**:
- Use reasonable timelocks (24-48 hours max)
- Off-chain reputation systems for swap partners
- Require small "good faith" deposit before revealing contract details

#### 2. Bribery/Miner Attacks
**Threat**: Malicious party bribes miners to censor claim transaction until refund timelock expires.

**Mitigation**:
- Use sufficient timelock buffer (Bob's timelock < Alice's timelock by 24h minimum)
- Monitor mempool for censorship
- Use flashbots or private transaction pools for high-value swaps
- Consider 4-Swap protocol variant for critical applications

#### 3. Front-Running
**Threat**: Attacker observes withdraw transaction with secret, submits own withdraw with higher gas.

**Mitigation**:
- **This is actually OK!** Only the designated receiver address can withdraw in proper implementation
- Ensure `require(msg.sender == receiver)` in Solidity
- Ensure `assert!(signer::address_of(receiver) == swap.receiver)` in Move

#### 4. Timelock Manipulation
**Threat**: Attacker sets timelock in past or too far in future.

**Mitigation**:
```solidity
require(_timelock > block.timestamp, "Timelock in past");
require(_timelock < block.timestamp + 30 days, "Timelock too far");
```

```move
assert!(time_lock > timestamp::now_seconds(), E_TIMELOCK_IN_PAST);
assert!(time_lock < timestamp::now_seconds() + (30 * 24 * 3600), E_TIMELOCK_TOO_FAR);
```

#### 5. Reentrancy (Solidity-specific)
**Threat**: Malicious contract calls back into HTLC during fund transfer.

**Mitigation**:
- Use checks-effects-interactions pattern
- Set `withdrawn = true` BEFORE transfer
- Use ReentrancyGuard from OpenZeppelin
- Or use `transfer()` which limits gas (safer than `call.value()`)

```solidity
function withdraw(bytes32 _contractId, bytes32 _preimage) external {
    LockContract storage c = contracts[_contractId];

    // Checks
    require(c.receiver == msg.sender, "Not receiver");
    require(!c.withdrawn, "Already withdrawn");
    require(c.hashlock == sha256(abi.encodePacked(_preimage)), "Invalid preimage");

    // Effects (state change BEFORE external call)
    c.withdrawn = true;
    c.preimage = _preimage;

    // Interactions (external call LAST)
    c.receiver.transfer(c.amount);
}
```

#### 6. Integer Overflow/Underflow
**Threat**: Arithmetic operations cause unexpected values.

**Mitigation**:
- **Solidity >= 0.8.0**: Built-in overflow protection
- **Move**: Natural overflow protection via type system
- Still validate all inputs explicitly

#### 7. Hash Collision
**Threat**: Attacker finds different preimage with same hash.

**Mitigation**:
- Use SHA-256 (256-bit security, collision-resistant)
- Require preimages to be exactly 32 bytes
- Never reuse the same secret for multiple swaps

#### 8. Timelock Ordering Violation
**Threat**: Alice's timelock expires before Bob's.

**Mitigation**:
```python
# Enforce ordering at application level
BOB_TIMELOCK = 24 * 3600  # 24 hours
ALICE_TIMELOCK = 48 * 3600  # 48 hours
assert ALICE_TIMELOCK > BOB_TIMELOCK + (6 * 3600)  # At least 6h buffer
```

### 8.2 Security Best Practices

1. **Audit Contracts**: Get professional smart contract audit before mainnet
2. **Formal Verification**: Use Move prover for Move contracts, consider Certora for Solidity
3. **Bug Bounty**: Offer rewards for finding vulnerabilities
4. **Gradual Rollout**: Start with small value limits, increase over time
5. **Monitor Events**: Watch for unusual patterns (many refunds, specific addresses)
6. **Emergency Pause**: Consider admin pause for initial deployment (remove later)
7. **Immutable Core**: Once battle-tested, make contracts immutable

### 8.3 Testing for Security

```move
// Test: Prevent receiver address spoofing
#[test]
#[expected_failure(abort_code = E_NOT_RECEIVER)]
fun test_wrong_receiver_cannot_withdraw() {
    let attacker = @0x999;
    withdraw<AptosCoin>(attacker, @alice, correct_preimage);
}

// Test: Prevent timelock manipulation
#[test]
#[expected_failure(abort_code = E_TIMELOCK_IN_PAST)]
fun test_cannot_create_swap_with_past_timelock() {
    new_swap<AptosCoin>(sender, receiver, 100, hash, 0);
}
```

```solidity
// Test: Reentrancy protection
function testReentrancyProtection() public {
    MaliciousReceiver attacker = new MaliciousReceiver(htlc);

    bytes32 contractId = htlc.newContract{value: 1 ether}(
        payable(address(attacker)),
        hashlock,
        block.timestamp + 1 hours
    );

    // Attacker tries to reenter
    vm.expectRevert("Already withdrawn");
    attacker.attack(contractId, secret);
}
```

---

## 9. MVP Evaluation Roadmap

The goal is to build **minimal viable prototypes** of the most promising approaches to evaluate their trade-offs empirically, not to build production systems. Each MVP should take 1-2 weeks and demonstrate core mechanics.

### Evaluation Criteria

For each approach, we will measure:
1. **Implementation Complexity**: Lines of code, ease of development
2. **Fair Market Behavior**: Can price manipulation be prevented?
3. **Capital Efficiency**: How long are funds locked?
4. **User Experience**: Steps required, time to completion
5. **Decentralization**: Trust assumptions, centralization points
6. **Cross-Chain Viability**: Does it actually work for OL ↔ ETH?

---

### MVP 1: Pure HTLC (Baseline) - Week 1-2

**Goal**: Establish baseline for comparison. Simplest trustless approach.

**Scope**:
- [ ] Basic Move HTLC module on OL (new_swap, withdraw, refund)
- [ ] Basic Solidity HTLC contract on Ethereum
- [ ] Single successful cross-chain swap test (manual coordination)
- [ ] Measure timelock duration, capital lockup

**Implementation**:
```
framework/libra-framework/sources/ol_sources/
└── atomic_swap_htlc.move (200 lines)

contracts/
├── src/HashedTimelock.sol (150 lines)
└── test/HashedTimelock.t.sol (100 lines)
```

**Test Scenario**:
- Alice locks 100 OL (48h timelock)
- Bob locks 1 ETH (24h timelock)
- Alice withdraws ETH (reveals secret)
- Bob withdraws OL (uses secret)

**Deliverables**:
- Working HTLC contracts on both chains
- Script to execute manual swap
- Report: time to completion, capital efficiency, UX pain points

**Findings Expected**:
- ✅ Fully trustless
- ❌ Long capital lockup (24-48h)
- ❌ Poor UX (4 manual transactions)
- ❌ No price manipulation protection

---

### MVP 2: HTLC + Orderbook (Price-Time Priority) - Week 3-4

**Goal**: Evaluate fair market enforcement. Can we prevent price manipulation?

**Scope**:
- [ ] Extend HTLC module with orderbook structure
- [ ] Implement price-time priority matching
- [ ] Test: User cannot bypass better prices
- [ ] Test: Wash trading prevented

**Implementation**:
```move
module ol_framework::atomic_swap_orderbook {
    struct OrderBook has key {
        sell_orders: vector<Order>,  // Sorted by price ASC, time ASC
    }

    // Users submit orders, cannot choose counterparty
    public entry fun create_limit_order(...)
    public entry fun create_market_order(...)

    // Matching enforces best price
    fun match_orders(...): vector<Match>
}
```

**Test Scenarios**:
1. **Price Priority**: Order A @ 1.05 ETH, Order B @ 1.00 ETH → Market order matches A first
2. **Time Priority**: Two orders at same price → Earlier order matched first
3. **Manipulation Prevention**: Attempt to match with worse order → Transaction fails
4. **Partial Fills**: Large order matches multiple smaller orders

**Deliverables**:
- Orderbook Move module with tests
- Report comparing to MVP 1: complexity increase vs manipulation protection

**Findings Expected**:
- ✅ Prevents price manipulation
- ✅ Fair market behavior guaranteed
- ⚠️  Increased complexity (~500 lines vs 200)
- ⚠️  Requires active orderbook management
- ❓ Capital efficiency vs MVP 1?

---

### MVP 3: Intent + Solver (Simple RFQ) - Week 5-6

**Goal**: Evaluate intent-based UX. Can we improve user experience significantly?

**Scope**:
- [ ] Intent signature format (off-chain)
- [ ] Simple solver that monitors intents
- [ ] Solver fulfills intent, claims funds with proof
- [ ] Compare UX to HTLC approach

**Architecture**:
```
User → Signs Intent (off-chain)
     → Posts to intent mempool

Solver → Monitors mempool
       → Sends ETH to user immediately
       → Submits intent + proof to OL chain
       → Claims OL tokens
```

**Implementation**:
```move
module ol_framework::intent_swap {
    struct Intent has drop {
        user: address,
        sell_amount: u64,
        min_receive: u64,
        nonce: u64,
        signature: vector<u8>,
    }

    // Solver claims funds by proving they fulfilled intent
    public entry fun claim_with_intent(
        solver: &signer,
        intent: Intent,
        eth_tx_hash: vector<u8>,  // Proof of ETH transfer (simplified)
    )
}
```

**Challenge**: Cross-chain proof
- **MVP Approach**: Solver self-reports (trusted for MVP evaluation only)
- **Note**: Real implementation would need ZK proof or optimistic bridge

**Test Scenarios**:
1. User signs intent, solver fills immediately
2. Measure time from intent to completion
3. Compare to HTLC 4-transaction flow

**Deliverables**:
- Intent format specification
- Simple solver (Python script)
- UX comparison report

**Findings Expected**:
- ✅ Better UX (1 signature vs 4 transactions)
- ✅ Fast completion (minutes vs hours)
- ❌ Requires solver infrastructure
- ❌ Trust assumption (in MVP; solvable with ZK)
- ❓ Can we enforce best execution?

---

### MVP 4: Batch Auction (CoW-style) - Week 7-8

**Goal**: Evaluate MEV protection and uniform clearing price benefits.

**Scope**:
- [ ] Batch collection mechanism (30s windows)
- [ ] Simple solver that finds clearing price
- [ ] Demonstrate uniform pricing (all users get same price)
- [ ] Test MEV resistance

**Implementation**:
```move
module ol_framework::batch_auction {
    struct Batch has key {
        batch_id: u64,
        submission_end: u64,
        intents: vector<Intent>,
        clearing_price: Option<u64>,
    }

    public entry fun submit_to_batch(user: &signer, ...)

    public entry fun solve_batch(
        solver: &signer,
        batch_id: u64,
        clearing_price: u64,
        matches: vector<Match>,
    )
}
```

**Test Scenarios**:
1. **Uniform Pricing**: Alice wants 1.00 ETH, Bob wants 1.05 ETH → Both get 1.02 ETH (clearing)
2. **CoW Matching**: Alice sells OL→ETH, Bob sells ETH→OL → Direct match
3. **MEV Protection**: All participants in batch get same price (no sandwich attacks)

**Deliverables**:
- Batch auction module
- Simple solver (finds clearing price)
- MEV resistance analysis

**Findings Expected**:
- ✅ MEV protection (uniform clearing)
- ✅ Prevents manipulation (can't select worse price)
- ⚠️  Latency (wait for batch window)
- ⚠️  Solver complexity (optimization problem)
- ❓ Better execution than orderbook?

---

### MVP 5: Dutch Auction (UniswapX-style) - Week 9-10

**Goal**: Evaluate if auction mechanism provides both speed AND fair pricing.

**Scope**:
- [ ] Dutch auction intent format
- [ ] Price decay function
- [ ] Solver competition (multiple solvers)
- [ ] Measure execution speed and price quality

**Implementation**:
```move
module ol_framework::dutch_auction {
    struct DutchIntent has key {
        trader: address,
        sell_amount: u64,
        start_price: u64,    // Best hoped-for price
        end_price: u64,      // Minimum acceptable
        decay_start: u64,
        decay_duration: u64,
    }

    public fun current_price(intent: &DutchIntent): u64 {
        // Linear decay: price(t) = start - (start - end) * elapsed / duration
    }

    public entry fun fill_dutch_order(solver: &signer, intent_id: u64)
}
```

**Test Scenarios**:
1. Intent starts at 1.05 ETH, decays to 0.95 ETH over 2 minutes
2. Solver fills at 1.02 ETH (30 seconds elapsed)
3. Compare speed vs batch auction, price vs orderbook

**Deliverables**:
- Dutch auction module
- Multi-solver simulation
- Speed vs price quality analysis

**Findings Expected**:
- ✅ Fast execution (solver competition)
- ✅ Fair pricing (auction mechanism)
- ✅ No manipulation (can't bypass auction)
- ⚠️  Solver dependency
- ❓ Better than batch auction?

---

### MVP 6: ZK Light Client Proof-of-Concept - Week 11-12

**Goal**: Evaluate feasibility of ZK proofs for cross-chain verification. Is this practical?

**Scope**:
- [ ] Generate ZK proof of Ethereum transaction inclusion
- [ ] Verify proof on OL chain (or in tests)
- [ ] Measure proof generation time and cost
- [ ] Assess implementation complexity

**Approach** (using existing ZK libraries):
```
Option 1: Use Succinct Labs' Telepathy (if available)
Option 2: Use Axiom for Ethereum historical data
Option 3: Simple Merkle proof + Plonky2 (minimal)
```

**Test Scenario**:
1. Alice sends ETH on Ethereum
2. Generate ZK proof: "Transaction T exists in block B"
3. Submit proof to OL Move module
4. Verify proof, release OL tokens

**Deliverables**:
- Proof generation script
- Verification in Move or Rust tests
- Feasibility report: time, cost, complexity

**Findings Expected**:
- ❓ Proof generation time: seconds? minutes?
- ❓ Complexity: can we realistically build this?
- ❓ Cost: computational requirements?
- ✅ If feasible: eliminates timelock delays
- ✅ If feasible: no trust assumptions

---

### Evaluation Matrix

After all MVPs, compare approaches:

| Approach | Complexity | Fair Markets | Capital Eff. | UX | Decentralization | Viability |
|----------|------------|--------------|--------------|-----|------------------|-----------|
| **Pure HTLC** | ⭐ Simple | ❌ No protection | ❌ Low | ⚠️  Manual | ✅ Full | ✅ Ready |
| **HTLC + Orderbook** | ⭐⭐ Moderate | ✅ Enforced | ⚠️  Medium | ⭐⭐ Good | ✅ Full | ✅ Ready |
| **Intent + Solver** | ⭐⭐ Moderate | ❓ TBD | ✅ High | ⭐⭐⭐ Excellent | ⚠️  Solver | ⚠️  Needs proof |
| **Batch Auction** | ⭐⭐⭐ Complex | ✅ Uniform price | ✅ High | ⚠️  Latency | ⚠️  Solver | ⚠️  Needs proof |
| **Dutch Auction** | ⭐⭐ Moderate | ✅ Auction | ✅ High | ⭐⭐⭐ Fast | ⚠️  Solver | ⚠️  Needs proof |
| **ZK Proofs** | ⭐⭐⭐⭐ Very Complex | N/A (orthogonal) | ✅ Highest | ⭐⭐⭐ Fast | ✅ Full | ❓ Feasibility? |

### Decision Framework

After MVP evaluation, choose approach based on:

**If ZK proofs are practical** (MVP 6 succeeds):
- **Winner**: Dutch Auction + ZK proofs
- Best UX + Fair markets + No trust assumptions

**If ZK proofs are too complex** (MVP 6 fails):
- **Winner**: HTLC + Orderbook (price-time priority)
- Battle-tested + Fair markets + Fully decentralized

**Hybrid Strategy** (if resources allow):
- Launch: HTLC + Orderbook (safe, proven)
- Phase 2: Add Dutch Auction mode (better UX)
- Phase 3: Integrate ZK when mature

### MVP Development Guidelines

For each MVP:
1. **Time-box**: Maximum 2 weeks
2. **Minimal**: Only core mechanics, no polish
3. **Testnet only**: No security audit needed
4. **Document findings**: What worked? What didn't?
5. **Quantitative metrics**: Measure time, costs, complexity
6. **Compare**: Always compare to baseline (MVP 1)

### Project Structure

```
atomic-swap-mvps/
├── mvp1-htlc/
│   ├── move/atomic_swap_htlc.move
│   ├── solidity/HashedTimelock.sol
│   ├── tests/
│   └── FINDINGS.md
│
├── mvp2-orderbook/
│   ├── move/atomic_swap_orderbook.move
│   ├── tests/
│   └── FINDINGS.md
│
├── mvp3-intent/
│   ├── move/intent_swap.move
│   ├── solver/simple_solver.py
│   └── FINDINGS.md
│
├── mvp4-batch/
│   ├── move/batch_auction.move
│   ├── solver/batch_solver.py
│   └── FINDINGS.md
│
├── mvp5-dutch/
│   ├── move/dutch_auction.move
│   ├── solver/dutch_solver.py
│   └── FINDINGS.md
│
└── mvp6-zk/
    ├── prover/generate_proof.rs
    ├── verifier/verify.move
    └── FINDINGS.md
```

### Success Criteria

By end of 12 weeks, we should be able to answer:
1. ✅ Which approach best prevents price manipulation?
2. ✅ Which approach has best UX vs security trade-off?
3. ✅ Are ZK proofs practical for OL ↔ ETH today?
4. ✅ What's the minimum viable architecture for launch?
5. ✅ What should the long-term evolution path be?

**Output**: Data-driven decision on which approach to build for production.

---

## 11. Asymmetric Chain Architecture: OL as Coordinator, EVM as Escrow

A more practical and efficient design is to have **OL chain handle all business logic** (orderbook, matching, price discovery) while **EVM chain does minimal work** (escrow, release, proof verification). This leverages each chain's strengths.

### 11.1 Design Rationale

**Why OL should be the coordinator:**
1. **Move's safety**: Resource model prevents errors in complex orderbook logic
2. **Native support**: OL framework can add atomic swap as first-class feature
3. **Lower gas costs**: Move execution cheaper than Solidity for complex logic
4. **Single source of truth**: One chain manages orderbook state
5. **Easier upgrades**: Update business logic on OL without touching EVM

**Why EVM should be minimal:**
1. **Gas costs**: Ethereum gas is expensive, minimize operations
2. **Simplicity**: Less code = easier audits, fewer bugs
3. **Immutability**: Simple escrow less likely to need upgrades
4. **Multi-chain**: Same simple EVM contract works for all EVM chains

### 11.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      OL Chain (Coordinator)                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Orderbook Module                                   │    │
│  │  - Price-time priority matching                     │    │
│  │  - Dutch auction management                         │    │
│  │  - Batch auction coordination                       │    │
│  │  - Fair market enforcement                          │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Swap Coordination Module                           │    │
│  │  - Match buyers and sellers                         │    │
│  │  - Generate swap instructions                       │    │
│  │  - Verify EVM proofs                                │    │
│  │  - Release OL tokens                                │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  ZK Verifier Module                                 │    │
│  │  - Verify Ethereum transaction proofs               │    │
│  │  - Confirm ETH was sent to user                     │    │
│  │  - Trigger OL token release                         │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ ZK Proofs
                            │
┌───────────────────────────┴─────────────────────────────────┐
│                   Ethereum Chain (Escrow)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Minimal Escrow Contract (~100 lines)              │    │
│  │                                                      │    │
│  │  function deposit(address recipient, bytes32 swapId)│    │
│  │  function release(bytes32 swapId, bytes proof)      │    │
│  │  function refund(bytes32 swapId)  // timeout only   │    │
│  │                                                      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 11.3 Protocol Flow with Pre-Funding (Corrected)

#### Scenario: Alice (OL) wants ETH, Bob (ETH) wants OL

**Important**: Bob must **pre-fund** his ETH into the escrow contract **before** he can submit orders on OL. This ensures instant settlement and prevents Bob from matching orders without having funds available.

**Critical Design Decision**: The protocol uses a **two-phase unlock** pattern to avoid circular dependency:
1. Alice locks ETH on Ethereum by proving the match happened on OL
2. Bob unlocks OL on OL by proving Alice locked ETH on Ethereum
3. Alice finalizes by claiming the locked ETH after Bob receives OL

**Phase 0: Bob Pre-Funds ETH (Ethereum Chain)**
```solidity
// Bob deposits ETH into escrow BEFORE creating orders
contract AtomicSwapEscrow {
    mapping(address => uint256) public balances;
    mapping(address => bytes32[]) public depositNonces;

    // Bob deposits ETH to make it available for swaps
    function depositFunds() external payable {
        require(msg.value > 0, "No ETH sent");
        balances[msg.sender] += msg.value;

        emit FundsDeposited(msg.sender, msg.value, balances[msg.sender]);
    }

    // Bob can withdraw unused funds
    function withdrawFunds(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);

        emit FundsWithdrawn(msg.sender, amount);
    }
}
```

**Phase 1: Bob Registers on OL (with proof of deposit)**
```move
// Bob submits ZK proof of his ETH deposit balance
public entry fun register_eth_funds(
    bob: &signer,
    eth_address: vector<u8>,
    eth_balance_proof: vector<u8>,  // ZK proof of Bob's CURRENT balance on Ethereum
) {
    let bob_addr = signer::address_of(bob);

    // Verify ZK proof of Bob's current Ethereum balance
    let verified_balance = zk_verifier::verify_eth_balance(
        eth_address,
        eth_balance_proof
    );
    assert!(verified_balance > 0, E_INVALID_BALANCE_PROOF);

    // Update Bob's tracked ETH balance (or create new)
    if (!exists<ETHBalance>(bob_addr)) {
        move_to(bob, ETHBalance {
            eth_address,
            available: verified_balance,
            locked: 0,
            nonce: 0,
            last_updated: timestamp::now_seconds(),
        });
    } else {
        let balance = borrow_global_mut<ETHBalance>(bob_addr);
        // Only update if balance increased (prevents old proofs)
        assert!(verified_balance >= balance.available + balance.locked, E_BALANCE_DECREASED);
        balance.available = verified_balance - balance.locked;
        balance.last_updated = timestamp::now_seconds();
    }
}
```

**Note**: To prevent Bob from withdrawing ETH after registration, the system needs periodic balance revalidation or withdrawal lockup periods. See Research Questions section.

**Phase 2: Alice Submits Sell Order (OL Chain)**
```move
// Alice submits limit order on OL
public entry fun create_sell_order(
    alice: &signer,
    ol_amount: u64,      // 100 OL
    min_eth: u64,        // Minimum 0.95 ETH
    eth_recipient: vector<u8>,  // Alice's Ethereum address
) acquires OrderBook {
    let alice_addr = signer::address_of(alice);

    // Lock Alice's OL tokens in module escrow
    let coins = coin::withdraw<LibraCoin>(alice, ol_amount);

    // Create order with escrowed coins
    let order_id = generate_order_id();
    let order = Order {
        order_id,
        trader: alice_addr,
        ol_amount,
        escrowed_coins: coins,  // Coins stored in order
        min_eth,
        eth_recipient,
        status: OPEN,
        created_at: timestamp::now_seconds(),
    };

    // Add to orderbook
    let orderbook = borrow_global_mut<OrderBook>(@ol_framework);
    table::add(&mut orderbook.orders, order_id, order);
    orderbook::insert_sorted(&mut orderbook.sell_orders, order_id);
}
```

**Phase 3: Bob Submits Buy Order & Matches (OL Chain)**
```move
// Bob's buy order matches Alice's sell order
public entry fun create_buy_order(
    bob: &signer,
    eth_amount: u64,     // Bob offers 1.0 ETH
    max_ol_price: u64,   // Maximum OL per ETH willing to pay
) acquires ETHBalance, OrderBook, SwapRegistry {
    let bob_addr = signer::address_of(bob);

    // CRITICAL: Verify Bob has sufficient pre-funded ETH
    assert!(exists<ETHBalance>(bob_addr), E_NO_ETH_BALANCE);
    let bob_balance = borrow_global_mut<ETHBalance>(bob_addr);
    assert!(bob_balance.available >= eth_amount, E_INSUFFICIENT_ETH);

    // Find best matching sell order (price-time priority)
    let orderbook = borrow_global_mut<OrderBook>(@ol_framework);
    let alice_order = orderbook::match_best_sell_order(&mut orderbook, eth_amount, max_ol_price);

    // Lock Bob's ETH balance (prevent double-spending)
    bob_balance.available = bob_balance.available - eth_amount;
    bob_balance.locked = bob_balance.locked + eth_amount;

    // Extract Alice's escrowed coins from order
    let order = table::borrow_mut(&mut orderbook.orders, alice_order.order_id);
    let ol_coins = coin::extract_all(&mut order.escrowed_coins);
    order.status = MATCHED;

    // Create swap agreement with escrowed coins
    let swap_id = generate_swap_id();
    let swap = SwapAgreement {
        swap_id,
        alice: alice_order.trader,
        bob: bob_addr,
        bob_eth_address: bob_balance.eth_address,
        ol_coins,  // Alice's coins stored here
        eth_amount,
        alice_eth_address: alice_order.eth_recipient,
        status: MATCHED,
        match_time: timestamp::now_seconds(),
        timeout: timestamp::now_seconds() + 3600, // 1 hour from match
    };

    // Store swap
    let registry = borrow_global_mut<SwapRegistry>(@ol_framework);
    table::add(&mut registry.swaps, swap_id, swap);

    // Emit event - Alice can now start claiming process
    event::emit(SwapMatched {
        swap_id,
        order_id: alice_order.order_id,
        alice: alice_order.trader,
        bob: bob_addr,
        ol_amount: alice_order.ol_amount,
        eth_amount,
        alice_eth_address: alice_order.eth_recipient,
        bob_eth_address: bob_balance.eth_address,
    });
}
```

**Phase 4: Alice Locks ETH on Ethereum (Ethereum Chain)**
```solidity
// Updated escrow with pre-funded balances
contract AtomicSwapEscrow {
    mapping(address => uint256) public balances;  // Pre-funded balances
    mapping(bytes32 => Swap) public swaps;

    struct Swap {
        address bob;        // ETH provider
        address alice;      // ETH recipient
        uint256 amount;
        uint256 timeout;
        bool claimed;       // True when Alice claims locked ETH
    }

    // Alice locks ETH using ZK proof that swap was matched on OL
    function lockETH(
        bytes32 swapId,
        address bob,
        uint256 amount,
        bytes calldata olSwapProof  // ZK proof that swap was matched on OL
    ) external {
        require(swaps[swapId].amount == 0, "Swap already exists");
        require(balances[bob] >= amount, "Insufficient balance");

        // Verify OL proof that swap was matched
        require(verifyOLSwapMatch(swapId, bob, msg.sender, amount, olSwapProof),
                "Invalid swap proof");

        // Lock funds for this swap
        swaps[swapId] = Swap({
            bob: bob,
            alice: msg.sender,
            amount: amount,
            timeout: block.timestamp + 1 hours,
            claimed: false
        });

        balances[bob] -= amount;

        emit SwapLocked(swapId, bob, msg.sender, amount);
    }

    // Alice claims locked ETH (callable by anyone with valid proof)
    // This happens AFTER Bob has unlocked OL tokens using proof of this lock
    function claimLockedETH(
        bytes32 swapId
    ) external {
        Swap storage swap = swaps[swapId];
        require(!swap.claimed, "Already claimed");
        require(swap.amount > 0, "Swap doesn't exist");

        // Alice can claim immediately - Bob already confirmed by accepting the lock proof on OL
        swap.claimed = true;
        payable(swap.alice).transfer(swap.amount);

        emit ETHClaimed(swapId, swap.alice);
    }

    // Bob refunds if swap times out (Alice didn't lock or claim in time)
    function refund(bytes32 swapId) external {
        Swap storage swap = swaps[swapId];
        require(!swap.claimed, "Already claimed");
        require(block.timestamp >= swap.timeout, "Not expired");
        require(msg.sender == swap.bob, "Not depositor");

        swap.claimed = true;
        balances[swap.bob] += swap.amount;  // Return to Bob's balance

        emit Refunded(swapId, swap.bob);
    }
}
```

**Phase 5: Bob Claims OL Tokens (OL Chain)**
```move
// After Alice locks ETH on Ethereum, Bob (or anyone) can complete the swap
// by proving the ETH lock happened
public entry fun complete_swap(
    _caller: &signer,  // Can be called by anyone
    swap_id: u64,
    eth_lock_proof: vector<u8>,  // ZK proof that Alice locked ETH on Ethereum
) acquires SwapRegistry, ETHBalance {
    let registry = borrow_global_mut<SwapRegistry>(@ol_framework);
    let swap = table::borrow_mut(&mut registry.swaps, swap_id);

    assert!(swap.status == MATCHED, E_INVALID_STATE);

    // Verify ZK proof that Alice successfully locked ETH on Ethereum
    assert!(
        zk_verifier::verify_eth_lock(
            swap_id,
            swap.bob_eth_address,
            swap.alice_eth_address,
            swap.eth_amount,
            eth_lock_proof
        ),
        E_INVALID_LOCK_PROOF
    );

    // Release OL tokens to Bob
    let ol_coins = coin::extract_all(&mut swap.ol_coins);
    let ol_amount = coin::value(&ol_coins);
    coin::deposit(swap.bob, ol_coins);

    // Unlock Bob's ETH balance (swap completed)
    let bob_balance = borrow_global_mut<ETHBalance>(swap.bob);
    bob_balance.locked = bob_balance.locked - swap.eth_amount;

    swap.status = COMPLETED;

    event::emit(SwapCompleted {
        swap_id,
        alice: swap.alice,
        bob: swap.bob,
        ol_amount,
        eth_amount: swap.eth_amount,
    });
}

// Note: After this, Alice can call claimLockedETH() on Ethereum to finalize

// If swap times out, anyone can trigger refund
public entry fun timeout_swap(
    _caller: &signer,
    swap_id: u64,
) acquires SwapRegistry, ETHBalance {
    let registry = borrow_global_mut<SwapRegistry>(@ol_framework);
    let swap = table::borrow_mut(&mut registry.swaps, swap_id);

    assert!(timestamp::now_seconds() >= swap.timeout, E_NOT_EXPIRED);
    assert!(swap.status == MATCHED, E_INVALID_STATE);

    // Return Bob's locked ETH to available
    let bob_balance = borrow_global_mut<ETHBalance>(swap.bob);
    bob_balance.available = bob_balance.available + swap.eth_amount;
    bob_balance.locked = bob_balance.locked - swap.eth_amount;

    // Return Alice's OL tokens
    let alice_coins = coin::extract_all(&mut swap.ol_coins);
    coin::deposit(swap.alice, alice_coins);

    swap.status = TIMED_OUT;

    event::emit(SwapTimedOut {
        swap_id,
        alice: swap.alice,
        bob: swap.bob,
    });
}
```

### 11.4 Key Advantages of Pre-Funding Design

**1. Instant Settlement**
```
Without pre-funding:
1. Match on OL
2. Bob deposits ETH (Ethereum tx: 12 sec + ZK proof: 30 sec)
3. Alice claims
Total: ~42 seconds + user latency

With pre-funding:
1. Match on OL (already verified Bob has funds)
2. Alice claims immediately (ZK proof of match: 30 sec)
Total: ~30 seconds
```

**2. Prevents Order Spam**
- Bob cannot create orders without pre-funded ETH
- Eliminates fake orders on orderbook
- Capital commitment proves serious intent

**3. Better Capital Efficiency**
```
Bob's perspective:
- Deposits 10 ETH once
- Can execute many swaps using that pool
- Only withdraws when done trading
- Similar to CEX experience
```

**4. Atomic Balance Tracking**
```move
struct ETHBalance {
    available: u64,  // Can create new orders
    locked: u64,     // Committed to active swaps
}

// OL tracks Bob's state, prevents double-spending
```

**5. Fair Market Enforcement**
- All matching logic on OL (price-time priority)
- Bob's funds are verified before order submission
- Users cannot manipulate by choosing specific orders
- EVM doesn't know about orderbook (no way to game it)

**6. Gas Efficiency**
```
Ethereum operations:
- One-time deposit: ~50k gas
- Multiple swaps: 0 gas (tracked on OL)
- Final withdraw: ~30k gas

Per-swap gas: ~0 ETH operations (just OL side)
Compare to DEX: 150-300k gas per swap

Amortized cost: ~80k / N swaps
```

**7. Complexity Concentrated on OL**
```
OL Chain:  ~1200 lines (orderbook + balance tracking + matching + verification)
ETH Chain: ~150 lines (deposit + withdraw + swap lock/release)

Ratio: 8:1 complexity on OL vs ETH
```

**8. Single Source of Truth**
- Orderbook state lives entirely on OL
- ETH balances tracked on OL (verified with ZK proofs)
- No synchronization issues between chains
- EVM just holds funds in escrow pool

**9. Easy Upgrades**
- Update orderbook logic on OL without touching EVM
- Update balance tracking logic on OL
- EVM escrow contract can be immutable (simple = secure)
- Add new auction types on OL side only

### 11.5 Security Properties

**OL Chain Responsibilities:**
- ✅ Prevent price manipulation (orderbook matching)
- ✅ Ensure fair ordering (price-time priority)
- ✅ Verify ETH deposits (ZK proof verification)
- ✅ Release OL tokens atomically

**ETH Chain Responsibilities:**
- ✅ Hold ETH in escrow securely
- ✅ Only release to correct recipient
- ✅ Refund if timeout expires
- ❌ No orderbook logic (can't be gamed)
- ❌ No price decisions (relies on OL)

**Trust Assumptions:**
- OL chain state is canonical for orderbook
- ZK proofs correctly verify Ethereum state
- Both chains execute honestly (standard blockchain assumption)

### 11.6 Failure Modes & Recovery

**Scenario 1: Bob doesn't deposit ETH**
```
1. Alice's order sits on OL orderbook
2. Match expires after timeout (e.g., 1 hour)
3. Alice's OL tokens unlocked automatically
4. Alice can create new order
```

**Scenario 2: Bob deposits ETH but OL proof fails**
```
1. Bob's ETH locked in Ethereum escrow
2. Bob cannot provide valid ZK proof to OL
3. Timeout expires on Ethereum side
4. Bob calls refund() on Ethereum, gets ETH back
5. Alice's OL tokens unlocked on OL side
```

**Scenario 3: Alice's ZK proof fails on Ethereum**
```
1. Bob receives OL tokens (proof was valid on OL side)
2. Alice tries to claim ETH with OL release proof
3. Ethereum contract rejects invalid proof
4. Alice must generate correct proof from OL chain data
5. Once correct proof submitted, Alice receives ETH
```

### 11.7 Implementation Priorities

**Week 1-2: Minimal Escrow (EVM)**
- Deploy simple escrow contract to Ethereum testnet
- Test: deposit, release, refund
- ~100 lines of Solidity
- **Goal: Prove EVM side is trivial**

**Week 3-4: ZK Proof System**
- Generate ZK proof of Ethereum deposit
- Verify proof on OL chain (or in Rust tests initially)
- Measure proof generation time (<30s target)
- **Goal: Prove cross-chain verification works**

**Week 5-6: OL Orderbook**
- Implement price-time priority orderbook on OL
- Order matching with fairness guarantees
- Test: prevent price manipulation
- **Goal: Prove fair market enforcement**

**Week 7-8: Full Integration**
- Connect all pieces: orderbook → escrow → proofs
- End-to-end swap test
- Measure total settlement time
- **Goal: Complete working system**

### 11.8 Code Size Comparison

**Symmetric (Both chains do similar work):**
```
OL HTLC:      200 lines
ETH HTLC:     200 lines
OL Orderbook: 500 lines
ETH Orderbook: 500 lines  ← Wasteful! High gas costs!
Total:        1400 lines (700 per chain)
```

**Asymmetric (OL heavy, ETH minimal):**
```
OL Orderbook + Swap: 1000 lines  ← All business logic
ETH Escrow:          100 lines   ← Minimal, cheap
Total:               1100 lines (90% on OL, 10% on ETH)

Benefit:
- Simpler overall
- Much cheaper gas costs
- Easier to audit ETH contract
- Single source of truth (OL orderbook)
```

### 11.9 Recommended Final Architecture

**For OL ↔ ETH atomic swaps, use asymmetric design:**

1. **OL Chain**: Full orderbook, Dutch auctions, batch auctions, ZK verification
2. **ETH Chain**: Minimal escrow contract (deposit, release with proof, refund on timeout)
3. **Solvers**: Monitor OL orderbook, deposit ETH when matched, submit proofs to complete

This architecture:
- ✅ Minimizes expensive Ethereum operations
- ✅ Leverages Move's safety for complex orderbook logic
- ✅ Single source of truth (OL orderbook)
- ✅ Prevents price manipulation (all matching on OL)
- ✅ Easy to upgrade (change OL, keep ETH immutable)
- ✅ Multi-chain ready (same escrow contract for all EVM chains)
- ✅ Gas efficient (~80k gas vs 150-300k for DEX)
- ✅ Fast settlement (30s - 2min with ZK proofs)

---

## 11.10. Execution Modes: Manual vs Automated

The protocol supports two distinct execution modes, allowing users to choose between full control and convenience.

### Manual Mode (Paranoid/Autonomous Systems)

Manual mode requires users to explicitly trigger each step of the swap process. This mode is designed for:
- **Paranoid users** who want full control over each transaction
- **Autonomous trading systems** that implement custom logic
- **Auditors and security researchers** who need to inspect each state transition

**Manual Execution Flow:**

```move
// Step 1: Alice manually creates sell order
libra txs swap create-sell-order \
  --amount 1000 \
  --min-eth 1.0 \
  --eth-recipient 0xAlice...

// Step 2: Bob manually registers ETH balance (one-time setup)
libra txs swap register-eth \
  --eth-address 0xBob... \
  --balance-proof <zk_proof_hex>

// Step 3: Bob manually matches Alice's order
libra txs swap create-buy-order \
  --eth-amount 1.0 \
  --max-ol-price 1000

// Step 4: Alice manually locks ETH on Ethereum
cast send $ESCROW_CONTRACT "lockETH(bytes32,address,uint256,bytes)" \
  $SWAP_ID $BOB_ETH_ADDRESS 1000000000000000000 $OL_MATCH_PROOF

// Step 5: Bob (or anyone) manually completes swap on OL
libra txs swap complete \
  --swap-id $SWAP_ID \
  --eth-lock-proof <zk_proof_hex>

// Step 6: Alice manually claims locked ETH
cast send $ESCROW_CONTRACT "claimLockedETH(bytes32)" $SWAP_ID
```

**Advantages:**
- ✅ Full transparency - user sees every state change
- ✅ Custom timing - user controls when each step executes
- ✅ No daemon dependency - works with basic CLI tools
- ✅ Auditable - each transaction can be independently verified
- ✅ Compatible with hardware wallets and air-gapped signing

**Disadvantages:**
- ❌ Slower - user must wait and execute each step
- ❌ Risk of timeout - if user doesn't act quickly, swap may expire
- ❌ More complex - requires understanding of protocol flow

### Automated Mode (Normal Users)

Automated mode uses a specialized wallet daemon that continuously polls both chains and automatically executes swap steps on behalf of the user.

**Wallet Daemon Architecture:**

```rust
// Simplified automated wallet daemon
struct SwapWalletDaemon {
    ol_client: OLClient,
    eth_client: EthClient,
    user_keys: KeyPair,
    config: DaemonConfig,
}

impl SwapWalletDaemon {
    async fn run(&self) {
        loop {
            // Poll OL chain for events affecting user
            self.poll_ol_events().await;

            // Poll ETH chain for events affecting user
            self.poll_eth_events().await;

            // Auto-execute pending actions
            self.auto_execute_pending_actions().await;

            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    }

    async fn poll_ol_events(&self) {
        // Watch for: OrderMatched events where user is Alice or Bob
        let events = self.ol_client.get_events_since_cursor(...).await;

        for event in events {
            match event {
                SwapMatched { swap_id, alice, bob, .. } => {
                    if alice == self.user_keys.address() {
                        // Alice's order matched - auto lock ETH
                        self.auto_lock_eth(swap_id).await;
                    } else if bob == self.user_keys.address() {
                        // Bob matched - wait for Alice to lock ETH
                        self.watch_for_eth_lock(swap_id).await;
                    }
                }
                SwapCompleted { swap_id, alice, .. } => {
                    if alice == self.user_keys.address() {
                        // Bob claimed OL - auto claim ETH
                        self.auto_claim_eth(swap_id).await;
                    }
                }
                _ => {}
            }
        }
    }

    async fn poll_eth_events(&self) {
        // Watch for: SwapLocked events affecting user
        let events = self.eth_client.get_logs(...).await;

        for event in events {
            match event {
                SwapLocked { swap_id, bob, alice, .. } => {
                    if bob == self.user_keys.eth_address() {
                        // Alice locked ETH - auto complete swap on OL
                        self.auto_complete_swap_on_ol(swap_id).await;
                    }
                }
                _ => {}
            }
        }
    }

    async fn auto_lock_eth(&self, swap_id: u64) {
        // Generate ZK proof of OL match
        let ol_match_proof = self.generate_ol_match_proof(swap_id).await;

        // Submit ETH lock transaction
        let tx = self.eth_client.lock_eth(
            swap_id,
            ol_match_proof
        ).await;

        log::info!("Auto-locked ETH for swap {}: {}", swap_id, tx.hash);
    }

    async fn auto_complete_swap_on_ol(&self, swap_id: u64) {
        // Generate ZK proof of ETH lock
        let eth_lock_proof = self.generate_eth_lock_proof(swap_id).await;

        // Submit OL completion transaction
        let tx = self.ol_client.complete_swap(
            swap_id,
            eth_lock_proof
        ).await;

        log::info!("Auto-completed swap {} on OL: {}", swap_id, tx.hash);
    }
}
```

**User Experience:**

```bash
# One-time setup: Start daemon
libra wallet daemon start --auto-swap

# Alice simply creates order - daemon handles the rest
libra txs swap create-sell-order --amount 1000 --min-eth 1.0

# Daemon automatically:
# 1. Watches for match event
# 2. Locks ETH on Ethereum (with ZK proof of match)
# 3. Waits for Bob to complete on OL
# 4. Claims locked ETH on Ethereum
# 5. Notifies user of completion

# User gets notification: "Swap completed! Received 1.0 ETH"
```

**Advantages:**
- ✅ Fast - no user latency between steps
- ✅ Simple UX - user only creates order, rest is automatic
- ✅ Lower timeout risk - daemon acts immediately
- ✅ Better for high-frequency trading

**Disadvantages:**
- ❌ Requires running daemon (or trusting hosted wallet)
- ❌ Less transparent - user doesn't see intermediate steps
- ❌ Daemon failure risk - if daemon crashes, swap might timeout

### 11.11. Global State Commitment: Withdraw-Time Verification

A critical feature of this design is that **anyone attempting to withdraw from escrow must provide the global state of all pending transactions** as part of their withdrawal call. This includes their own transaction and potentially those of bad actors.

This simple requirement eliminates the need for dedicated oracle infrastructure - the withdrawer themselves provides the cross-chain state verification, and anyone can verify it's complete and accurate.

### Withdrawal Requires Global State Proof

The protocol requires that every withdrawal call includes a cryptographic commitment to the complete set of pending transactions. To verify completeness, the destination chain maintains **periodic checkpoints** of the source chain's state.

**Core Principle:**
> To withdraw, you must provide proof of the global pending transaction set against a recent checkpoint. Your transaction is in that set. Any missing transactions will cause verification to fail.

### Checkpoint Mechanism: Transaction Chaining (No Trusted Parties)

Instead of requiring validator signatures or committees, **each transaction naturally extends the checkpoint chain**. Every cross-chain transaction proves the state of the source chain and becomes a checkpoint for the next transaction.

**Key Principle:**
> Each transaction must prove it builds on the previous transaction's state. This creates a provable chain of state transitions with no trusted intermediaries.

**Implementation:**

```solidity
// Ethereum contract tracks OL state through transaction chain
contract AtomicSwapEscrow {
    struct StateCheckpoint {
        bytes32 olStateRoot;        // OL state root at this point
        uint256 olBlockHeight;      // OL block height
        bytes32 prevCheckpointHash; // Hash of previous checkpoint (forms chain)
        uint256 ethBlockNumber;     // When this checkpoint was created
    }

    // Latest checkpoint hash (chain tip)
    bytes32 public latestCheckpointHash;

    // Checkpoint history
    mapping(bytes32 => StateCheckpoint) public checkpoints;

    // Alice claims ETH - creates a new checkpoint by proving OL state
    function claimLockedETH(
        bytes32 swapId,

        // Prove OL state builds on previous checkpoint
        bytes32 prevCheckpointHash,     // Reference to previous checkpoint
        bytes32 olStateRoot,             // Current OL state root
        uint256 olBlockHeight,           // Current OL block height
        bytes calldata stateTransitionProof, // Merkle proof that state advanced validly

        // Prove this swap in current OL state
        bytes32 pendingSetMerkleRoot,
        bytes calldata swapMerkleProof,
        bytes calldata olCompletionProof
    ) external {
        Swap storage swap = swaps[swapId];
        require(!swap.claimed, "Already claimed");
        require(msg.sender == swap.alice, "Not recipient");

        // 1. Verify state transition from previous checkpoint
        if (prevCheckpointHash != bytes32(0)) {
            StateCheckpoint storage prev = checkpoints[prevCheckpointHash];
            require(prev.olBlockHeight > 0, "Invalid previous checkpoint");

            // Prove OL state advanced from prev.olStateRoot to olStateRoot
            // This is just a Merkle proof showing block progression
            require(
                verifyStateTransition(
                    prev.olStateRoot,
                    prev.olBlockHeight,
                    olStateRoot,
                    olBlockHeight,
                    stateTransitionProof
                ),
                "Invalid state transition"
            );
        }

        // 2. Verify swap completed in current OL state (Merkle proofs)
        require(
            verifyMerkleProof(olStateRoot, pendingSetMerkleRoot, swapMerkleProof),
            "Swap not in OL state"
        );

        // 3. Create new checkpoint (this transaction extends the chain)
        bytes32 newCheckpointHash = keccak256(abi.encodePacked(
            olStateRoot,
            olBlockHeight,
            prevCheckpointHash,
            block.number
        ));

        checkpoints[newCheckpointHash] = StateCheckpoint({
            olStateRoot: olStateRoot,
            olBlockHeight: olBlockHeight,
            prevCheckpointHash: prevCheckpointHash,
            ethBlockNumber: block.number
        });

        latestCheckpointHash = newCheckpointHash;

        // 4. Release ETH
        swap.claimed = true;
        payable(swap.alice).transfer(swap.amount);

        emit ETHClaimed(swapId, swap.alice, newCheckpointHash);
    }

    // Anyone can challenge invalid checkpoint by proving correct state
    function challengeCheckpoint(
        bytes32 invalidCheckpointHash,
        bytes32 correctOLStateRoot,
        uint256 olBlockHeight,
        bytes calldata correctStateProof  // Proof of actual OL state
    ) external {
        StateCheckpoint storage invalid = checkpoints[invalidCheckpointHash];

        // Prove the checkpoint used wrong state root
        require(invalid.olStateRoot != correctOLStateRoot, "Checkpoint is valid");

        // Prove what the ACTUAL state root was at that height
        // This can be proven by showing blockchain headers / Merkle proofs
        require(
            verifyActualOLState(olBlockHeight, correctOLStateRoot, correctStateProof),
            "Invalid correction"
        );

        // Revert to previous valid checkpoint
        latestCheckpointHash = invalid.prevCheckpointHash;
        delete checkpoints[invalidCheckpointHash];

        emit CheckpointChallenged(invalidCheckpointHash, msg.sender);
    }
}
```

**OL Side: Symmetric Transaction Chaining**

```move
/// OL contract tracks Ethereum state through transaction chain
module ol_framework::swap_global_state {
    use std::signer;
    use ol_framework::table;
    use ol_framework::hash;
    use ol_framework::merkle;

    struct StateCheckpoint has copy, drop, store {
        eth_state_root: vector<u8>,      // Ethereum state root at this point
        eth_block_number: u64,            // Ethereum block number
        prev_checkpoint_hash: vector<u8>, // Hash of previous checkpoint (forms chain)
        ol_block_height: u64,             // When this checkpoint was created on OL
    }

    struct CheckpointRegistry has key {
        latest_checkpoint_hash: vector<u8>,  // Chain tip
        checkpoints: Table<vector<u8>, StateCheckpoint>,  // hash -> checkpoint
    }

    /// Bob completes swap - creates new checkpoint by proving Ethereum state
    public entry fun complete_swap(
        _caller: &signer,
        swap_id: u64,

        // Prove Ethereum state builds on previous checkpoint
        prev_checkpoint_hash: vector<u8>,    // Reference to previous checkpoint
        eth_state_root: vector<u8>,          // Current Ethereum state root
        eth_block_number: u64,                // Current Ethereum block number
        state_transition_proof: vector<u8>,  // Merkle proof that ETH state advanced validly

        // Prove this swap's ETH lock in current Ethereum state
        pending_set_merkle_root: vector<u8>,
        swap_merkle_proof: vector<u8>,
        eth_lock_proof: vector<u8>,
    ) acquires SwapRegistry, ETHBalance, CheckpointRegistry {
        let registry = borrow_global_mut<SwapRegistry>(@ol_framework);
        let swap = table::borrow_mut(&mut registry.swaps, swap_id);

        assert!(swap.status == MATCHED, E_INVALID_STATE);

        let checkpoint_registry = borrow_global_mut<CheckpointRegistry>(@ol_framework);

        // 1. Verify state transition from previous checkpoint
        if (vector::length(&prev_checkpoint_hash) > 0) {
            let prev = table::borrow(&checkpoint_registry.checkpoints, prev_checkpoint_hash);

            // Prove Ethereum state advanced from prev.eth_state_root to eth_state_root
            // This is Merkle proof showing Ethereum block progression
            assert!(
                verify_eth_state_transition(
                    &prev.eth_state_root,
                    prev.eth_block_number,
                    &eth_state_root,
                    eth_block_number,
                    &state_transition_proof
                ),
                E_INVALID_STATE_TRANSITION
            );
        };

        // 2. Verify swap's ETH lock in current Ethereum state (Merkle proofs)
        assert!(
            merkle::verify_proof(
                &eth_state_root,
                &pending_set_merkle_root,
                &swap_merkle_proof
            ),
            E_LOCK_NOT_IN_ETH_STATE
        );

        // 3. Create new checkpoint (this transaction extends the chain)
        let new_checkpoint_hash = hash::keccak256(&vector::append(
            vector::append(eth_state_root, serialize_u64(eth_block_number)),
            prev_checkpoint_hash
        ));

        let checkpoint = StateCheckpoint {
            eth_state_root,
            eth_block_number,
            prev_checkpoint_hash,
            ol_block_height: block::get_current_block_height(),
        };

        table::upsert(&mut checkpoint_registry.checkpoints, new_checkpoint_hash, checkpoint);
        checkpoint_registry.latest_checkpoint_hash = new_checkpoint_hash;

        // 4. Release OL tokens to Bob
        let ol_coins = coin::extract_all(&mut swap.ol_coins);
        let ol_amount = coin::value(&ol_coins);
        coin::deposit(swap.bob, ol_coins);

        // Unlock Bob's ETH balance (swap completed)
        let bob_balance = borrow_global_mut<ETHBalance>(swap.bob);
        bob_balance.locked = bob_balance.locked - swap.eth_amount;

        swap.status = COMPLETED;

        event::emit(SwapCompleted {
            swap_id,
            alice: swap.alice,
            bob: swap.bob,
            ol_amount,
            eth_amount: swap.eth_amount,
        });
    }
}
```

**Implementation on Ethereum:**

```solidity
// Global state commitment on Ethereum side
contract AtomicSwapEscrow {
    mapping(bytes32 => Swap) public swaps;

    struct Swap {
        address bob;
        address alice;
        uint256 amount;
        uint256 timeout;
        bool claimed;
    }

    // Alice claims ETH - MUST provide global pending state
    function claimLockedETH(
        bytes32 swapId,

        // CRITICAL: Caller must provide global pending state from OL
        bytes32 pendingSetMerkleRoot,     // Root of ALL pending swaps on OL
        bytes calldata swapMerkleProof,   // Proof this swap is in the set
        bytes calldata olCompletionProof, // ZK proof swap completed on OL
        bytes calldata globalConsistencyProof, // ZK proof the global set is complete
        uint256 olBlockHeight
    ) external {
        Swap storage swap = swaps[swapId];
        require(swap.amount > 0, "Swap doesn't exist");
        require(!swap.claimed, "Already claimed");
        require(msg.sender == swap.alice, "Not recipient");

        // 1. Verify this swap is included in the global pending set on OL
        require(
            verifyMerkleInclusion(swapId, pendingSetMerkleRoot, swapMerkleProof),
            "Swap not in global set"
        );

        // 2. Verify the global pending set is complete and matches OL chain state
        // This is the KEY verification - ensures no transactions are hidden
        require(
            verifyOLGlobalPendingSet(pendingSetMerkleRoot, globalConsistencyProof, olBlockHeight),
            "Incomplete global set"
        );

        // 3. Verify this specific swap was completed on OL (Bob received tokens)
        require(
            verifyOLCompletion(swapId, swap.bob, swap.alice, olCompletionProof, olBlockHeight),
            "Swap not completed on OL"
        );

        // All verifications passed - the caller proved:
        // - Their swap is in the global OL pending set
        // - The global set is complete (no hidden transactions)
        // - The swap was actually completed on OL (Bob got tokens)
        // Safe to proceed

        swap.claimed = true;
        payable(swap.alice).transfer(swap.amount);

        emit ETHClaimed(swapId, swap.alice);
    }
}
```

### Checkpoint Submission Flow

**Who Submits Checkpoints?**

**Primary model: Users submit checkpoints when they need to withdraw**

The protocol should work without any background infrastructure:

1. **User wants to withdraw** (e.g., Alice wants to claim ETH)
2. **User checks**: Is there a recent checkpoint? (< 1 hour old)
3. **If no recent checkpoint**: User submits checkpoint themselves first
4. **Then**: User submits withdrawal using that checkpoint

**No background daemon required** - checkpoints are created on-demand by users who need them.

**Optional optimization: Cooperative checkpoint submission**

Users who just withdrew can leave a fresh checkpoint for the next user:
- Alice submits checkpoint + withdraws
- Bob sees Alice's checkpoint (5 mins old), uses it directly
- Charlie sees Bob used Alice's checkpoint, also uses it
- Eventually checkpoint gets stale, next user submits fresh one

**Cost Model:**
- First user after staleness: Pays ~$10-30 to submit checkpoint + ~$5-20 for withdrawal = $15-50 total
- Next N users: Only pay ~$5-20 for withdrawal (reuse checkpoint)
- This naturally incentivizes checkpoint sharing without explicit rewards

**Checkpoint Frequency:**
- No fixed frequency - submitted on-demand
- Max age accepted: 1-3 hours (configurable)
- In practice: Heavy trading creates frequent checkpoints, light trading creates sparse checkpoints

**Checkpoint Lifecycle (On-Demand):**

```
1. Alice wants to withdraw:
   ├─ Checks latest checkpoint on Ethereum
   ├─ Latest is 2 hours old (too stale)
   └─ Alice must submit fresh checkpoint first

2. Alice generates consensus proof:
   ├─ Gets current OL block height: 10,000
   ├─ Gets OL state root at height 10,000
   ├─ Generates ZK proof of OL consensus (validator signatures)
   └─ Proof generation: ~30 seconds

3. Alice submits checkpoint transaction:
   ├─ Call submitOLCheckpoint() on Ethereum
   ├─ Pays ~$20 gas to store OL state root
   └─ Checkpoint now available for everyone

4. Alice immediately submits withdrawal:
   ├─ Uses checkpoint she just submitted
   ├─ Pays ~$5-20 for withdrawal
   └─ Total cost: ~$25-40

5. Bob wants to withdraw 10 minutes later:
   ├─ Sees Alice's checkpoint (10 mins old - fresh!)
   ├─ Uses Alice's checkpoint directly
   ├─ Pays only ~$5-20 for withdrawal
   └─ Saves ~$20 by reusing checkpoint

6. Charlie, Diana, Eve also withdraw:
   ├─ All reuse Alice's checkpoint (still < 1 hour old)
   └─ Alice's $20 checkpoint cost amortized across 5 users = $4 each
```

**Security Properties:**

- **ZK consensus proofs**: Checkpoints are cryptographically proven, not trusted
- **Anyone can submit**: No centralized checkpoint authority
- **Recent checkpoints required**: Withdrawals must use checkpoint <3 hours old
- **Immutable once stored**: Can't change checkpoint after submission
- **Invalid checkpoints rejected**: ZK proof verification fails if consensus is invalid

**Example: Full Swap with Checkpoints**

```
Time  | OL Chain                        | Ethereum Chain
------|---------------------------------|--------------------------------
T+0   | Alice creates sell order        |
T+1   | Bob matches (locks ETH balance) |
T+2   |                                 | Alice locks ETH in escrow
T+5   | Checkpoint 100 submitted        | (OL state root stored)
      | - OL block 10,000              |
      | - State root: 0xabc...         |
T+10  | Bob wants to complete swap:     |
      | - Uses checkpoint 100           |
      | - Proves ETH pending set       |
      |   against ETH state root       |
      | - Proves Alice's lock is in set|
      | - Receives OL tokens ✓         |
T+15  |                                 | Checkpoint 100 submitted
      |                                 | (OL state root stored)
T+20  |                                 | Alice wants to claim ETH:
      |                                 | - Uses checkpoint 100
      |                                 | - Proves OL completion
      |                                 |   against OL state root
      |                                 | - Receives ETH ✓
```

**Key Insight:**

Checkpoints solve the "how do we know the global state is complete?" problem:
- Without checkpoints: No way to verify claimed global state is actually complete
- With checkpoints: Contract knows the canonical state root, can verify completeness via ZK proof

The checkpoint itself is trustless (proven via ZK), and anyone can submit it.

**Critical Economic Design:**

The key insight is that checkpoint submission is **self-interested, not altruistic**:

- **Without recent checkpoint**: You CANNOT withdraw
- **Want to withdraw?**: Submit checkpoint yourself (~$20 extra)
- **Side effect**: Your checkpoint helps next users withdraw cheaply

This is different from an oracle which requires:
- ❌ Continuous monitoring (ongoing operational cost)
- ❌ Incentives to keep oracle honest
- ❌ Governance to manage oracle set
- ❌ Slashing for oracle misbehavior

Instead, checkpoints are:
- ✅ On-demand (only created when needed)
- ✅ Self-interested (submitter wants to withdraw)
- ✅ Cryptographically verified (can't be faked)
- ✅ Permissionless (anyone can submit)
- ✅ Public good side effect (helps future users)

**No continuous infrastructure required** - protocol works even if months pass between checkpoints.

### Summary: Transaction Chaining Design

**Core Innovation: Checkpoints created BY transactions, not FOR transactions**

Instead of:
- ❌ Validators submit checkpoints (trusted intermediaries)
- ❌ Sync committees attest to state (trusted intermediaries)
- ❌ Oracle submits periodic state roots (trusted intermediary)

We have:
- ✅ Each transaction proves it builds on previous transaction's state
- ✅ Each transaction creates new checkpoint for next transaction
- ✅ Forms provable chain with no trusted parties
- ✅ Any honest actor can reset chain if invalid checkpoint appears

**How It Works:**

```
Genesis (empty checkpoint)
    ↓
Alice withdraws:
   - Proves: Ethereum state at block 1000
   - Creates: Checkpoint A (ETH block 1000)
    ↓
Bob withdraws:
   - Proves: Ethereum advanced from block 1000 → 1050 (Merkle proof of block headers)
   - Proves: His swap is in Ethereum state at block 1050
   - Creates: Checkpoint B (ETH block 1050) building on Checkpoint A
    ↓
Charlie withdraws:
   - Proves: Ethereum advanced from block 1050 → 1100
   - Creates: Checkpoint C building on Checkpoint B
```

**If someone submits invalid checkpoint:**

```
...→ Checkpoint B (valid) → Checkpoint X (INVALID) → stuck

Any honest actor:
1. Sees Checkpoint X claims ETH state root is 0xbad... at block 1200
2. Proves actual ETH state root is 0xgood... at block 1200
   (by showing block headers with correct state root)
3. Calls challengeCheckpoint(X, 0xgood..., proof)
4. Contract reverts to Checkpoint B
5. Next transaction must build on B, not X
```

**No Trust Required:**
- Don't need to trust validators (no validator signatures)
- Don't need to trust oracles (no oracle attestation)
- Don't need to trust committees (no sync committee)
- Only need: Math (Merkle proofs) + One honest actor

### ZK Proofs vs Merkle Proofs: What Do We Actually Need?

**The short answer: Just Merkle proofs! No ZK needed for basic protocol.**

Here's what we use for each verification:

| Verification | Method | Why |
|-------------|--------|-----|
| **Checkpoint validity** | Validator signatures (BFT) or Sync committee signatures (Ethereum PoS) | Direct cryptographic verification, no ZK needed |
| **Global state inclusion** | Merkle proof | Proving a value is in a known state root is exactly what Merkle trees do |
| **Swap in pending set** | Merkle proof | Again, just proving inclusion in a known root |
| **Lock/completion status** | Merkle proof | State tree already has this info, just prove it |

**Where ZK Proofs COULD Be Useful (Optional Optimizations):**

1. **Signature aggregation**: If validator set is very large (>1000 validators), ZK proof could compress signatures
   - BFT (small validator set): Not needed
   - Ethereum PoS sync committee: 512 validators, manageable without ZK

2. **Complex conditions**: If we want to prove "no double-spend across all pending swaps" in zero-knowledge
   - Current design: We just provide the complete pending set, anyone can check
   - ZK alternative: Prove the property without revealing all swaps
   - Trade-off: More complexity for marginal privacy benefit

3. **Proof batching**: Aggregate many Merkle proofs into one ZK proof
   - Reduces on-chain verification cost
   - Adds off-chain proof generation complexity

**Recommended Approach:**

**MVP: Pure Merkle proofs**
- Checkpoint submission: Direct validator signature verification
- State proofs: Standard Merkle proofs
- Simple, well-understood, easy to implement
- Gas cost: ~$5-20 per withdrawal (acceptable)

**Future optimization (if gas becomes issue):**
- Aggregate signatures using ZK for very large validator sets
- Batch Merkle proofs for high-frequency users
- Only add ZK when gas costs justify the complexity

**Key Insight:**

Merkle trees are already cryptographic proofs! The blockchain state root is a Merkle root. Proving something is in that state is just a Merkle proof - no fancy ZK needed.

```
Ethereum State Root (Merkle root)
  ├─ Account 0x123...
  │   └─ Storage slot 0: pendingSetRoot
  │       ├─ Swap #1
  │       ├─ Swap #2
  │       └─ Swap #3
  └─ Merkle proof path proves Swap #2 exists
```

This is much simpler than ZK proofs and works perfectly fine for our use case.

### How It Works

**The withdrawer provides the global state as part of their withdrawal call:**
- **Alice** wants to claim ETH → Provides global pending set in `claimLockedETH()` call
- **Bob** (or anyone) wants to complete swap on OL → Provides global pending set in `complete_swap()` call

**No Separate Proof Submission:**
- No state registry
- No proof submission transactions
- Proofs are part of the withdrawal transaction itself

**Cost is Minimal:**
- ~$5-20 gas for withdrawal with proofs (slightly higher than withdrawal alone)
- Cost paid by whoever wants to withdraw (usually the beneficiary)
- No special incentives needed - self-interest drives participation

### Example Scenarios

**Scenario 1: Normal Swap (with On-Demand Checkpoints)**

1. Alice locks ETH on Ethereum (Phase 4)
2. Bob wants to complete swap on OL:
   - Checks for recent ETH checkpoint on OL
   - Latest checkpoint is 30 minutes old (fresh enough!)
   - Uses existing checkpoint
3. Bob calls `complete_swap()` on OL with:
   - Checkpoint height: 10,000
   - Global pending set Merkle root (from Ethereum escrow contract at block 10,000)
   - Merkle proof his swap is in that set
   - ZK proof the pending set root is in Ethereum state at checkpoint
   - ZK proof Alice's ETH lock exists
4. OL contract verifies against checkpoint 10,000 → Bob receives OL tokens
5. Alice wants to claim ETH:
   - Checks for recent OL checkpoint on Ethereum
   - Latest checkpoint is 2 hours old (too stale!)
   - Alice submits fresh OL checkpoint first (~$20 gas)
6. Alice calls `claimLockedETH()` on Ethereum with:
   - Checkpoint height: 5,000 (the one she just submitted)
   - Global pending set Merkle root (from OL swap registry at block 5,000)
   - Merkle proof her swap is in that set
   - ZK proof the pending set root is in OL state at checkpoint
   - ZK proof swap completed on OL (Bob got tokens)
   - Pays ~$5-20 for withdrawal
7. Ethereum contract verifies against checkpoint 5,000 → Alice receives ETH
8. Swap complete! Total cost to Alice: ~$25-40 (checkpoint + withdrawal)

**Scenario 2: Fraud Attempt Blocked (Invalid Global Set)**

1. Alice locks ETH on Ethereum
2. Checkpoint 10,000 stores Ethereum state root
3. Bob tries to call `complete_swap()` with INCOMPLETE global set:
   - He omits another pending swap to hide a conflict
   - His claimed pending set Merkle root: 0xbad...
4. ZK verification fails: `E_PENDING_SET_NOT_IN_ETH_STATE`
   - The global state proof tries to prove 0xbad... is in Ethereum state
   - But checkpoint 10,000 state root only contains the REAL pending set root 0xabc...
   - Proof verification fails - 0xbad... is not in the canonical Ethereum state
5. Bob's withdrawal is rejected
6. Fraud prevented - can't provide incomplete global set because checkpoint knows real state

**Scenario 3: Fraud Attempt Blocked (No ETH Lock)**

1. Alice CLAIMS she locked ETH but actually didn't
2. Someone tries to call `complete_swap()` with global state proof
3. Global set verification passes (it's accurate)
4. But ETH lock proof fails: `E_INVALID_ETH_LOCK_PROOF`
   - Alice's lock doesn't exist in the Ethereum state
5. Withdrawal is rejected
6. Fraud prevented proactively

**Scenario 4: Double-Spend Blocked**

1. Bob registers 10 ETH on OL
2. Bob matches 5 swaps totaling 12 ETH (attempting double-spend)
3. When constructing global pending set for swap #5:
   - The set includes swaps #1, #2, #3, #4 (total 8 ETH)
   - Adding swap #5 (2 ETH) exceeds Bob's registered balance
4. Global consistency proof fails: `E_INCOMPLETE_GLOBAL_SET`
   - The proof shows Bob doesn't have sufficient balance for all swaps
5. Withdrawal blocked for swap #5
6. Double-spend prevented

### Why This Eliminates Oracle Infrastructure

**Traditional Oracle Design:**
```
┌─────────────────────────────────────┐
│  Centralized Oracle Service         │
│  - Monitors both chains             │
│  - Attests to cross-chain state     │
│  - Trusted third party              │
│  - Single point of failure          │
│  - Needs ongoing operational costs  │
│  - Requires governance & incentives │
└─────────────────────────────────────┘
           ↓ provides attestation
    ┌──────────────┐
    │  Swap Smart  │
    │   Contract   │
    │  (trusts     │
    │   oracle)    │
    └──────────────┘
```

**Global State Commitment Design:**
```
    ┌──────────────┐
    │  Withdrawer  │
    │  (Alice/Bob) │
    └──────┬───────┘
           │
           │ Provides global pending set + ZK proofs
           │ as part of withdrawal transaction
           ↓
    ┌──────────────────────────┐
    │  Swap Smart Contract     │
    │  - Verifies global set   │
    │  - Verifies completeness │
    │  - No trusted oracle     │
    └──────────────────────────┘
```

**Key Differences:**

| Traditional Oracle | Global State Commitment |
|-------------------|------------------------|
| Trusted third party attests to state | Withdrawer proves state cryptographically |
| Oracle monitors continuously | No monitoring needed |
| Requires oracle incentives/governance | Self-interest drives proof generation |
| Oracle can lie or fail | Cryptographic proofs can't lie |
| Centralized (oracle as bottleneck) | Fully decentralized (anyone can withdraw) |
| Ongoing operational costs | No infrastructure to maintain |

**The Elegant Simplicity:**

Instead of asking "who do we trust to tell us the truth about the other chain?", we ask "can you prove the complete state when you withdraw?"

- ✅ **No oracle selection** - don't need to choose who to trust
- ✅ **No oracle incentives** - don't need to pay anyone to monitor
- ✅ **No oracle slashing** - don't need to punish misbehavior
- ✅ **No oracle governance** - don't need to manage reputation
- ✅ **No uptime requirements** - no service to keep running

The withdrawer pays slightly more gas (~$5-20) to include proofs, but gains **trustlessness** without relying on any external party.

### Recommended Deployment Strategy

**For Individual Traders (Automated Mode):**
1. Run automated wallet daemon for convenience
2. Daemon handles checkpoint submission when needed:
   - Checks for recent checkpoint before withdrawal
   - Submits new checkpoint if stale (pays checkpoint cost)
   - Reuses existing checkpoint if fresh (saves cost)
3. Daemon automatically generates proofs and includes them in withdrawal calls
4. Total cost per withdrawal:
   - If checkpoint exists: ~$5-20 (just withdrawal)
   - If checkpoint needed: ~$25-40 (checkpoint + withdrawal)

**For Individual Traders (Manual Mode):**
1. Execute swap steps manually via CLI
2. Before withdrawal, check checkpoint freshness
3. Submit checkpoint yourself if needed
4. Generate global state proofs when ready to withdraw
5. Include proofs as parameters in withdrawal transaction

**Example Manual Withdrawal:**
```bash
# Check latest checkpoint
libra swap check-checkpoint --chain ethereum

# If stale, submit fresh checkpoint
libra swap submit-checkpoint \
  --chain ethereum \
  --ol-block-height 10000

# Generate global pending set proof
libra swap generate-global-proof \
  --checkpoint-height 10000 \
  --output /tmp/global_proof.json

# Complete swap with proof
libra txs swap complete \
  --swap-id 12345 \
  --checkpoint-height 10000 \
  --pending-set-root 0xabc... \
  --swap-merkle-proof /tmp/proof.json \
  --eth-lock-proof /tmp/eth_proof.json \
  --global-state-proof /tmp/global_proof.json
```

**For Professional Market Makers:**
1. Run manual mode for full control
2. Deploy optimized proof generation infrastructure
3. Optionally run checkpoint submission service:
   - Submit checkpoints every 10-20 minutes (public good)
   - Provides convenience for other users
   - No special reward, just good citizenship
4. Or: Let users submit their own checkpoints on-demand

**For Optional Checkpoint Services (Not Required):**
1. Monitor both chains
2. Submit checkpoints proactively every 10-20 minutes
3. Provides convenience - users never need to submit checkpoints themselves
4. No revenue model needed - can be run as protocol infrastructure
5. Protocol works fine WITHOUT this service (users submit on-demand)

**For Protocol:**
1. Design works with ZERO background infrastructure
2. Users can always submit checkpoints themselves when withdrawing
3. Provide open-source reference implementation:
   - Checkpoint generation library (Rust)
   - Proof generation library (Rust)
   - Wallet daemon with auto-checkpoint-submission (optional convenience)
   - CLI tools for manual mode
4. Document checkpoint submission and verification
5. NO oracle infrastructure REQUIRED
6. NO governance or incentive mechanisms NEEDED
7. Optional services (daemons, checkpoint bots) are conveniences, not dependencies

---

## 12. Bitcoin Integration: State of the Art ZK Proof Verification

Bitcoin integration is particularly interesting because Bitcoin doesn't have smart contract functionality like EVM chains. However, recent advances in ZK proof systems make Bitcoin atomic swaps feasible through client-side verification and minimalist on-chain primitives.

### 12.1 Bitcoin's Constraints

**What Bitcoin CAN do:**
- ✅ Time locks (CheckLockTimeVerify - CLTV, CheckSequenceVerify - CSV)
- ✅ Hash locks (OP_HASH160, OP_SHA256)
- ✅ Schnorr signatures (Taproot - since 2021)
- ✅ Basic scripting (Bitcoin Script)

**What Bitcoin CANNOT do:**
- ❌ Complex state machines
- ❌ Verify ZK proofs on-chain (too expensive/impossible with Script)
- ❌ Read external chain state
- ❌ Turing-complete computation

**Implication**: ZK proof verification for Bitcoin must happen **client-side** or through **indirect mechanisms**.

### 12.2 Current State of the Art

#### Approach 1: BitVM (Bitcoin Virtual Machine)

**Status**: Research/Early Development (2023-2024)

**Concept**: Optimistic computation verification on Bitcoin using fraud proofs.

**How it works**:
1. Prover commits to computation result (e.g., "OL transaction exists")
2. Challenge period where anyone can submit fraud proof
3. Bisection protocol narrows down to single incorrect step
4. Bitcoin script verifies that single step

**For Atomic Swaps**:
```
1. Solver commits: "I verified OL transaction with ZK proof"
2. Bitcoin locks funds based on commitment
3. Challenge period (e.g., 7 days)
4. If no fraud proof, funds release
5. If fraud proof valid, solver loses collateral
```

**Pros**:
- ✅ Works within Bitcoin's constraints
- ✅ No fork or protocol changes needed
- ✅ Can verify arbitrary computation (including ZK proofs)

**Cons**:
- ❌ Long finality (challenge period = days)
- ❌ Requires significant collateral
- ❌ High complexity (bisection protocol)
- ❌ Not production-ready yet

**Projects**:
- **BitVM**: https://bitvm.org/ (Robin Linus, 2023)
- **BitVM2**: Improved variant with covenant emulation

#### Approach 2: Discrete Log Contracts (DLCs) + Oracle

**Status**: Production-ready but requires trusted oracle

**Concept**: Oracle signs outcome, Bitcoin script releases based on signature.

**How it works**:
```
1. Oracle observes OL chain state
2. Oracle signs: "OL transaction T exists" or "does not exist"
3. Bitcoin script: IF oracle_sig(exists) THEN release to Alice
4. IF timeout THEN refund to Bob
```

**For Atomic Swaps**:
```bitcoin_script
OP_IF
  # Oracle confirmed OL transaction
  <oracle_pubkey> OP_CHECKSIG
  <alice_pubkey> OP_CHECKSIG
OP_ELSE
  # Timeout refund
  <timeout> OP_CHECKLOCKTIMEVERIFY OP_DROP
  <bob_pubkey> OP_CHECKSIG
OP_ENDIF
```

**Pros**:
- ✅ Production-ready (used by DeFi protocols)
- ✅ Fast finality (minutes)
- ✅ Relatively simple

**Cons**:
- ❌ Requires trusted oracle (centralization)
- ❌ Oracle can censor or lie
- ❌ Not fully trustless

**Projects**:
- **DLC.link**: Bitcoin DeFi bridge using DLCs
- **Chainlink**: Oracle network (exploring Bitcoin support)

#### Approach 3: Adapter Signatures (Scriptless Scripts)

**Status**: Production-ready for specific use cases

**Concept**: Use Schnorr signature adapters to create atomic swaps without revealing secrets on-chain.

**How it works**:
```
1. Alice creates adaptor signature for Bitcoin transaction
   - Valid only when combined with secret s
2. Bob creates adaptor signature for OL transaction (same secret)
3. Alice publishes her signature → reveals s
4. Bob uses s to complete his transaction
```

**Key Property**: Atomicity through cryptography, not through on-chain state.

**Bitcoin Script**:
```
# Alice's Bitcoin output (locked for Bob with adaptor)
<bob_pubkey> OP_CHECKSIG

# Standard P2PKH, but signature is adaptor signature
# When Bob publishes valid signature, he reveals secret s
```

**Pros**:
- ✅ Efficient (minimal on-chain footprint)
- ✅ Privacy-preserving (secret not visible on-chain)
- ✅ Works with Taproot (Schnorr signatures)
- ✅ Production-ready (Lightning Network uses this)

**Cons**:
- ❌ Doesn't verify external chain state directly
- ❌ Still needs HTLC-style coordination
- ❌ No direct ZK proof verification

**Projects**:
- **Lightning Network**: Uses adaptor signatures for submarine swaps
- **Monero ↔ Bitcoin**: XMR-BTC atomic swaps (COMIT Network)

#### Approach 4: ZK Light Client on OL Side (Bitcoin → OL)

**Status**: Theoretically possible, practical with modern ZK systems

**Concept**: Instead of verifying ZK proofs on Bitcoin, verify Bitcoin state on OL with ZK.

**How it works**:
```
1. Bob locks BTC using standard HTLC (hash lock)
2. OL chain runs ZK light client that verifies Bitcoin state
3. Someone generates ZK proof: "Bitcoin block B contains transaction T locking BTC"
4. OL verifies proof, releases OL tokens to Bob
5. Bob uses secret from OL transaction to unlock Bitcoin
```

**Architecture**:
```
Bitcoin (Simple HTLC)
    ↓
    | ZK Proof of Bitcoin transaction
    ↓
OL Chain (ZK Light Client)
    ↓
    | Standard HTLC secret revelation
    ↓
Bitcoin (Unlock with secret)
```

**Pros**:
- ✅ Bitcoin side uses simple HTLCs (proven, secure)
- ✅ All complex verification happens on OL (cheaper, more capable)
- ✅ Asymmetric design (Bitcoin minimal, OL does heavy lifting)
- ✅ Actually feasible with current ZK tech

**Cons**:
- ⚠️  Still requires HTLC timelocks (24-48h for safety)
- ⚠️  ZK proof generation time (10-60 seconds for Bitcoin)
- ⚠️  Need ZK prover infrastructure

**Implementation Details**:

```move
// OL module to verify Bitcoin transactions
module ol_framework::bitcoin_light_client {
    use std::hash;

    struct BitcoinHeader has store, drop {
        version: u32,
        prev_block: vector<u8>,
        merkle_root: vector<u8>,
        timestamp: u32,
        bits: u32,
        nonce: u32,
    }

    // Verify ZK proof that Bitcoin transaction exists
    public fun verify_btc_transaction(
        block_header: BitcoinHeader,
        tx_hash: vector<u8>,
        merkle_proof: vector<u8>,
        zk_proof: vector<u8>,
    ): bool {
        // Verify ZK proof that:
        // 1. Block header is valid (POW check)
        // 2. Transaction is in Merkle tree
        // 3. Transaction locks correct amount to correct address

        zk_verifier::verify(
            bitcoin_circuit_id(),
            zk_proof,
            vector[block_header, tx_hash, merkle_proof]
        )
    }
}
```

**Projects working on Bitcoin ZK light clients**:
- **=nil; Foundation**: zkLLVM for Bitcoin state proofs
- **Polyhedra Network**: Bitcoin → Ethereum bridge using ZK
- **Gevulot**: Bitcoin ZK verification infrastructure

#### Approach 5: Taproot + MuSig2 (Federation-based)

**Status**: Production-ready

**Concept**: Multi-signature threshold wallet controlled by federation.

**How it works**:
```
1. Federation of N signers (e.g., 5-of-7)
2. Bitcoin funds locked in Taproot MuSig address
3. Federation observes OL chain
4. If OL transaction valid, federation signs Bitcoin release
5. Threshold signature releases Bitcoin
```

**Bitcoin Script** (Taproot):
```
# Internal key: MuSig aggregated public key of federation
# Script path: Timeout refund
<timeout> OP_CHECKLOCKTIMEVERIFY OP_DROP <bob_pubkey> OP_CHECKSIG
```

**Pros**:
- ✅ Production-ready (Liquid, tBTC use variants)
- ✅ Fast finality (minutes)
- ✅ Flexible trust model (N-of-M threshold)
- ✅ Privacy (MuSig looks like single sig)

**Cons**:
- ❌ Requires trusted federation
- ❌ Centralization risk
- ❌ Liveness depends on federation

**Projects**:
- **Liquid**: Bitcoin sidechain (Blockstream)
- **tBTC v2**: Threshold ECDSA for Bitcoin (Threshold Network)
- **Thorchain**: TSS-based cross-chain swaps

### 12.3 Comparison for Bitcoin Integration

| Approach | Trust Model | Finality | Complexity | Production Ready? |
|----------|-------------|----------|------------|-------------------|
| **BitVM** | Trustless (fraud proofs) | 7+ days | Very High | No (research) |
| **DLC Oracle** | Trusted oracle | Minutes | Low | Yes |
| **Adapter Signatures** | Trustless | Hours (HTLC) | Medium | Yes (Lightning) |
| **ZK Light Client (OL side)** | Trustless | Hours (HTLC) | High | Partial (tech ready) |
| **Taproot Federation** | Threshold trust | Minutes | Medium | Yes |

### 12.4 Recommended Approach for OL ↔ Bitcoin

**Phase 1: HTLC + Adapter Signatures (Launch)**
- Use battle-tested Bitcoin HTLC with Taproot
- Combine with adapter signatures for efficiency
- Accept 24-48h settlement time
- Fully trustless, works today

**Implementation**:
```
1. Alice locks OL tokens (48h timelock)
2. Bob locks BTC with adaptor signature (24h timelock)
3. Alice claims BTC (reveals secret via signature)
4. Bob observes secret, claims OL tokens
```

**Phase 2: ZK Light Client Verification (6-12 months)**
- Build ZK light client for Bitcoin on OL chain
- Keep Bitcoin side simple (just HTLCs)
- Asymmetric architecture (Bitcoin minimal, OL complex)
- Reduce proof generation time to <60 seconds

**Bitcoin side** (unchanged):
```bitcoin_script
OP_IF
  # Hash lock path
  OP_SHA256 <hash> OP_EQUALVERIFY <alice_pk> OP_CHECKSIG
OP_ELSE
  # Timeout refund
  <timeout> OP_CHECKLOCKTIMEVERIFY OP_DROP <bob_pk> OP_CHECKSIG
OP_ENDIF
```

**OL side** (ZK verification):
```move
public entry fun complete_btc_swap(
    user: &signer,
    swap_id: u64,
    btc_block_header: vector<u8>,
    btc_tx: vector<u8>,
    merkle_proof: vector<u8>,
    zk_proof: vector<u8>,
) {
    // Verify ZK proof of Bitcoin transaction
    assert!(
        bitcoin_light_client::verify_btc_transaction(
            btc_block_header,
            btc_tx,
            merkle_proof,
            zk_proof
        ),
        E_INVALID_BTC_PROOF
    );

    // Release OL tokens
    // ...
}
```

**Phase 3: BitVM Integration (Future/Experimental)**
- If BitVM matures, integrate for full trustlessness
- Eliminate HTLC timelocks on Bitcoin side
- Still accept challenge period for finality

### 12.5 Bitcoin ZK Proof Generation Performance

**Current state-of-the-art** (as of 2024):

**Proving Bitcoin block validity**:
- **=nil; Foundation**: ~30 seconds for SPV proof
- **Polyhedra zkBridge**: ~45 seconds for Bitcoin block
- **zkSNARK proof size**: ~200 bytes - ~2KB

**Proving transaction inclusion (Merkle proof)**:
- **Basic Merkle proof**: <5 seconds
- **With full POW verification**: ~30-60 seconds
- **Recursive proof aggregation**: Add 10-20 seconds

**Total time for Bitcoin → OL swap**:
```
1. Bob locks BTC (10 minutes - Bitcoin block confirmation)
2. Generate ZK proof of BTC lock (30-60 seconds)
3. Submit proof to OL (6 seconds - OL block)
4. Verify proof on OL (instant - verification is fast)
5. Bob receives OL tokens

Total: ~11-12 minutes (mostly Bitcoin block time)
```

### 12.6 Key Insights for Bitcoin Integration

**1. Bitcoin should be minimal**
- Use standard HTLCs (proven, secure)
- Don't try to verify ZK proofs on Bitcoin (impossible/impractical)
- Keep Bitcoin scripts simple for auditability

**2. OL should do the heavy lifting**
- ZK light client for Bitcoin on OL chain
- Verify Bitcoin transactions with ZK proofs
- Orderbook and matching logic on OL

**3. Accept Bitcoin's slow block times**
- 10 minute blocks are fundamental to Bitcoin
- Can't be avoided for security
- Design UX around this (show "confirming" state)

**4. Asymmetric design is crucial**
- Bitcoin: Escrow only (simple HTLC)
- OL: All business logic + ZK verification
- Same pattern as OL ↔ ETH architecture

**5. Multiple paths forward**
- Launch: HTLCs (trustless, slow)
- Near-term: ZK light client (trustless, faster)
- Long-term: BitVM (trustless, no timelock delays)

### 12.7 Research Resources

**BitVM**:
- **Whitepaper**: https://bitvm.org/bitvm.pdf
- **BitVM2 Specification**: https://bitvm.org/bitvm2
- **Implementation**: https://github.com/BitVM/BitVM

**Bitcoin ZK Light Clients**:
- **=nil; Foundation Bitcoin proofs**: https://nil.foundation/blog/post/bitcoin_zk
- **Polyhedra zkBridge**: "zkBridge: Trustless Cross-chain Bridges Made Practical"
- **ZeroSync**: Bitcoin STARK proofs project

**Adapter Signatures**:
- **Scriptless Scripts**: https://github.com/ElementsProject/scriptless-scripts
- **Lightning Network Spec**: https://github.com/lightning/bolts
- **COMIT XMR-BTC**: https://github.com/comit-network/xmr-btc-swap

**Taproot & MuSig**:
- **BIP 340-342**: Schnorr, Taproot, Tapscript
- **MuSig2 Paper**: "MuSig2: Simple Two-Round Schnorr Multi-Signatures"
- **tBTC v2**: https://docs.threshold.network/app-development/tbtc-v2

**Bitcoin DLCs**:
- **DLC Specification**: https://github.com/discreetlogcontracts/dlcspecs
- **DLC.link**: https://www.dlc.link/

---

## Appendix A: Reference Code Examples

### Complete Move HTLC Module

```move
module ol_framework::atomic_swap {
    use std::signer;
    use std::hash;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_SWAP_ALREADY_EXISTS: u64 = 1;
    const E_SWAP_NOT_FOUND: u64 = 2;
    const E_INVALID_PREIMAGE: u64 = 3;
    const E_TIME_LOCK_NOT_EXPIRED: u64 = 4;
    const E_ALREADY_WITHDRAWN: u64 = 5;
    const E_ALREADY_REFUNDED: u64 = 6;
    const E_NOT_RECEIVER: u64 = 7;
    const E_NOT_SENDER: u64 = 8;
    const E_TIMELOCK_IN_PAST: u64 = 9;
    const E_TIMELOCK_TOO_FAR: u64 = 10;
    const E_INVALID_AMOUNT: u64 = 11;

    /// Swap agreement stored at sender's address
    struct SwapAgreement<phantom CoinType> has key {
        receiver: address,
        amount: Coin<CoinType>,
        hash_lock: vector<u8>,
        time_lock: u64,
        withdrawn: bool,
        refunded: bool,
        preimage: vector<u8>,
        new_swap_events: EventHandle<NewSwapEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        refund_events: EventHandle<RefundEvent>,
    }

    struct NewSwapEvent has drop, store {
        sender: address,
        receiver: address,
        amount: u64,
        hash_lock: vector<u8>,
        time_lock: u64,
    }

    struct WithdrawEvent has drop, store {
        sender: address,
        receiver: address,
        preimage: vector<u8>,
    }

    struct RefundEvent has drop, store {
        sender: address,
        receiver: address,
    }

    public entry fun new_swap<CoinType>(
        sender: &signer,
        receiver: address,
        amount: u64,
        hash_lock: vector<u8>,
        time_lock: u64,
    ) {
        let sender_addr = signer::address_of(sender);

        // Validations
        assert!(!exists<SwapAgreement<CoinType>>(sender_addr), E_SWAP_ALREADY_EXISTS);
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(time_lock > timestamp::now_seconds(), E_TIMELOCK_IN_PAST);
        assert!(time_lock < timestamp::now_seconds() + (30 * 24 * 3600), E_TIMELOCK_TOO_FAR);

        // Withdraw coins from sender
        let coins = coin::withdraw<CoinType>(sender, amount);

        // Create swap agreement
        let swap = SwapAgreement<CoinType> {
            receiver,
            amount: coins,
            hash_lock,
            time_lock,
            withdrawn: false,
            refunded: false,
            preimage: vector::empty(),
            new_swap_events: account::new_event_handle<NewSwapEvent>(sender),
            withdraw_events: account::new_event_handle<WithdrawEvent>(sender),
            refund_events: account::new_event_handle<RefundEvent>(sender),
        };

        event::emit_event(&mut swap.new_swap_events, NewSwapEvent {
            sender: sender_addr,
            receiver,
            amount,
            hash_lock,
            time_lock,
        });

        move_to(sender, swap);
    }

    public entry fun withdraw<CoinType>(
        receiver: &signer,
        sender: address,
        preimage: vector<u8>,
    ) acquires SwapAgreement {
        let receiver_addr = signer::address_of(receiver);

        // Get swap agreement
        assert!(exists<SwapAgreement<CoinType>>(sender), E_SWAP_NOT_FOUND);
        let swap = borrow_global_mut<SwapAgreement<CoinType>>(sender);

        // Validations
        assert!(receiver_addr == swap.receiver, E_NOT_RECEIVER);
        assert!(!swap.withdrawn, E_ALREADY_WITHDRAWN);
        assert!(!swap.refunded, E_ALREADY_REFUNDED);

        // Verify preimage
        let computed_hash = hash::sha2_256(preimage);
        assert!(computed_hash == swap.hash_lock, E_INVALID_PREIMAGE);

        // Update state
        swap.withdrawn = true;
        swap.preimage = preimage;

        // Transfer coins
        let amount = coin::value(&swap.amount);
        let coins = coin::extract_all(&mut swap.amount);
        coin::deposit(receiver_addr, coins);

        event::emit_event(&mut swap.withdraw_events, WithdrawEvent {
            sender,
            receiver: receiver_addr,
            preimage,
        });
    }

    public entry fun refund<CoinType>(
        sender: &signer,
        receiver: address,
    ) acquires SwapAgreement {
        let sender_addr = signer::address_of(sender);

        // Get swap agreement
        assert!(exists<SwapAgreement<CoinType>>(sender_addr), E_SWAP_NOT_FOUND);
        let swap = borrow_global_mut<SwapAgreement<CoinType>>(sender_addr);

        // Validations
        assert!(swap.receiver == receiver, E_NOT_RECEIVER);
        assert!(!swap.withdrawn, E_ALREADY_WITHDRAWN);
        assert!(!swap.refunded, E_ALREADY_REFUNDED);
        assert!(timestamp::now_seconds() >= swap.time_lock, E_TIME_LOCK_NOT_EXPIRED);

        // Update state
        swap.refunded = true;

        // Return coins to sender
        let coins = coin::extract_all(&mut swap.amount);
        coin::deposit(sender_addr, coins);

        event::emit_event(&mut swap.refund_events, RefundEvent {
            sender: sender_addr,
            receiver,
        });
    }

    #[view]
    public fun get_swap_details<CoinType>(sender: address): (address, u64, vector<u8>, u64, bool, bool) acquires SwapAgreement {
        assert!(exists<SwapAgreement<CoinType>>(sender), E_SWAP_NOT_FOUND);
        let swap = borrow_global<SwapAgreement<CoinType>>(sender);
        (
            swap.receiver,
            coin::value(&swap.amount),
            swap.hash_lock,
            swap.time_lock,
            swap.withdrawn,
            swap.refunded
        )
    }
}
```

---

## Appendix B: CLI Tool Example

```python
#!/usr/bin/env python3
"""
Atomic Swap CLI for OL ↔ Ethereum
"""

import click
import hashlib
import time
from web3 import Web3
from ol_sdk import OLClient

@click.group()
def cli():
    """Atomic Swap between OL and Ethereum"""
    pass

@cli.command()
@click.option('--ol-amount', type=int, required=True, help='OL amount to send')
@click.option('--eth-amount', type=float, required=True, help='ETH amount to receive')
@click.option('--counterparty-ol', required=True, help='Counterparty OL address')
@click.option('--counterparty-eth', required=True, help='Counterparty ETH address')
def initiate(ol_amount, eth_amount, counterparty_ol, counterparty_eth):
    """Initiate a new atomic swap"""

    # Generate secret
    secret = os.urandom(32)
    hash_lock = hashlib.sha256(secret).digest()

    # Save secret securely
    save_secret(secret, hash_lock.hex())

    # Calculate timelocks
    now = int(time.time())
    ol_timelock = now + (48 * 3600)  # 48 hours

    # Create swap on OL chain
    ol = OLClient()
    tx = ol.create_atomic_swap(
        receiver=counterparty_ol,
        amount=ol_amount,
        hash_lock=hash_lock.hex(),
        timelock=ol_timelock
    )

    click.echo(f"✓ Created swap on OL chain")
    click.echo(f"  Hash lock: {hash_lock.hex()}")
    click.echo(f"  OL timelock: {ol_timelock} ({time.ctime(ol_timelock)})")
    click.echo(f"  TX: {tx.hash}")
    click.echo(f"\nShare this hash_lock with counterparty: {hash_lock.hex()}")
    click.echo(f"Wait for counterparty to lock {eth_amount} ETH on Ethereum")

@cli.command()
@click.option('--contract-id', required=True, help='Ethereum contract ID')
@click.option('--hash-lock', required=True, help='Hash lock from initiator')
def withdraw_eth(contract_id, hash_lock):
    """Withdraw ETH using secret"""

    # Retrieve secret
    secret = load_secret(hash_lock)

    # Withdraw from Ethereum
    eth = Web3(Web3.HTTPProvider('http://localhost:8545'))
    htlc = eth.eth.contract(address=HTLC_ADDRESS, abi=HTLC_ABI)

    tx = htlc.functions.withdraw(
        bytes.fromhex(contract_id),
        secret
    ).transact({'from': eth.eth.defaultAccount})

    receipt = eth.eth.wait_for_transaction_receipt(tx)

    click.echo(f"✓ Withdrew ETH successfully")
    click.echo(f"  TX: {receipt.transactionHash.hex()}")
    click.echo(f"  Secret revealed: {secret.hex()}")

@cli.command()
@click.option('--sender', required=True, help='OL swap sender address')
@click.option('--secret', required=True, help='Secret preimage')
def withdraw_ol(sender, secret):
    """Withdraw OL using revealed secret"""

    # Withdraw from OL
    ol = OLClient()
    tx = ol.withdraw_atomic_swap(
        sender=sender,
        preimage=secret
    )

    click.echo(f"✓ Withdrew OL successfully")
    click.echo(f"  TX: {tx.hash}")

if __name__ == '__main__':
    cli()
```

---

## 10. State of the Art: Beyond HTLCs

While HTLCs remain the most battle-tested approach for atomic swaps, recent innovations have emerged that address HTLC limitations and offer new capabilities. This section explores cutting-edge alternatives and complementary technologies.

### 10.1 Signed Instructions & State Confirmations

Instead of generalized "intents", atomic swaps need **narrow, specific signed confirmations** of expected outcomes and state conditions.

#### Core Concept

Users sign **instructions** that confirm:
1. What they expect to happen
2. What state must be true
3. What they authorize

**Not a generalized intent system** - just confirmation signatures for atomic swap operations.

#### Three Types of Signed Confirmations

**1. Order Confirmation (Alice on OL)**
```typescript
// Alice signs: "I confirm I want to sell 100 OL at this price"
interface OrderConfirmation {
  type: "SELL_ORDER"
  trader: Address              // Alice's OL address
  ol_amount: 100_000_000       // Exactly 100 OL
  min_eth_price: 0.01          // Minimum 0.01 ETH per OL
  eth_recipient: "0xalice_eth" // Where to send ETH

  // State checks
  expected_ol_balance: 150_000_000  // I expect to have at least 150 OL
  nonce: 5                          // Prevents replay
  expiry: 1234567890                // Expires after this timestamp
}
```

**2. Match Confirmation (Bob on OL)**
```typescript
// Bob signs: "I confirm I will provide ETH for this order"
interface MatchConfirmation {
  type: "BUY_ORDER"
  order_id: "abc123"           // Which order I'm matching
  eth_amount: 1_000_000_000    // Exactly 1 ETH I'll provide
  ol_recipient: "0xbob_ol"     // Where to send OL

  // State checks
  expected_eth_balance: 2_000_000_000  // I expect to have 2 ETH in escrow
  expected_order_status: "OPEN"        // Order must still be open
  nonce: 3
  expiry: 1234567900
}
```

**3. Claim Confirmation (Alice on ETH)**
```typescript
// Alice signs: "I confirm Bob matched my order, I'm claiming ETH"
interface ClaimConfirmation {
  type: "CLAIM_ETH"
  swap_id: "swap_xyz"
  bob_eth_address: "0xbob"
  amount: 1_000_000_000

  // Proof that swap was matched on OL
  ol_swap_proof: bytes         // ZK proof of OL state

  // State checks
  expected_bob_balance: 2_000_000_000  // Bob must have this in escrow
  nonce: 6
  expiry: 1234567910
}
```

#### State Verification Pattern

**Goal**: Verify expected state matches actual state before executing instruction.

**Simple Two-Step Process**:
1. **Check expected state** (balance, nonce, order status)
2. **Execute instruction** (only if state matches)

### Implementation on Both Chains

#### On OL Chain: Order + Match Confirmations

```move
module ol_framework::swap_confirmations {
    struct OrderConfirmation has drop, copy {
        trader: address,
        ol_amount: u64,
        min_eth_price: u64,
        eth_recipient: vector<u8>,

        // Expected state at execution
        expected_ol_balance: u64,
        nonce: u64,
        expiry: u64,
    }

    struct MatchConfirmation has drop, copy {
        buyer: address,
        order_id: u64,
        eth_amount: u64,
        ol_recipient: address,

        // Expected state at execution
        expected_eth_balance: u64,  // In OL-tracked escrow
        expected_order_status: u8,  // OPEN = 1
        nonce: u64,
        expiry: u64,
    }

    // Alice creates order with signed confirmation
    public entry fun create_order_with_confirmation(
        alice: &signer,
        confirmation: OrderConfirmation,
        signature: vector<u8>,
    ) acquires UserBalance, OrderBook {
        // Verify Alice signed this confirmation
        assert!(
            verify_order_signature(confirmation, signature),
            E_INVALID_SIGNATURE
        );

        let alice_addr = signer::address_of(alice);
        let balance = borrow_global<UserBalance>(alice_addr);

        // CHECK EXPECTED STATE
        assert!(
            balance.amount >= confirmation.expected_ol_balance,
            E_BALANCE_MISMATCH
        );
        assert!(
            balance.nonce == confirmation.nonce,
            E_NONCE_MISMATCH
        );
        assert!(
            timestamp::now_seconds() < confirmation.expiry,
            E_EXPIRED
        );

        // State matches, execute
        let coins = coin::withdraw<LibraCoin>(alice, confirmation.ol_amount);

        // Create order
        // ... (normal orderbook logic)

        // Increment nonce
        balance.nonce = balance.nonce + 1;
    }

    // Bob matches order with signed confirmation
    public entry fun match_order_with_confirmation(
        bob: &signer,
        confirmation: MatchConfirmation,
        signature: vector<u8>,
    ) acquires ETHBalance, OrderBook {
        // Verify Bob signed this confirmation
        assert!(
            verify_match_signature(confirmation, signature),
            E_INVALID_SIGNATURE
        );

        let bob_addr = signer::address_of(bob);
        let eth_balance = borrow_global_mut<ETHBalance>(bob_addr);
        let orderbook = borrow_global_mut<OrderBook>(@ol_framework);
        let order = get_order(&orderbook, confirmation.order_id);

        // CHECK EXPECTED STATE
        assert!(
            eth_balance.available >= confirmation.expected_eth_balance,
            E_INSUFFICIENT_ETH
        );
        assert!(
            order.status == confirmation.expected_order_status,
            E_ORDER_STATUS_MISMATCH
        );
        assert!(
            eth_balance.nonce == confirmation.nonce,
            E_NONCE_MISMATCH
        );
        assert!(
            timestamp::now_seconds() < confirmation.expiry,
            E_EXPIRED
        );

        // State matches, execute match
        eth_balance.available = eth_balance.available - confirmation.eth_amount;
        eth_balance.locked = eth_balance.locked + confirmation.eth_amount;

        // Create swap
        // ... (normal swap logic)

        // Increment nonce
        eth_balance.nonce = eth_balance.nonce + 1;
    }
}
```

#### On ETH Chain: Claim Confirmation

```solidity
contract SwapEscrow {
    struct ClaimConfirmation {
        address claimer;           // Alice
        bytes32 swapId;
        address bobEthAddress;
        uint256 amount;
        uint256 expectedBobBalance;  // Expected state
        uint256 nonce;
        uint256 expiry;
        bytes olSwapProof;         // ZK proof swap matched on OL
    }

    mapping(address => uint256) public nonces;

    function claimWithConfirmation(
        ClaimConfirmation calldata confirmation,
        bytes calldata signature
    ) external {
        // Verify Alice signed this
        require(
            verifyClaimSignature(confirmation, signature),
            "Invalid signature"
        );

        // CHECK EXPECTED STATE
        require(
            balances[confirmation.bobEthAddress] >= confirmation.expectedBobBalance,
            "Bob balance mismatch"
        );
        require(
            nonces[confirmation.claimer] == confirmation.nonce,
            "Nonce mismatch"
        );
        require(
            block.timestamp < confirmation.expiry,
            "Expired"
        );
        require(
            swaps[confirmation.swapId].amount == 0,
            "Already claimed"
        );

        // Verify ZK proof that swap was matched on OL
        require(
            verifyOLSwapProof(
                confirmation.swapId,
                confirmation.bobEthAddress,
                confirmation.claimer,
                confirmation.amount,
                confirmation.olSwapProof
            ),
            "Invalid OL proof"
        );

        // State matches, lock funds for swap
        balances[confirmation.bobEthAddress] -= confirmation.amount;
        swaps[confirmation.swapId] = Swap({
            bob: confirmation.bobEthAddress,
            alice: confirmation.claimer,
            amount: confirmation.amount,
            timeout: block.timestamp + 1 hours,
            released: false
        });

        // Increment nonce
        nonces[confirmation.claimer]++;

        emit SwapLocked(confirmation.swapId, confirmation.claimer);
    }
}
```

### Why This Approach Works

**1. Narrow Scope**
- Not a generalized intent system
- Just three specific confirmation types:
  - Order confirmation (Alice)
  - Match confirmation (Bob)
  - Claim confirmation (Alice)

**2. Explicit State Expectations**
- User states exactly what they expect
- Contract validates expectations match reality
- Transaction fails if state changed

**3. Simple Validation Pattern**
```
1. Verify signature
2. Check expected_balance == actual_balance
3. Check expected_nonce == actual_nonce
4. Check expected_status == actual_status
5. Execute if all match
6. Increment nonce
```

**4. Works on Both Chains**
- OL: Same pattern for order/match confirmations
- ETH: Same pattern for claim confirmations
- Both check: balance, nonce, expiry, specific state

### Key Differences from Generalized Intents

| Generalized Intents | Narrow Confirmations |
|---------------------|----------------------|
| Open-ended outcomes | Specific: order, match, claim |
| Complex solver competition | Pre-defined operations |
| Flexible state conditions | Exact state expectations |
| General-purpose | Atomic swap specific |

### Benefits of Narrow Confirmations

**1. Predictable**
- User knows exactly what will happen
- No solver interpretation needed
- Clear error messages

**2. Secure**
- State checked before execution
- Nonce prevents replay attacks
- Expiry prevents stale confirmations
- Explicit balance checks

**3. Efficient**
- No complex solver logic
- No auction mechanisms
- Direct execution
- Clear failure modes

**4. Auditable**
- Three simple confirmation types
- Straightforward state checks
- Easy to verify correctness

### Example User Flow

**Alice wants to sell 100 OL for ETH:**

1. **Alice prepares order confirmation**:
```typescript
const orderConf = {
  trader: "0xalice_ol",
  ol_amount: 100_000_000,
  min_eth_price: 0.01,
  eth_recipient: "0xalice_eth",
  expected_ol_balance: 150_000_000,  // I have 150 OL
  nonce: 5,
  expiry: now() + 3600
}
// Alice signs with her OL key
const signature = sign(orderConf, alice_ol_key)
```

2. **Alice submits to OL chain**:
```
create_order_with_confirmation(orderConf, signature)
→ Checks: balance ≥ 150 OL? nonce == 5? not expired?
→ If yes: creates order, increments nonce
→ If no: transaction fails with specific error
```

3. **Bob sees order, prepares match confirmation**:
```typescript
const matchConf = {
  buyer: "0xbob_ol",
  order_id: 123,
  eth_amount: 1_000_000_000,  // 1 ETH
  ol_recipient: "0xbob_ol",
  expected_eth_balance: 2_000_000_000,  // I have 2 ETH in escrow
  expected_order_status: OPEN,
  nonce: 3,
  expiry: now() + 1800
}
const signature = sign(matchConf, bob_ol_key)
```

4. **Bob submits to OL chain**:
```
match_order_with_confirmation(matchConf, signature)
→ Checks: Bob's ETH balance ≥ 2 ETH? Order still OPEN? nonce == 3?
→ If yes: matches order, locks Bob's ETH, increments nonce
→ If no: transaction fails
```

5. **Alice prepares claim confirmation**:
```typescript
const claimConf = {
  claimer: "0xalice_eth",
  swap_id: "swap_xyz",
  bob_eth_address: "0xbob_eth",
  amount: 1_000_000_000,
  expected_bob_balance: 2_000_000_000,
  nonce: 6,
  expiry: now() + 1800,
  ol_swap_proof: generateZKProof(swap_match_on_ol)
}
const signature = sign(claimConf, alice_eth_key)
```

6. **Alice submits to ETH chain**:
```
claimWithConfirmation(claimConf, signature)
→ Checks: Bob's balance ≥ 2 ETH? nonce == 6? Valid ZK proof?
→ If yes: locks 1 ETH for Alice, increments nonce
→ If no: transaction fails
```

### State Check Failures

**If state doesn't match:**
```
Alice tries to create order with nonce=5
But Alice's actual nonce is 6 (she made another tx)
→ Transaction fails: "Nonce mismatch"
→ Alice updates confirmation with nonce=6
→ Tries again, succeeds
```

**If balance insufficient:**
```
Bob tries to match with expected_eth_balance=2 ETH
But Bob only has 1.5 ETH in escrow
→ Transaction fails: "Insufficient ETH"
→ Bob deposits more ETH
→ Tries again with updated confirmation
```

#### Approach 3: Permit2-Style Witness Pattern (Ethereum)

**Concept**: Use Uniswap's Permit2 pattern - user gives allowance to intent contract, solver calls with witness.

**Architecture**:
```solidity
// User approves Permit2 contract once
IERC20(token).approve(PERMIT2_ADDRESS, type(uint256).max);

// Intent executor uses Permit2
interface IPermit2 {
    function permitWitnessTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,  // Hash of intent conditions
        string calldata witnessTypeString,
        bytes calldata signature
    ) external;
}

contract IntentExecutor {
    function fillIntent(
        Intent calldata intent,
        bytes calldata signature
    ) external {
        // Construct witness (state conditions)
        bytes32 witness = keccak256(abi.encode(
            intent.nonce,
            intent.minBalance,
            intent.maxGasPrice
        ));

        // Check state BEFORE attempting transfer
        require(checkStateConditions(intent), "State invalid");

        // Transfer using Permit2 (atomic with witness)
        permit2.permitWitnessTransferFrom(
            permit,
            transferDetails,
            intent.user,
            witness,
            "IntentWitness(uint256 nonce,uint256 minBalance,uint256 maxGasPrice)",
            signature
        );

        // Execute intent fulfillment
        // ...
    }
}
```

#### Approach 4: View Functions for State Queries (Pre-Flight Checks)

**Concept**: Solver queries state before submitting, but still validates on-chain.

**On ETH**:
```solidity
contract IntentValidator {
    // Solver calls this BEFORE submitting transaction
    function validateIntentState(
        Intent calldata intent
    ) external view returns (bool valid, string memory reason) {
        // Check all state conditions
        if (userNonces[intent.user] != intent.nonce) {
            return (false, "Nonce mismatch");
        }
        if (IERC20(token).balanceOf(intent.user) < intent.conditions.minBalance) {
            return (false, "Insufficient balance");
        }
        if (block.timestamp >= intent.expiry) {
            return (false, "Expired");
        }

        return (true, "");
    }

    // Solver submits transaction only if validateIntentState passes
    function fillIntent(Intent calldata intent) external {
        // Still check on-chain (state may have changed)
        require(validateIntentState(intent), "Invalid state");
        // ...
    }
}
```

**On OL**:
```move
// View function for pre-flight check
#[view]
public fun validate_intent_state(
    intent: StatefulIntent
): (bool, u64) acquires UserBalance, OrderBook {
    // Check user balance
    if (!exists<UserBalance>(intent.user)) {
        return (false, E_NO_BALANCE)
    };

    let user_balance = borrow_global<UserBalance>(intent.user);

    // Check nonce
    if (user_balance.nonce != intent.conditions.nonce) {
        return (false, E_NONCE_MISMATCH)
    };

    // Check balance
    if (user_balance.amount < intent.conditions.min_balance) {
        return (false, E_INSUFFICIENT_BALANCE)
    };

    // Check expiry
    if (timestamp::now_seconds() >= intent.expiry) {
        return (false, E_EXPIRED)
    };

    return (true, 0)
}

// Solver queries this before submitting
public entry fun fill_intent(intent: StatefulIntent, ...) {
    let (valid, error_code) = validate_intent_state(intent);
    assert!(valid, error_code);
    // ...
}
```

#### Approach 5: State Root Commitments (Advanced)

**Concept**: Intent includes commitment to specific state root. Only executable if chain state matches.

**Example**:
```typescript
interface StateRootIntent {
  user: Address
  sell_amount: u64

  // Commitment to specific blockchain state
  ol_state_root: bytes32      // OL chain state root
  eth_state_root: bytes32     // Ethereum state root

  // Or specific account state
  user_account_hash: bytes32  // Hash of user's account state
}
```

**Validation**:
```move
public entry fun fill_intent_with_state_root(
    intent: StateRootIntent,
    account_proof: vector<u8>,  // Merkle proof
) {
    // Verify user's account state matches commitment
    let current_state_root = get_current_state_root();

    assert!(
        verify_account_state_proof(
            intent.user,
            intent.user_account_hash,
            account_proof,
            current_state_root
        ),
        E_STATE_MISMATCH
    );

    // Execute intent
}
```

**Problem**: Very brittle - any state change invalidates intent.

### Recommended Approach for OL ↔ ETH Swaps

**Use Approach 2 (State Conditions) + Approach 4 (Pre-Flight Checks)**

**On OL Chain**:
```move
module ol_framework::stateful_intent_swap {
    struct IntentConditions has drop, copy {
        min_ol_balance: u64,        // User must have this much OL
        nonce: u64,                 // Prevents replay
        min_eth_price: u64,         // Minimum acceptable price
        max_slippage: u64,          // Maximum price deviation
    }

    struct Intent has drop, copy {
        user: address,
        ol_amount: u64,
        min_eth_receive: u64,
        eth_recipient: vector<u8>,
        expiry: u64,
        conditions: IntentConditions,
    }

    // View function for pre-flight check
    #[view]
    public fun validate_intent(intent: Intent): (bool, u64)
        acquires UserBalance, OrderBook
    {
        // Check balance
        let user_bal = borrow_global<UserBalance>(intent.user);
        if (user_bal.amount < intent.conditions.min_ol_balance) {
            return (false, E_INSUFFICIENT_BALANCE)
        };

        // Check nonce
        if (user_bal.nonce != intent.conditions.nonce) {
            return (false, E_NONCE_MISMATCH)
        };

        // Check market conditions
        let orderbook = borrow_global<OrderBook>(@ol_framework);
        let best_price = get_best_eth_price(orderbook);
        if (best_price < intent.conditions.min_eth_price) {
            return (false, E_PRICE_TOO_LOW)
        };

        // Check expiry
        if (timestamp::now_seconds() >= intent.expiry) {
            return (false, E_EXPIRED)
        };

        (true, 0)
    }

    // Execution function
    public entry fun fill_intent(
        solver: &signer,
        intent: Intent,
        signature: vector<u8>,
    ) acquires UserBalance, OrderBook {
        // Verify signature
        assert!(verify_intent_signature(intent, signature), E_INVALID_SIG);

        // CRITICAL: Validate state conditions on-chain
        let (valid, error) = validate_intent(intent);
        assert!(valid, error);

        // Increment nonce to prevent replay
        let user_bal = borrow_global_mut<UserBalance>(intent.user);
        user_bal.nonce = user_bal.nonce + 1;

        // Execute swap
        // ...
    }
}
```

**On ETH Chain**:
```solidity
contract IntentSwapEscrow {
    struct IntentConditions {
        uint256 minEthBalance;    // Solver must have this in escrow
        uint256 nonce;            // Prevents replay
        uint256 maxGasPrice;      // Only execute if gas reasonable
    }

    struct Intent {
        address user;
        uint256 ethAmount;
        address olRecipient;
        uint256 expiry;
        IntentConditions conditions;
    }

    // View function for pre-flight validation
    function validateIntent(Intent calldata intent)
        external
        view
        returns (bool valid, string memory reason)
    {
        // Check solver balance
        if (balances[intent.user] < intent.conditions.minEthBalance) {
            return (false, "Insufficient escrow balance");
        }

        // Check nonce
        if (userNonces[intent.user] != intent.conditions.nonce) {
            return (false, "Nonce mismatch");
        }

        // Check gas price
        if (tx.gasprice > intent.conditions.maxGasPrice) {
            return (false, "Gas price too high");
        }

        // Check expiry
        if (block.timestamp >= intent.expiry) {
            return (false, "Expired");
        }

        return (true, "");
    }

    function fillIntent(
        Intent calldata intent,
        bytes calldata signature,
        bytes calldata olProof  // ZK proof of OL state
    ) external {
        // Validate signature
        require(verifySignature(intent, signature), "Invalid signature");

        // CRITICAL: Validate state on-chain
        (bool valid, string memory reason) = validateIntent(intent);
        require(valid, reason);

        // Verify OL proof (that swap matched on OL)
        require(verifyOLSwapProof(olProof), "Invalid OL proof");

        // Increment nonce
        userNonces[intent.user]++;

        // Execute transfer
        // ...
    }
}
```

### Key Principles for State Verification

1. **Sign Over State Conditions**: Intent explicitly specifies required state
2. **Pre-Flight Checks**: Solvers query state before submitting (save gas)
3. **On-Chain Validation**: Always re-check state during execution
4. **Nonce Management**: Prevent replay attacks
5. **Atomic State Updates**: Increment nonce in same transaction
6. **View Functions**: Expose state validation as view functions
7. **Fail Fast**: Check cheapest conditions first (expiry, nonce)
8. **Clear Error Messages**: Help solvers understand why intent failed

#### Advantages Over HTLCs

| Aspect | HTLC | Intent-Based |
|--------|------|--------------|
| **UX** | User must initiate 2+ transactions | User signs once, solver handles rest |
| **Time** | Wait for counterparty lock + timelock | Near-instant if solver available |
| **Capital Efficiency** | Funds locked for 24-48 hours | Funds locked for seconds/minutes |
| **Failure Mode** | Must wait for refund timelock | Intent expires quickly |
| **Complexity** | User manages both sides | Solver abstracts complexity |

#### Disadvantages

- **Requires Solver Infrastructure**: Not fully peer-to-peer, depends on solver availability
- **Solver Trust Assumptions**: Solvers see intents before committing (MEV risk, can front-run)
- **Economic Viability**: Solvers need incentives (fees), may not exist for niche pairs
- **Censorship Risk**: Solvers can choose which intents to fulfill

#### Notable Intent Protocols

**1. Anoma / Namada**
- Generalized intent-centric architecture
- Multi-chain intent gossip network
- Uses zero-knowledge proofs for privacy
- Solver incentives via fees

**2. UniswapX**
- Intent-based DEX aggregation by Uniswap
- Fillers compete to provide best execution
- Dutch auction mechanism for price discovery
- Cross-chain swaps via intents (announced 2024)

**3. CoW Protocol (Coincidence of Wants)**
- Matches opposing intents directly (Alice wants ETH→OL, Bob wants OL→ETH)
- Reduces on-chain transactions
- Batch auctions for MEV protection
- Solvers compete for order flow

**4. Essential / SUAVE (MEV-focused)**
- Intent standard with privacy guarantees
- Encrypted intents prevent front-running
- Threshold decryption after commitment
- Cross-domain MEV optimization

#### Implementation Considerations for OL ↔ ETH

**Intent Structure**:
```typescript
interface CrossChainIntent {
  // Input: what user offers
  source_chain: "OL"
  source_asset: "0x1::libra_coin::LibraCoin"
  source_amount: 100_000_000
  source_address: "0xalice"

  // Output: what user wants
  dest_chain: "Ethereum"
  dest_asset: "0x0000...0000" // ETH
  dest_amount: 1000000000000000000 // 1 ETH
  dest_address: "0xalice_eth"

  // Constraints
  expiry: 1234567890 // Unix timestamp
  max_slippage: 0.01 // 1%

  // Signature
  signature: "0x..." // Alice's signature
}
```

**Solver Flow**:
1. Solver monitors intent mempool
2. Sees Alice's intent, calculates profitability
3. Sends 1 ETH to Alice's Ethereum address
4. Submits proof + Alice's signed intent to OL chain
5. Claims Alice's 100 OL tokens

**Security Challenge**: Preventing solver from claiming OL tokens without sending ETH
- **Solution 1**: Require on-chain proof of ETH transfer (oracle needed)
- **Solution 2**: Optimistic bridge (fraud proofs)
- **Solution 3**: ZK proof of Ethereum block inclusion (next section)

#### When to Use Intents vs HTLCs

**Use Intents when**:
- Solver infrastructure exists for your asset pair
- UX is critical (consumer-facing application)
- Speed matters more than full decentralization
- Users cannot manage multi-step flows

**Use HTLCs when**:
- Full peer-to-peer is required (no intermediaries)
- Asset pair is too niche for solvers
- Security is paramount over convenience
- Building foundational infrastructure

### 10.2 Zero-Knowledge Proof (ZKP) Based Swaps

#### Overview

Zero-knowledge proofs enable **verifiable computation**: proving that a computation was performed correctly without revealing the inputs. For atomic swaps, ZKPs can prove cross-chain events without oracles or bridges.

#### Core Innovation: ZK Light Clients

Traditional cross-chain verification requires trusting oracles or bridges. ZK light clients eliminate this trust assumption:

**Problem**: How can an Ethereum contract verify that an OL transaction occurred?

**ZK Solution**:
1. Generate ZK proof: "I know a valid OL block header H and a transaction T in block B such that T transferred 100 OL to address X"
2. Submit proof to Ethereum contract
3. Ethereum contract verifies proof (cheap, ~200k gas)
4. If valid, releases corresponding ETH

**Key Advantage**: Verification happens on-chain, no trusted intermediary needed.

#### ZKP Primitives for Cross-Chain Swaps

**1. ZK-SNARKs** (Zero-Knowledge Succinct Non-Interactive Arguments of Knowledge)
- **Pros**: Tiny proof size (~200 bytes), fast verification
- **Cons**: Requires trusted setup, complex circuits
- **Use case**: Proving Ethereum block headers on OL chain

**2. ZK-STARKs** (Scalable Transparent Arguments of Knowledge)
- **Pros**: No trusted setup, quantum-resistant, transparent
- **Cons**: Larger proofs (~100KB), slower verification
- **Use case**: Proving large state transitions

**3. Recursive SNARKs** (e.g., Halo 2, Nova)
- **Pros**: Prove proof-of-proof, constant-size final proof
- **Cons**: Complex to implement
- **Use case**: Aggregating many transaction proofs into one

#### Architecture: ZK Atomic Swaps

**Protocol Flow**:

```
1. Setup Phase:
   - Deploy ZK verifier contract on both chains
   - Verifier understands opposite chain's consensus rules

2. Alice locks 100 OL:
   - Creates OL transaction: "Lock 100 OL for Bob"
   - Gets transaction receipt + Merkle proof

3. Alice generates ZK proof:
   - Proof: "There exists a valid OL block B that includes
            transaction T locking 100 OL for Bob"
   - Proof includes: block hash, transaction hash, Merkle proof
   - Does NOT reveal: Alice's private key or signature

4. Alice submits proof to Ethereum:
   - Ethereum contract verifies ZK proof
   - If valid, contract knows OL-side lock exists
   - Contract auto-sends 1 ETH to Alice

5. Bob observes Ethereum payment:
   - Bob now generates ZK proof of Ethereum payment
   - Submits proof to OL chain
   - OL contract verifies and releases 100 OL to Bob
```

**Atomicity Guarantee**:
- Alice cannot get ETH without provably locking OL
- Bob cannot get OL without provably sending ETH
- No timelock needed (instant finality once proofs verified)

#### Real-World ZK Bridge Projects

**1. Succinct Labs / Telepathy**
- ZK light client for Ethereum ↔ other chains
- Proves Ethereum consensus (beacon chain) using SNARKs
- Used by bridges for trustless message passing
- ~$100M+ in TVL

**2. =nil; Foundation / zkLLVM**
- Compile any program to ZK circuits
- Generate proofs of arbitrary computation
- Use case: Prove Bitcoin block validity on Ethereum

**3. Polyhedra Network / zkBridge**
- Academic research turned production
- Proves consensus of multiple chains
- Deferred proof generation (doesn't block user transactions)
- Published at ACM CCS 2022

**4. Electron Labs**
- ZK light client for Ethereum on Cosmos chains
- Proves Ethereum state using Plonky2
- Reduces trust assumptions for IBC bridges

**5. Axiom (formerly Pryomasis)**
- ZK co-processor for Ethereum
- Prove historical on-chain data
- Use case: "Prove I sent transaction X in block Y"

#### Advantages Over HTLCs

| Aspect | HTLC | ZK-Based |
|--------|------|----------|
| **Trust** | Trustless (both parties) | Trustless (cryptographic proof) |
| **Speed** | Hours (timelock wait) | Minutes (proof generation + verification) |
| **Capital Efficiency** | Low (funds locked 24-48h) | High (instant settlement) |
| **Privacy** | Public (all amounts visible) | Private (ZK can hide amounts) |
| **Complexity** | Low (hash preimage) | High (ZK circuits, prover infrastructure) |

#### Disadvantages

- **Computational Cost**: Generating proofs is expensive (CPU/GPU intensive)
- **Latency**: Proof generation takes seconds to minutes
- **Complexity**: Requires ZK expertise to implement safely
- **Hardware Requirements**: Provers need significant resources
- **Immature Tooling**: ZK libraries still evolving rapidly

#### ZK + Intent Hybrid

**Optimal Architecture**: Combine intents with ZK proofs

1. **Alice signs intent**: "I want 1 ETH, will pay 100 OL"
2. **Solver fulfills intent**: Sends 1 ETH to Alice immediately
3. **Solver generates ZK proof**: Proves they sent 1 ETH to Alice
4. **Solver submits proof to OL**: Claims Alice's 100 OL

**Benefits**:
- **Fast UX**: Alice gets ETH instantly (solver takes risk)
- **No Trust**: Solver must provide ZK proof to claim OL
- **No Oracle**: ZK proof verifies Ethereum state directly

### 10.3 Other Promising Mechanisms

#### 1. Optimistic Cross-Chain Swaps

**Concept**: Assume transactions are valid, allow fraud proofs to challenge.

**How it Works**:
1. Alice posts: "I claim I sent 1 ETH to Bob on Ethereum (tx: 0xabc)"
2. OL contract releases 100 OL to Alice immediately
3. **Challenge period** (e.g., 7 days): Anyone can submit fraud proof
4. If fraud proof valid, Alice loses collateral
5. If no fraud proof, swap is final

**Advantages**:
- Fast: Instant settlement (optimistically)
- Cheap: No expensive proofs needed
- Simple: Easier to implement than ZK

**Disadvantages**:
- Capital inefficiency: Requires collateral
- Delay: Finality takes challenge period (days)
- Validator set needed: Someone must monitor and challenge

**Example**: Optimism and Arbitrum use optimistic rollups with this model

#### 2. Adapter Signatures (Signature-Based Swaps)

**Concept**: Cryptographic signatures that reveal secrets when claimed.

**How it Works**:
1. Alice creates **adaptor signature** for Ethereum transaction
2. Adaptor signature is valid only if combined with secret `s`
3. Bob creates adaptor signature for OL transaction (same secret)
4. Alice publishes her transaction → reveals `s`
5. Bob uses `s` to complete his transaction

**Advantages**:
- More efficient than HTLCs (smaller on-chain footprint)
- Built into some cryptographic schemes (Schnorr signatures)
- No timelock needed (atomicity via cryptography)

**Disadvantages**:
- Requires specific signature schemes (Schnorr, not ECDSA)
- Not natively supported on Ethereum (would need protocol changes)
- Complex to implement correctly

**Status**: Used in Bitcoin Lightning Network for submarine swaps

#### 3. Payment Channels & Layer 2 Swaps

**Concept**: Move swaps off-chain to layer 2 networks.

**Approaches**:

**a) Cross-Chain Payment Channels**
- Open bidirectional payment channels on both chains
- Perform swaps instantly within channels
- Only settle on-chain when closing channel
- **Example**: Lightning Network ↔ Raiden Network connectors

**b) Rollup-Native Swaps**
- Both assets live on rollups (Optimism, Arbitrage, zkSync)
- Use rollup's native bridge for asset transfer
- Atomic swaps within rollup (single sequencer)
- **Example**: Hop Protocol, Connext

**c) Cross-Rollup Communication**
- Rollups communicate via shared layer 1
- Atomic swaps coordinated through L1 proofs
- **Example**: Polymer (IBC for Ethereum rollups)

**Advantages**:
- Near-instant finality
- Low fees (off-chain execution)
- High throughput

**Disadvantages**:
- Requires both assets on L2
- Liquidity fragmentation
- L2 trust assumptions

#### 4. IBC (Inter-Blockchain Communication)

**Concept**: Cosmos's standardized cross-chain communication protocol.

**How it Works**:
1. Chains run light clients of each other
2. Merkle proofs verify cross-chain messages
3. Relayers pass messages between chains
4. Atomic execution via two-phase commit

**For Atomic Swaps**:
```
1. Alice locks 100 OL → generates proof
2. Relayer submits proof to Ethereum IBC module
3. Ethereum IBC module verifies proof
4. If valid, sends 1 ETH to Alice and generates proof
5. Relayer submits proof back to OL
6. OL releases 100 OL to escrow/Bob
```

**Advantages**:
- Standardized protocol (widely adopted in Cosmos)
- Proven in production ($1B+ in IBC volume)
- Composable (works for any message, not just swaps)

**Disadvantages**:
- Both chains must support IBC
- Light client overhead (expensive on Ethereum)
- Relayer dependency (liveness assumption)

**Status**: Mostly used in Cosmos ecosystem, emerging Ethereum support via Polymer/Composable Finance

#### 5. Threshold Signatures (TSS) & MPC

**Concept**: Multiple parties control a key collectively without any single party knowing the full key.

**How it Works**:
1. Create threshold wallet (e.g., 3-of-5 multisig)
2. Threshold signers collectively control locked assets
3. Signers release funds only if both sides of swap verified
4. Uses multi-party computation (MPC) to sign

**For Atomic Swaps**:
- Lock Alice's 100 OL in TSS wallet
- Lock Bob's 1 ETH in TSS wallet
- TSS committee verifies both locks
- Committee signs releases atomically

**Advantages**:
- No complex smart contracts needed
- Works with any blockchain (even Bitcoin)
- Flexible trust models (N-of-M thresholds)

**Disadvantages**:
- Requires trusted committee (not fully trustless)
- Committee liveness assumption
- Complex cryptography (TSS, MPC)

**Examples**:
- **Thorchain**: Uses TSS for cross-chain DEX
- **Axelar**: TSS-based cross-chain messaging
- **Qredo**: MPC custody for institutional swaps

#### 6. Atomic Swaps via Hash-Locked Tokens (Cross-Chain HTLCs with Tokens)

**Concept**: Wrap HTLCs into fungible tokens.

**How it Works**:
1. Alice creates HTLC locking 100 OL
2. OL contract mints "htlcToken" representing locked value
3. Alice transfers htlcToken to Bob (instantly, off-chain or on L2)
4. Bob redeems htlcToken by revealing secret

**Advantages**:
- HTLCs become transferable
- Can trade HTLC positions (DeFi composability)
- Reduces on-chain transactions

**Disadvantages**:
- Adds complexity layer
- Still needs timelock resolution
- Requires liquid market for htlcTokens

#### 7. Flash Swaps (Single-Transaction Atomicity)

**Concept**: Borrow assets, swap, repay in single transaction.

**How it Works (same-chain)**:
```solidity
1. Flash loan 1 ETH
2. Perform swap operations
3. Repay 1 ETH + fee
4. If step 3 fails, entire transaction reverts
```

**Cross-Chain Variant**:
- Not truly atomic across chains
- Requires trusted intermediary to flash loan
- Intermediary takes risk, charges fee

**Limitations**: Only works within single chain transaction context

### 10.4 Comparative Analysis

#### Security Model Comparison

| Approach | Trust Assumption | Liveness | Censorship Resistance |
|----------|------------------|----------|----------------------|
| **HTLC** | None (cryptography only) | Both users must be online | High (permissionless) |
| **Intent** | Solver existence | Solver availability | Medium (solver selection) |
| **ZK** | None (cryptography only) | Prover availability | High (permissionless) |
| **Optimistic** | Honest validator | Validator monitoring | Medium (validator required) |
| **IBC** | Light client security | Relayer availability | High (permissionless relaying) |
| **TSS** | Threshold committee | Committee availability | Low (committee controls) |

#### Cost Comparison

| Approach | On-Chain Cost | Off-Chain Cost | Total Cost |
|----------|---------------|----------------|------------|
| **HTLC** | Medium (3 txs) | None | Medium |
| **Intent** | Low (1-2 txs) | Solver fee | Low-Medium |
| **ZK** | Medium (proof verification) | High (proof generation) | Medium-High |
| **Optimistic** | Low (1 tx + potential fraud proof) | None | Low |
| **IBC** | High (Merkle proof verification) | Relayer fee | Medium-High |
| **TSS** | Low (threshold sig) | MPC computation | Medium |

#### Time to Finality

| Approach | Time to Finality | Notes |
|----------|------------------|-------|
| **HTLC** | 10 min - 48 hours | Timelock dependent |
| **Intent** | Seconds - minutes | Solver dependent |
| **ZK** | 5-30 minutes | Proof generation time |
| **Optimistic** | 1-7 days | Challenge period |
| **IBC** | 10-60 seconds | Chain finality dependent |
| **TSS** | Minutes | Committee coordination |

### 10.5 Recommendations for OL ↔ Ethereum

#### Phase 1: Production Launch (Months 1-3)
**Use HTLCs** for initial implementation:
- Battle-tested technology
- No dependencies on external infrastructure
- Pure peer-to-peer
- Foundation for future improvements

#### Phase 2: UX Improvements (Months 4-6)
**Add Intent Layer** on top of HTLCs:
- Solver can use HTLC protocol under the hood
- Users sign intents, solver executes HTLCs
- Maintains security while improving UX
- Optional: users can bypass and use HTLCs directly

#### Phase 3: Trust Minimization (Months 7-12)
**Integrate ZK Proofs**:
- Eliminate timelock delays
- Add ZK light client for Ethereum on OL
- Solvers submit ZK proofs instead of waiting for HTLC timelock
- Reduces capital lockup from 24-48h to minutes

#### Long-Term: Full Ecosystem
- **HTLCs**: For peer-to-peer, niche assets
- **Intents + ZK**: For consumer UX, popular pairs
- **IBC**: If OL joins Cosmos ecosystem
- **L2 Swaps**: For high-frequency, low-value swaps

### 10.6 Fair Market Behavior & Price Manipulation Prevention

A critical goal of any swap protocol is ensuring **fair market behavior** and preventing price manipulation. Traditional DEXes and swap platforms can suffer from users intentionally selecting sub-optimal prices to manipulate market signals.

#### The Price Manipulation Problem

**Attack Scenario**:
```
Current Orderbook (OL → ETH):
- Order A: 100 OL for 1.05 ETH (best price: 0.0105 ETH/OL)
- Order B: 100 OL for 1.00 ETH (worse price: 0.0100 ETH/OL)
- Order C: 100 OL for 0.95 ETH (worst price: 0.0095 ETH/OL)

Malicious Alice intentionally matches with Order C (0.95 ETH)
Even though Order A offers 1.05 ETH (11% better)
```

**Why This is Harmful**:
1. **False Price Signals**: Last traded price appears to be 0.0095 ETH/OL, misleading other traders
2. **Oracle Manipulation**: Price feeds that rely on last trade data report artificially low prices
3. **Wash Trading**: Alice and Bob (same entity) can coordinate to set arbitrary "market" prices
4. **Market Manipulation**: Artificially move price to trigger liquidations or stop-losses elsewhere
5. **MEV Extraction**: Manipulate price before large trade to extract value

#### Fundamental Issue: User Choice vs Fair Execution

**Problem**: In pure peer-to-peer atomic swaps, users can:
- Select which counterparty to swap with
- Ignore better available prices
- Coordinate with specific parties (wash trading)

**Trade-off**:
- **Full Freedom**: Users choose exact counterparty → enables price manipulation
- **Best Execution**: Protocol enforces best price → fair markets, no manipulation

#### Solution Architectures

### Architecture 1: Orderbook with Price-Time Priority (Recommended)

**Concept**: Enforce traditional exchange rules - best prices must be filled first.

**Orderbook Structure**:
```move
module ol_framework::atomic_swap_orderbook {
    struct OrderBook has key {
        // Buy orders (sorted by price DESC, then time ASC)
        buy_orders: vector<Order>,
        // Sell orders (sorted by price ASC, then time ASC)
        sell_orders: vector<Order>,
    }

    struct Order has store, drop {
        trader: address,
        amount: u64,
        price: u64,        // Price in smallest units
        timestamp: u64,
        hash_lock: vector<u8>,
        time_lock: u64,
    }

    /// Users CANNOT select specific orders - always matches best price
    public entry fun create_market_order(
        taker: &signer,
        amount: u64,
        side: u8,  // BUY or SELL
        max_slippage: u64,
    ) {
        // 1. Find best available price
        let best_orders = get_best_orders(side, amount);

        // 2. Verify price within slippage tolerance
        assert!(within_slippage(best_orders, max_slippage), E_SLIPPAGE_EXCEEDED);

        // 3. Automatically match with best orders (price-time priority)
        execute_matches(taker, best_orders);
    }

    /// Limit orders join the queue at specified price
    public entry fun create_limit_order(
        maker: &signer,
        amount: u64,
        limit_price: u64,
        side: u8,
    ) {
        // Insert order in price-time priority position
        insert_order_sorted(maker, amount, limit_price, side);

        // Check if any existing orders can immediately match
        try_match_against_book(amount, limit_price, side);
    }
}
```

**Key Properties**:
- Users submit **orders** (not select counterparties)
- Protocol enforces best price matching
- No ability to bypass better prices
- Prevents wash trading (can't choose your counterparty)

**Matching Logic**:
```rust
// Pseudocode for matching algorithm
fn match_order(taker_order: Order) -> Vec<Match> {
    let mut matches = vec![];
    let mut remaining = taker_order.amount;

    // Get all maker orders sorted by price-time priority
    let maker_orders = get_sorted_orders(opposite_side(taker_order.side));

    for maker_order in maker_orders {
        if remaining == 0 { break; }

        // Check price compatibility
        if !is_price_match(taker_order, maker_order) { break; }

        // Match as much as possible with this order
        let match_amount = min(remaining, maker_order.remaining);
        matches.push(Match {
            maker: maker_order.trader,
            taker: taker_order.trader,
            amount: match_amount,
            price: maker_order.price,  // Maker's price (better for taker)
        });

        remaining -= match_amount;
    }

    matches
}
```

### Architecture 2: Batch Auctions (CoW Protocol Model)

**Concept**: Collect all intents in a time window, solve for optimal clearing price.

**How It Works**:
1. **Submission Phase** (e.g., 30 seconds): Users submit signed intents
   ```typescript
   interface Intent {
     trader: Address
     sell_token: "OL"
     sell_amount: 100_000_000
     buy_token: "ETH"
     min_buy_amount: 950000000000000000  // Minimum acceptable
     expiry: timestamp
   }
   ```

2. **Solving Phase**: Solver finds optimal batch execution
   - Matches opposing intents when possible (CoW - Coincidence of Wants)
   - Fills remainder from external liquidity
   - Optimizes for **uniform clearing price** (everyone gets same price)

3. **Execution Phase**: All matched intents execute at same price
   ```
   Batch 123 Results:
   - Clearing price: 0.0102 ETH/OL
   - All OL sellers get 0.0102 ETH per OL
   - All ETH sellers get 98.04 OL per ETH
   - No one can manipulate price (uniform clearing)
   ```

**Advantages**:
- **MEV Protection**: All orders in batch execute at same price
- **Fair Price Discovery**: Uniform clearing price prevents manipulation
- **CoW Matching**: Direct matches reduce external liquidity needs
- **Better Execution**: Can be better than best individual order due to CoW

**Implementation**:
```move
module ol_framework::batch_auction {
    struct Batch has key {
        batch_id: u64,
        submission_end: u64,     // When submission window closes
        intents: vector<Intent>,
        clearing_price: Option<u64>,
        executed: bool,
    }

    /// Users submit intents to current batch
    public entry fun submit_intent(
        user: &signer,
        sell_amount: u64,
        min_receive: u64,
        expiry: u64,
    ) {
        let current_batch = get_or_create_current_batch();

        // Validate intent
        assert!(timestamp::now_seconds() < current_batch.submission_end, E_BATCH_CLOSED);

        // Add to batch
        vector::push_back(&mut current_batch.intents, Intent {
            trader: signer::address_of(user),
            sell_amount,
            min_receive,
            expiry,
            executed: false,
        });
    }

    /// Solver submits solution for batch
    public entry fun solve_batch(
        solver: &signer,
        batch_id: u64,
        clearing_price: u64,
        matches: vector<Match>,
    ) {
        let batch = borrow_global_mut<Batch>(batch_id);

        // Validate submission window closed
        assert!(timestamp::now_seconds() >= batch.submission_end, E_BATCH_STILL_OPEN);

        // Verify solution satisfies all intents
        assert!(verify_solution(batch, clearing_price, matches), E_INVALID_SOLUTION);

        // Execute all matches at uniform clearing price
        execute_batch(batch, clearing_price, matches);
    }
}
```

### Architecture 3: Dutch Auction (UniswapX Model)

**Concept**: Each intent is a Dutch auction - price improves over time until filled.

**How It Works**:
1. Alice submits intent: "Sell 100 OL for minimum 0.95 ETH, willing to accept up to 1.05 ETH"
2. Price starts at 1.05 ETH and linearly decreases over time
3. First solver willing to fill at current price wins
4. **Prevents manipulation**: Can't select sub-optimal price (auction finds best available)

**Intent Structure**:
```typescript
interface DutchAuctionIntent {
  trader: Address
  sell_token: "OL"
  sell_amount: 100_000_000

  // Dutch auction parameters
  start_price: 1.05  // Best price user hopes for
  end_price: 0.95    // Worst price user will accept
  decay_start: 1730000000  // Unix timestamp
  decay_duration: 120      // 2 minutes

  // Current price formula:
  // price(t) = start_price - (start_price - end_price) * (t - decay_start) / decay_duration
}
```

**Advantages**:
- **Fast Execution**: Solvers compete to fill as soon as profitable
- **No Manipulation**: Can't bypass better prices (auction mechanism enforces best execution)
- **Simple**: User expresses price range, market finds best price within range
- **MEV Resistance**: Decreasing price means front-running is unprofitable

**Implementation**:
```move
module ol_framework::dutch_auction {
    public fun get_current_price(intent: &Intent): u64 {
        let now = timestamp::now_seconds();

        if (now < intent.decay_start) {
            return intent.start_price
        };

        if (now >= intent.decay_start + intent.decay_duration) {
            return intent.end_price
        };

        let elapsed = now - intent.decay_start;
        let decay_fraction = elapsed / intent.decay_duration;
        let price_drop = (intent.start_price - intent.end_price) * decay_fraction;

        intent.start_price - price_drop
    }

    /// Solver fills intent at current auction price
    public entry fun fill_dutch_order(
        solver: &signer,
        intent_id: u64,
    ) {
        let intent = borrow_global_mut<Intent>(intent_id);
        let current_price = get_current_price(intent);

        // Solver must provide at least current auction price
        // (price decreases over time, so earlier fill = better for trader)
        execute_fill(solver, intent, current_price);
    }
}
```

### Architecture 4: Request For Quote (RFQ) with Best Execution Guarantee

**Concept**: Users request quotes from multiple market makers, protocol enforces best quote selection.

**How It Works**:
1. Alice broadcasts RFQ: "Want to sell 100 OL for ETH"
2. Market makers respond with quotes:
   ```
   MM-A: 1.00 ETH
   MM-B: 1.03 ETH (best)
   MM-C: 0.98 ETH
   ```
3. **Protocol automatically selects best quote** (MM-B)
4. Alice signs confirmation, HTLC created with MM-B

**Enforcement**:
```move
module ol_framework::rfq_swap {
    struct RFQ has key {
        requester: address,
        sell_amount: u64,
        quotes: vector<Quote>,
        accepted_quote: Option<u64>,
    }

    struct Quote has store, drop {
        market_maker: address,
        offered_amount: u64,
        expiry: u64,
        signature: vector<u8>,
    }

    /// User MUST accept best available quote
    public entry fun accept_quote(
        user: &signer,
        rfq_id: u64,
    ) {
        let rfq = borrow_global_mut<RFQ>(rfq_id);

        // Find best quote (highest offered amount)
        let best_quote_idx = find_best_quote(&rfq.quotes);

        // User can only accept best quote (no choice)
        rfq.accepted_quote = option::some(best_quote_idx);

        // Initiate HTLC with best market maker
        let best_quote = vector::borrow(&rfq.quotes, best_quote_idx);
        create_htlc_with_mm(user, best_quote);
    }
}
```

#### Comparison: Fair Market Architectures

| Architecture | Price Manipulation Protection | UX | Decentralization | Capital Efficiency |
|--------------|------------------------------|-----|------------------|-------------------|
| **Orderbook (Price-Time)** | Excellent (enforced matching) | Good | High | Medium (locked in orders) |
| **Batch Auction** | Excellent (uniform clearing) | Medium (wait for batch) | Medium (solver dependency) | High (brief lock) |
| **Dutch Auction** | Excellent (auction mechanism) | Excellent (fast) | Medium (solver competition) | High (brief lock) |
| **RFQ with Best Execution** | Good (best quote enforced) | Good | Medium (MM dependency) | High (just-in-time quotes) |
| **Pure P2P HTLC** | Poor (users choose counterparty) | Poor (manual matching) | Excellent | Low (long timelock) |

#### MEV Protection Strategies

Beyond price manipulation, atomic swaps must protect against MEV (Maximal Extractable Value) attacks:

**1. Sandwich Attack Protection**
```
Attack:
- Attacker sees Alice's swap order in mempool
- Front-runs with large buy order (raises price)
- Alice's order executes at inflated price
- Attacker back-runs with sell order (profits from spread)

Protection:
- Use batch auctions (uniform clearing price)
- Private mempools (Flashbots Protect, MEV-Blocker)
- Commit-reveal schemes (commit to intent hash, reveal later)
```

**2. Front-Running Protection**
```move
// Commit-reveal pattern
struct CommittedIntent has key {
    commitment: vector<u8>,  // Hash of intent details
    reveal_after: u64,
}

public entry fun commit_intent(user: &signer, commitment: vector<u8>) {
    // User submits hash(intent details + salt)
    // Details not visible to MEV bots
}

public entry fun reveal_intent(
    user: &signer,
    intent_details: IntentDetails,
    salt: vector<u8>,
) {
    // Verify hash matches commitment
    // Now execute intent
}
```

**3. Price Oracle Independence**
```
Problem: If swap protocol affects price oracle, can manipulate DeFi protocols

Solution:
- Don't use last-trade price for oracle
- Use Time-Weighted Average Price (TWAP)
- Use median of multiple sources
- Separate "reference price" from "execution price"
```

#### Implementation Recommendations for OL ↔ ETH

**Phase 1: Launch with Orderbook + Price-Time Priority**
- Proven model from traditional exchanges
- Easy to understand and audit
- Full protection against price manipulation
- No solver infrastructure needed initially

**Phase 2: Add Dutch Auction for Fast Trades**
- Users wanting speed can opt-in to Dutch auction
- Solvers fill automatically when profitable
- Better UX while maintaining fair pricing

**Phase 3: Implement Batch Auctions for MEV Protection**
- For users concerned about MEV
- Optimal for large trades
- Best execution guarantees

**Hybrid Approach (Recommended)**:
```
User Chooses Mode:

1. LIMIT ORDER → Joins orderbook with price-time priority
   - Pros: May get better than limit price, no active management
   - Cons: May wait for match

2. MARKET ORDER → Matches immediately against best available
   - Pros: Instant execution
   - Cons: Subject to current orderbook depth

3. DUTCH AUCTION → Intent filled by solver competition
   - Pros: Fast, competitive pricing
   - Cons: Requires solver infrastructure

4. BATCH AUCTION → Wait for next batch for best execution
   - Pros: MEV protection, optimal price
   - Cons: Wait time (e.g., 30s)

Protocol enforces fair execution in ALL modes
```

### 10.7 Research Resources

#### Intent Protocols
- **Anoma Whitepaper**: https://anoma.net/papers/whitepaper.pdf
- **UniswapX Documentation**: https://docs.uniswap.org/contracts/uniswapx/overview
- **CoW Protocol Research**: https://docs.cow.fi/

#### ZK Cross-Chain
- **Succinct Telepathy**: https://docs.succinct.xyz/
- **Polyhedra zkBridge Paper**: "zkBridge: Trustless Cross-chain Bridges Made Practical" (ACM CCS 2022)
- **Axiom Protocol**: https://docs.axiom.xyz/
- **=nil; Foundation**: https://nil.foundation/

#### IBC & Cosmos
- **IBC Specification**: https://github.com/cosmos/ibc
- **Polymer Labs**: https://www.polymerlabs.org/

#### Fair Market Design
- **CoW Protocol Docs**: https://docs.cow.fi/overview/coincidence-of-wants - Batch auction design
- **UniswapX Whitepaper**: Dutch auction mechanism for DEX aggregation
- **Flashbots Documentation**: https://docs.flashbots.net/ - MEV protection strategies
- **"The Cost of Decentralization in 0x and EtherDelta"** (2019) - Analysis of DEX manipulation

#### General Cross-Chain Research
- **"SoK: Communication Across Distributed Ledgers"** (2021) - Comprehensive survey
- **"Téléportation: Fast Cross-Chain Swaps"** (2023) - Optimistic approach
- **"Hermes: Threshold Cryptography for Cross-Chain Swaps"** (2024)
- **"High-Frequency Trading on Decentralized On-Chain Exchanges"** (2021) - MEV analysis

---

## 13. Security Analysis: Potential Exploits

**Critical vulnerabilities in the transaction chaining checkpoint design:**

### 13.1 CRITICAL: State Transition Proof Impossibility

**The Fundamental Problem:**

The design claims you can prove "Ethereum state advanced from block X to block Y" using just Merkle proofs, with no trusted intermediaries. **This is not actually possible.**

**Why:**

```solidity
function verifyStateTransition(
    bytes32 fromStateRoot,
    uint256 fromBlock,
    bytes32 toStateRoot,
    uint256 toBlock,
    bytes calldata proof
) internal pure returns (bool) {
    // HOW DO YOU IMPLEMENT THIS TRUSTLESSLY?
    //
    // Option 1: Verify PoW difficulty
    //   - Gas cost: ~1M gas per block header
    //   - For 100 blocks: ~100M gas (impossible)
    //
    // Option 2: Verify PoS validator signatures
    //   - Requires trusting validator set (trusted intermediary!)
    //   - This is exactly what we're trying to avoid
    //
    // Option 3: Trust the submitter
    //   - Not trustless!
    //
    // There's no Option 4.
}
```

**Attack Scenario:**

```
1. Alice submits checkpoint A claiming ETH block 1000 has state root 0xFAKE
2. Contract has no way to verify this is actually wrong
3. Contract accepts it (no trusted verifier to check)
4. Alice proves her swap is in the fake state
5. Alice withdraws ETH based on fabricated state
```

**Verdict:** The entire checkpoint chaining mechanism has a fatal flaw - it assumes you can verify blockchain state transitions without any trust, which is impossible.

---

### 13.2 CRITICAL: Genesis/Bootstrap Problem

**The Problem:**

The first transaction has no previous checkpoint to build on. How do we verify the first state root is correct?

**Code shows:**

```solidity
// 1. Verify state transition from previous checkpoint
if (prevCheckpointHash != bytes32(0)) {
    // verify transition
}
// If prevCheckpointHash == 0, no verification happens!
```

**Attack:**

```
1. Attacker submits FIRST transaction (prevCheckpoint = 0)
2. Claims Ethereum state root is 0xATTACKER_CONTROLS
3. No verification happens (it's the first one!)
4. Attacker fabricates entire initial state
5. All future transactions build on this poisoned genesis
```

**Verdict:** First transaction can fabricate arbitrary initial state with no verification.

---

### 13.3 CRITICAL: Checkpoint Chain Reorganization

**The Problem:**

Multiple users can create competing checkpoint chains simultaneously. Contract only tracks `latestCheckpointHash` - whichever transaction lands last wins.

**Attack Scenario:**

```
Current state: Checkpoint C (valid)

Attacker submits: C → D (invalid state) → E → F → G (4 transactions)
Honest user submits: C → D' (valid state)

If attacker's transactions land first:
- latestCheckpointHash = G
- Honest user's D' transaction fails (C is no longer latest)
- Entire chain is now built on attacker's invalid state

Even if honest user challenges later:
- Challenges D, reverts to C
- But E, F, G also executed based on D
- What happens to withdrawals that already occurred in E, F, G?
- Can't undo ETH transfers that already happened!
```

**Verdict:** No consensus mechanism for resolving checkpoint forks. Last-write-wins enables chain poisoning.

---

### 13.4 CRITICAL: Challenge Timing Attack

**The Problem:**

Invalid checkpoints can be challenged, but what if challenge comes too late?

**Attack:**

```
Block 1000: Attacker submits invalid checkpoint X
Block 1001: Alice withdraws building on X
Block 1002: Bob withdraws building on X
Block 1003: Charlie withdraws building on X
Block 1004: Honest actor notices and challenges X

Result:
- Challenge succeeds, X reverted
- But Alice, Bob, Charlie already received ETH!
- Can't reverse ETH transfers
- Funds lost
```

**The challenge function:**

```solidity
function challengeCheckpoint(...) external {
    // Reverts checkpoint
    latestCheckpointHash = invalid.prevCheckpointHash;
    delete checkpoints[invalidCheckpointHash];

    // But what about all the withdrawals that already happened???
}
```

**Verdict:** Challenges don't prevent theft if invalid checkpoint is used before challenge occurs.

---

### 13.5 HIGH: State Withholding Attack

**The Problem:**

User must provide "complete global pending set" but contract has no way to verify it's actually complete (without knowing the real state, which requires... a trusted checkpoint!).

**Attack:**

```
Real Ethereum state at block 1000:
- Swap #1 (Alice): pending
- Swap #2 (Bob): pending
- Swap #3 (Attacker): INVALID (double-spend)

Attacker submits checkpoint:
- Claims pending set = {Swap #1, Swap #2}  (omits Swap #3)
- Proves Swap #3 is in the incomplete set
- Withdraws successfully

How does contract detect Swap #3 was omitted?
- It doesn't have the real state root to check against
- Circular dependency: need checkpoint to verify completeness,
  but checkpoint is what we're trying to create!
```

**Verdict:** No way to verify global pending set is actually complete without trusted state root.

---

### 13.6 HIGH: Race Condition on Chain Extension

**The Problem:**

Multiple users try to extend same checkpoint simultaneously.

**Scenario:**

```
Current latest: Checkpoint C (block 1000)

At block 1001 (same time):
- Alice submits tx extending C to block 1050
- Bob submits tx extending C to block 1050
- Charlie submits tx extending C to block 1050

All three are valid extensions of C!

Transaction ordering:
1. Alice's lands first → latestCheckpoint = D1
2. Bob's fails (C is no longer latest, D1 is)
3. Charlie's fails (C is no longer latest, D1 is)

Bob and Charlie's valid transactions fail unpredictably.
```

**Impact:**
- Unreliable UX (valid transactions randomly fail)
- Possible griefing (attacker spam-extends checkpoints to DOS others)

**Verdict:** No mechanism for concurrent checkpoint extension.

---

### 13.7 HIGH: Block Header Verification Gas Cost Attack

**The Problem:**

Verifying state transitioned from block X to Y requires verifying all intermediate headers.

**Attack:**

```
Attacker waits 10,000 blocks between checkpoints.

Next user must verify transition:
- fromBlock: 1000
- toBlock: 11000
- Must verify 10,000 block headers

Gas cost calculation:
- Each header verification: ~50,000 gas (optimistic)
- Total: 10,000 × 50,000 = 500,000,000 gas
- Block limit: 30,000,000 gas

Transaction fails - too much gas!

User is stuck - can't withdraw because verification exceeds block gas limit.
```

**Verdict:** Attacker can DOS users by forcing expensive state transition proofs.

---

### 13.8 MEDIUM: Finality Mismatch Attack

**The Problem:**

Checkpoints might reference unfinalized blocks that later get reorged.

**Attack:**

```
1. Ethereum at block 1000 (not finalized, only 3 confirmations)
   State root: 0xABC

2. Alice submits checkpoint claiming state root 0xABC at block 1000
   Checkpoint accepted on OL

3. Ethereum reorganizes! Block 1000 now has different state root: 0xDEF
   (This happens occasionally in PoS before finality at ~12 min)

4. Alice's checkpoint on OL still claims 0xABC
   But Ethereum canonical chain has 0xDEF

5. Now all future checkpoints on OL are building on wrong Ethereum state
```

**Verdict:** Need to require finality, but design doesn't specify this.

---

### 13.9 MEDIUM: Bob's Balance Desync (Race to Withdraw)

**Already noted in Research Questions, but here's the attack:**

```
1. Bob registers 10 ETH on OL (proves balance via checkpoint)
2. Bob creates 10 orders on OL, each selling 1 OL for 1 ETH (10 ETH locked)
3. Bob immediately withdraws 8 ETH from Ethereum escrow contract
4. Bob's OL balance still shows 10 ETH locked (stale)
5. 10 swaps complete on OL, Bob should pay 10 ETH
6. But Bob only has 2 ETH left in escrow!
7. Last 8 Alice's can't claim their ETH (insufficient funds)
```

**Verdict:** Balance synchronization is impossible without continuous checkpoints (which requires trusted intermediary).

---

### 13.10 LOW: Griefing via Checkpoint Spam

**The Problem:**

Anyone can create checkpoints. No cost mentioned.

**Attack:**

```
Attacker submits 1000 transactions, each creating new checkpoint:
C → D → E → F → ... → ZZZZ

Each checkpoint is "valid" (extends previous).

Result:
- Checkpoint history bloated
- Higher storage costs for contract
- Harder to find "real" checkpoints among spam
```

**Mitigation:** Require small fee to create checkpoint, but this wasn't specified.

---

## 13.11 Research Questions (Non-Critical Issues)

While the above are potential exploits, several open questions require further investigation:

### 13.1 Bob's ETH Balance Synchronization

**Problem**: After Bob registers his ETH balance on OL (Phase 1), he could withdraw ETH from the Ethereum escrow contract, causing his tracked balance on OL to become stale.

**Potential Solutions**:
1. **Periodic Revalidation**: Require Bob to submit fresh ZK proofs of his Ethereum balance every N hours (e.g., 24 hours)
   - Pros: Simple, lets Bob withdraw freely
   - Cons: Adds friction, Bob might forget to revalidate

2. **Withdrawal Lockup Period**: When Bob registers ETH, lock it in escrow contract for minimum period
   - Pros: Prevents desync during active trading
   - Cons: Reduces capital efficiency if Bob wants to exit quickly

3. **Two-Way State Sync**: OL contract can trigger Ethereum withdrawals via cross-chain messages
   - Pros: Most accurate, allows atomic operations
   - Cons: More complex, requires bidirectional ZK light clients

4. **Grace Period + Challenge System**: Allow anyone to challenge stale balances, force Bob to prove solvency or be penalized
   - Pros: Community-enforced honesty
   - Cons: Adds complexity, potential for griefing

**Recommendation**: Start with approach #2 (withdrawal lockup) for MVP, transition to #3 (two-way sync) for production.

### 13.2 Timeout Coordination Between Chains

**Problem**: OL timeout and Ethereum timeout start at different times:
- OL timeout starts at `match_time` (when Bob matches order)
- Ethereum timeout starts when Alice calls `lockETH()` (could be seconds or minutes later)

**Consequences**:
- If Alice delays calling `lockETH()`, Ethereum timeout might expire before OL timeout
- Bob could get refunded on Ethereum while still locked on OL (or vice versa)

**Potential Solutions**:
1. **Fixed Time Buffer**: Make OL timeout significantly longer than Ethereum (e.g., OL: 2 hours, ETH: 1 hour)
   - Pros: Simple
   - Cons: Capital locked longer than necessary

2. **Relative Timeout Encoding**: Encode timeout duration in ZK proof, Ethereum calculates based on current time
   - Pros: More precise alignment
   - Cons: More complex proof verification

3. **Synchronized Timestamps**: Use ZK proof to embed OL `match_time` in Ethereum lock
   - Pros: Perfect alignment
   - Cons: Requires timestamp verification in ZK circuit

**Recommendation**: Use approach #3 (synchronized timestamps) for production to minimize capital lockup time.

### 13.3 Gas Cost Optimization for ZK Verification

**Problem**: Verifying ZK proofs on Ethereum is expensive (200k-500k gas per proof).

**Considerations**:
- Alice pays gas to lock ETH (one proof verification)
- Bob or anyone pays gas to complete swap on OL (one proof verification)
- At current gas prices, this could be $10-50 per swap

**Potential Solutions**:
1. **Batch Verification**: Aggregate multiple swap proofs into single verification
   - Pros: Amortized cost across many users
   - Cons: Adds latency, coordination complexity

2. **Use Plonky2 with Poseidon Hash**: ~80% cheaper than standard SNARKs
   - Pros: Significant savings
   - Cons: Less mature, fewer audited implementations

3. **Optimistic Verification**: Assume proof is valid, allow challenge period
   - Pros: No immediate verification cost
   - Cons: Adds latency, requires fraud proof system

4. **Layer 2 Settlement**: Execute swaps on rollup, batch-settle to L1
   - Pros: Cheapest option, leverages existing L2 infrastructure
   - Cons: Adds complexity, L2 trust assumptions

**Recommendation**: Start with approach #2 (Plonky2) for MVP, explore #4 (L2 settlement) for scale.

### 13.4 Oracle vs Light Client for ZK Proofs

**Problem**: The design assumes ZK light clients for verifying cross-chain state. Should we consider oracles as an alternative?

**Trade-offs**:

**ZK Light Client Approach**:
- Pros: Fully trustless, no external dependencies
- Cons: Complex to implement, expensive to verify (~200k+ gas), requires maintaining consensus proofs

**Oracle Approach (e.g., Chainlink CCIP)**:
- Pros: Simple integration, battle-tested, lower gas cost
- Cons: Introduces trust assumptions, oracle compromise = fund loss, ongoing oracle fees

**Hybrid Approach**:
- Pros: Use oracle for speed, ZK light client for security-critical operations
- Cons: More complex, need clear rules for when to use which

**Recommendation**: Use ZK light client for MVP to maintain trustlessness. Consider hybrid for production if gas costs become prohibitive.

### 13.5 MEV on OL Chain

**Problem**: OL validators can see pending orders and front-run matching logic.

**Attack Scenarios**:
1. **Order Front-Running**: Validator sees Alice's profitable order, submits their own order first
2. **Match Manipulation**: Validator delays including Bob's match transaction to get worse price
3. **Sandwich Attacks**: Validator places orders before and after user orders

**Potential Solutions**:
1. **Commit-Reveal Scheme**: Orders submitted as commitments, revealed in later block
   - Pros: Prevents front-running
   - Cons: Adds one block delay (~1-5 seconds)

2. **Threshold Encryption**: Orders encrypted to future block, decrypted by validators collectively
   - Pros: Strong MEV protection
   - Cons: Complex, requires threshold crypto primitives

3. **Fair Ordering Protocol**: Use HotStuff BFT with fair ordering guarantees
   - Pros: Protocol-level solution
   - Cons: May require consensus changes

4. **Frequent Batch Auctions**: Accept orders for N seconds, match all in batch
   - Pros: Simple, reduces MEV opportunity
   - Cons: Adds latency

**Recommendation**: Implement approach #4 (batch auctions) for MVP. This is simplest and provides reasonable MEV protection while maintaining decent UX.

### 13.6 Cross-Chain Message Ordering

**Problem**: If Alice locks ETH on Ethereum and Bob completes swap on OL in quick succession, the ZK proof of ETH lock might not be available yet due to proof generation latency.

**Scenario**:
1. Alice calls `lockETH()` on Ethereum (block N)
2. Light client needs to prove block N to OL
3. Bob tries to call `complete_swap()` but proof isn't ready yet

**Potential Solutions**:
1. **Wait for Finality**: Require Ethereum finality (~12 minutes) before OL accepts proof
   - Pros: Simple, safe
   - Cons: Very slow, poor UX

2. **Optimistic Acceptance**: Accept unfinalized blocks, allow reorg challenges
   - Pros: Fast (~30 seconds)
   - Cons: Complex reorg handling

3. **Proof Generation Service**: Dedicated provers generate proofs within seconds of block
   - Pros: Fast, reliable
   - Cons: Centralization risk if single prover

4. **Progressive Finality**: Accept blocks with increasing confidence based on depth
   - Pros: Balance speed/security
   - Cons: Needs careful economic analysis

**Recommendation**: Use approach #2 (optimistic acceptance) with 6-12 block confirmation (~1-2 minutes) for MVP. This is fast enough for good UX while providing reasonable safety.

### 13.7 Upgradeability and Governance

**Problem**: The swap protocol will need upgrades for bug fixes, optimizations, and new features.

**Considerations**:
- Move contracts on OL are upgradeable via governance
- Solidity contracts on Ethereum can use proxy pattern
- Need coordination for breaking changes across both chains

**Questions**:
1. Who can trigger upgrades? (Multisig, DAO, timelock?)
2. How to handle in-flight swaps during upgrade?
3. How to deprecate old versions safely?
4. How to coordinate simultaneous upgrades on both chains?

**Recommendation**: Design upgrade mechanism from day one. Consider:
- Versioned swap contracts (v1, v2, etc.)
- Grace period for migrating from old version
- Circuit breaker for emergency pauses
- Multisig + timelock governance for OL side
- Proxy pattern for Ethereum side

---

## Conclusion

This research provides a comprehensive foundation for implementing a trustless atomic swap protocol between OL (Move) and Ethereum (Solidity). The key insights are:

1. **HTLCs are battle-tested** and provide the cryptographic foundation for trustless swaps
2. **Move's resource safety** offers inherent advantages for secure asset handling
3. **Foundry provides the fastest path** for Solidity development and testing
4. **Docker Compose enables realistic E2E testing** of cross-chain scenarios
5. **Security requires attention to detail**: timelock ordering, reentrancy, griefing attacks
6. **Emerging alternatives** (intents, ZKPs) offer compelling improvements but add complexity
7. **Fair market behavior is non-negotiable**: Price manipulation must be prevented through orderbook price-time priority, batch auctions, or Dutch auctions
8. **MEV protection is essential**: Use batch auctions, private mempools, or commit-reveal to protect users
9. **Hybrid approaches** combining HTLCs + intents + ZK proofs provide the best user experience
10. **Global state commitment eliminates oracle infrastructure**: Withdrawals require providing the complete global pending transaction set, eliminating need for trusted oracles

The recommended approach is to:
- **Start with asymmetric architecture**: OL handles orderbook and business logic, Ethereum handles minimal escrow operations
- **Use pre-funding model**: Bob registers ETH balance on OL before creating orders, enabling instant settlement
- **Require global state commitment**: Withdrawals must include proof of complete pending transaction set, preventing fraud proactively
- **Support dual execution modes**: Manual mode for paranoid/autonomous systems, automated mode for normal users
- **Layer on intent-based UX**: Add Dutch auctions for speed and batch auctions for MEV protection
- **Integrate ZK optimizations**: Reduce timelock delays while maintaining trustlessness
- **Enforce best execution**: Protocol enforces fair matching through price-time priority

This progressive strategy balances security, fair markets, usability, and innovation. The protocol must be trustless not only in preventing theft, but also in ensuring honest price discovery and protecting against market manipulation. The global state commitment model achieves trustlessness through cryptographic verification rather than relying on trusted intermediaries - withdrawers must prove the complete cross-chain state to withdraw, and this requirement alone prevents all major attack vectors.

The 10-week roadmap provides a pragmatic path from initial development through production deployment, with emphasis on comprehensive testing, security review, and fair market design at each phase.
