# Research: Treasury Auction Atomic Swaps for OL ↔ EVM

## Executive Summary

This document proposes an alternative atomic swap design that avoids the zkBridge complexity by using **asymmetric atomicity**: the away chain (e.g., Ethereum) uses simple HTLCs with single-party locks, while the home chain (Libra) leverages Move's resource safety to enable **multi-party fractional fulfillment** through treasury auction mechanics.

**Key Innovation:** Away chain assets are traded in their entirety (no fractionalization), but home chain (Libra) allows multiple users to collectively fill the swap using their **unlocked balances** with no escrow needed, finding price through uniform-price auctions.

## 1. Core Concept

### 1.1 The Problem with Symmetric Escrow

Traditional atomic swaps require both parties to lock funds:
```
Alice locks 10 ETH on Ethereum
Bob locks 1000 OL on Libra
→ Both funds escrowed for 24-48 hours
→ Capital inefficiency
→ Single counterparty risk
```

The zkBridge approach tried to solve this with orderbooks and ZK proofs, but created infrastructure dependencies.

### 1.2 The Asymmetric Solution

**Away Chain (Ethereum):**
- Alice locks 10 ETH in simple HTLC contract
- Single-party, indivisible lock
- No fractionalization, no complex logic
- Standard hash + time lock primitives

**Home Chain (Libra):**
- Multiple users (Bob, Carol, Dave) participate with unlocked balances
- Treasury auction determines clearing price
- Move's atomicity ensures all-or-nothing execution
- No escrow needed - execution is instant and atomic

### 1.3 Why This Works

**Move's Resource Safety:**
```move
// Pseudocode - atomic multi-party execution
public entry fun execute_auction_settlement(
    auction_id: u64
) acquires AuctionRegistry {
    let auction = get_auction(auction_id);

    // All of these transfers happen atomically
    // If any fails, entire transaction reverts
    transfer(bob, alice, 400 OL);    // Bob's portion
    transfer(carol, alice, 300 OL);  // Carol's portion
    transfer(dave, alice, 300 OL);   // Dave's portion

    // Total: 1000 OL to Alice
    // Alice reveals secret, unlocking her 10 ETH for pro-rata distribution
}
```

**Key Properties:**
- All transfers execute in single transaction (atomic)
- No escrow needed (funds taken from unlocked balances)
- If anyone lacks balance, entire tx reverts (safety)
- Settlement is instant (no waiting period)

## 2. Treasury Auction Mechanics

### 2.1 What is a Treasury Auction?

Used by governments to sell bonds, treasury auctions find a uniform clearing price where supply meets demand.

**Characteristics:**
- Multiple bidders submit price/quantity pairs
- All winning bids pay the **same price** (uniform price)
- Fair price discovery (no first-mover advantage)
- Simple, well-understood mechanism

### 2.2 Application to Atomic Swaps

**Scenario:** Alice wants to swap 10 ETH for OL tokens

**Step 1: Alice locks ETH and announces**
```
Offering: 10 ETH
Minimum acceptable: 900 OL (90 OL per ETH)
Auction duration: 2 hours
Hash lock: 0xabc123...
Time lock: 24 hours
```

**Step 2: Libra users bid (non-sealed)**
```
Bob:   "I'll buy 5 ETH at max 95 OL/ETH"  → 475 OL
Carol: "I'll buy 3 ETH at max 100 OL/ETH" → 300 OL
Dave:  "I'll buy 4 ETH at max 92 OL/ETH"  → 368 OL
Eve:   "I'll buy 2 ETH at max 105 OL/ETH" → 210 OL
```

**Step 3: Auction clears**
```
Sort by price (descending):
Eve:   2 ETH @ 105 OL/ETH
Carol: 3 ETH @ 100 OL/ETH
Bob:   5 ETH @ 95 OL/ETH
Dave:  4 ETH @ 92 OL/ETH

Total demand: 14 ETH
Supply: 10 ETH

Clearing price: 95 OL/ETH (Bob's bid clears the market)
```

**Step 4: Pro-rata allocation at uniform price**
```
All winners pay 95 OL/ETH:
Eve:   2 ETH × 95 = 190 OL (filled 100%)
Carol: 3 ETH × 95 = 285 OL (filled 100%)
Bob:   5 ETH × 95 = 475 OL (filled 100%)
───────────────────────────
Total: 10 ETH for 950 OL

Dave: Not filled (bid too low)
```

**Step 5: Atomic settlement**
- Alice receives 950 OL (from Eve + Carol + Bob)
- Alice reveals secret preimage
- Eve, Carol, Bob each claim their pro-rata ETH from Ethereum contract

### 2.3 Uniform Price Benefits

**Fairness:**
- Everyone pays the same price (no discrimination)
- No advantage to being first
- Reduces gaming incentives

**Simplicity:**
- Easy to understand
- Widely used in finance
- Predictable outcomes

**Efficiency:**
- Price discovery happens naturally
- No sealed bid complexity
- Transparent process

## 3. HTLC Adaptation for Multi-Party Fulfillment

### 3.1 Away Chain (Ethereum) Contract

```solidity
// Simplified - supports multiple withdrawers
contract MultiPartyHTLC {
    struct Lock {
        address payable initiator;
        uint256 totalAmount;
        bytes32 hashLock;
        uint256 timeLock;
        uint256 minAcceptable;  // Minimum OL tokens required
        bool refunded;
        bytes32 preimage;

        // Multi-party withdrawal tracking
        mapping(address => uint256) allocations;  // Pro-rata shares
        mapping(address => bool) withdrawn;
        uint256 totalAllocated;
        bool finalized;
    }

    mapping(bytes32 => Lock) public locks;

    // Alice locks ETH
    function lockETH(
        bytes32 lockId,
        bytes32 hashLock,
        uint256 timeLock,
        uint256 minAcceptable
    ) external payable {
        require(msg.value > 0, "Must send ETH");

        locks[lockId] = Lock({
            initiator: payable(msg.sender),
            totalAmount: msg.value,
            hashLock: hashLock,
            timeLock: timeLock,
            minAcceptable: minAcceptable,
            refunded: false,
            preimage: 0,
            totalAllocated: 0,
            finalized: false
        });
    }

    // Auction winner sets their allocation (callable by anyone with proof)
    function setAllocation(
        bytes32 lockId,
        address[] calldata winners,
        uint256[] calldata amounts,
        bytes32 preimage  // Proves auction settled on Libra
    ) external {
        Lock storage lock = locks[lockId];
        require(!lock.finalized, "Already finalized");
        require(sha256(abi.encodePacked(preimage)) == lock.hashLock, "Invalid preimage");
        require(block.timestamp < lock.timeLock, "Expired");

        // Set allocations based on auction results
        uint256 total = 0;
        for (uint i = 0; i < winners.length; i++) {
            lock.allocations[winners[i]] = amounts[i];
            total += amounts[i];
        }

        require(total == lock.totalAmount, "Allocation mismatch");

        lock.preimage = preimage;
        lock.finalized = true;
        lock.totalAllocated = total;
    }

    // Each auction winner withdraws their share
    function withdraw(bytes32 lockId) external {
        Lock storage lock = locks[lockId];
        require(lock.finalized, "Not finalized");
        require(lock.allocations[msg.sender] > 0, "No allocation");
        require(!lock.withdrawn[msg.sender], "Already withdrawn");

        uint256 amount = lock.allocations[msg.sender];
        lock.withdrawn[msg.sender] = true;

        payable(msg.sender).transfer(amount);
    }

    // Alice refunds if auction fails
    function refund(bytes32 lockId) external {
        Lock storage lock = locks[lockId];
        require(msg.sender == lock.initiator, "Not initiator");
        require(block.timestamp >= lock.timeLock, "Not expired");
        require(!lock.finalized, "Already finalized");
        require(!lock.refunded, "Already refunded");

        lock.refunded = true;
        lock.initiator.transfer(lock.totalAmount);
    }
}
```

### 3.2 Home Chain (Libra) Contract

```move
module ol_framework::treasury_auction_swap {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::table::{Self, Table};

    /// Auction state for an away chain asset
    struct Auction<phantom HomeCoin> has key, store {
        auction_id: u64,
        initiator: address,           // Away chain initiator (e.g., Alice)
        away_asset: vector<u8>,       // "ETH" identifier
        away_amount: u64,             // 10 ETH (in wei or smallest unit)
        away_lock_id: vector<u8>,     // Ethereum HTLC lock ID
        away_hash_lock: vector<u8>,   // Hash of secret

        min_home_amount: u64,         // 900 OL minimum
        clearing_price: u64,          // OL per away unit (set after auction)

        auction_end: u64,             // Timestamp when bidding ends
        time_lock: u64,               // Must settle before this

        status: u8,                   // 0=Open, 1=Clearing, 2=Settled, 3=Refunded
    }

    /// Individual bid in an auction
    struct Bid has store, drop {
        bidder: address,
        max_price: u64,               // Maximum OL per away unit
        quantity: u64,                // How many away units (e.g., ETH)
        auto_bid: bool,               // Was this auto-generated from user settings?
    }

    /// Registry of all active auctions
    struct AuctionRegistry<phantom HomeCoin> has key {
        auctions: Table<u64, Auction<HomeCoin>>,
        bids: Table<u64, vector<Bid>>,  // auction_id -> bids
        next_auction_id: u64,
    }

    /// User's global max price settings for auto-bidding
    struct UserBidSettings has key {
        max_prices: Table<vector<u8>, u64>,  // away_asset -> max price
        enabled: bool,
    }

    /// Initialize auction from away chain lock
    public entry fun create_auction<HomeCoin>(
        initiator: &signer,
        away_asset: vector<u8>,
        away_amount: u64,
        away_lock_id: vector<u8>,
        away_hash_lock: vector<u8>,
        min_home_amount: u64,
        auction_duration: u64,
        time_lock: u64,
    ) acquires AuctionRegistry {
        let registry = borrow_global_mut<AuctionRegistry<HomeCoin>>(@ol_framework);
        let auction_id = registry.next_auction_id;
        registry.next_auction_id = auction_id + 1;

        let current_time = timestamp::now_seconds();

        let auction = Auction<HomeCoin> {
            auction_id,
            initiator: signer::address_of(initiator),
            away_asset,
            away_amount,
            away_lock_id,
            away_hash_lock,
            min_home_amount,
            clearing_price: 0,
            auction_end: current_time + auction_duration,
            time_lock,
            status: 0,  // Open
        };

        table::add(&mut registry.auctions, auction_id, auction);
        table::add(&mut registry.bids, auction_id, vector::empty<Bid>());

        // Trigger auto-bids from users with settings
        trigger_auto_bids<HomeCoin>(auction_id);
    }

    /// Manual bid submission with authorization
    public entry fun submit_bid<HomeCoin>(
        bidder: &signer,
        auction_id: u64,
        max_price: u64,
        quantity: u64,
    ) acquires AuctionRegistry {
        let registry = borrow_global_mut<AuctionRegistry<HomeCoin>>(@ol_framework);
        let auction = table::borrow(&registry.auctions, auction_id);

        assert!(timestamp::now_seconds() < auction.auction_end, E_AUCTION_ENDED);
        assert!(auction.status == 0, E_AUCTION_NOT_OPEN);

        // Check bidder has sufficient balance (not locked, just available)
        let bidder_addr = signer::address_of(bidder);
        let required = max_price * quantity;
        assert!(coin::balance<HomeCoin>(bidder_addr) >= required, E_INSUFFICIENT_BALANCE);

        let bid = Bid {
            bidder: bidder_addr,
            max_price,
            quantity,
            auto_bid: false,
        };

        let bids = table::borrow_mut(&mut registry.bids, auction_id);
        vector::push_back(bids, bid);

        // CRITICAL: Authorize contract to withdraw if bid wins
        // Authorization is scoped to this auction and max bid amount
        coin::authorize_withdrawal<HomeCoin>(
            bidder,
            @ol_framework,  // Contract address
            auction_id,     // Scope identifier
            required        // Max authorized amount
        );
    }

    /// Clear auction and determine winners (callable by anyone)
    public entry fun clear_auction<HomeCoin>(
        _caller: &signer,
        auction_id: u64,
    ) acquires AuctionRegistry {
        let registry = borrow_global_mut<AuctionRegistry<HomeCoin>>(@ol_framework);
        let auction = table::borrow_mut(&mut registry.auctions, auction_id);

        assert!(timestamp::now_seconds() >= auction.auction_end, E_AUCTION_NOT_ENDED);
        assert!(auction.status == 0, E_AUCTION_NOT_OPEN);

        let bids = table::borrow_mut(&mut registry.bids, auction_id);

        // Sort bids by max_price (descending)
        // Find clearing price where supply meets demand
        let (clearing_price, total_filled) = calculate_clearing_price(
            bids,
            auction.away_amount
        );

        // Check if minimum met
        let total_home_coins = clearing_price * auction.away_amount;
        assert!(total_home_coins >= auction.min_home_amount, E_MIN_NOT_MET);

        auction.clearing_price = clearing_price;
        auction.status = 1;  // Clearing
    }

    /// Atomic settlement (anyone can trigger with preimage)
    public entry fun settle_auction<HomeCoin>(
        _caller: &signer,
        auction_id: u64,
        preimage: vector<u8>,
    ) acquires AuctionRegistry {
        let registry = borrow_global_mut<AuctionRegistry<HomeCoin>>(@ol_framework);
        let auction = table::borrow_mut(&mut registry.auctions, auction_id);

        assert!(auction.status == 1, E_NOT_CLEARED);
        assert!(timestamp::now_seconds() < auction.time_lock, E_TIMEOUT);

        // Verify preimage
        let computed_hash = hash::sha2_256(preimage);
        assert!(computed_hash == auction.away_hash_lock, E_INVALID_PREIMAGE);

        let bids = table::borrow(&registry.bids, auction_id);

        // Determine winners and their allocations
        let winners = get_winning_bids(bids, auction.clearing_price, auction.away_amount);

        // ATOMIC EXECUTION: Use pre-authorized withdrawals
        // All transfers execute or all fail (Move transaction atomicity)
        let i = 0;
        let total_transferred = 0;
        while (i < vector::length(&winners)) {
            let winner = vector::borrow(&winners, i);

            // Contract withdraws from winner's account using pre-authorization
            // Authorization was granted when user submitted bid
            coin::withdraw_authorized<HomeCoin>(
                @ol_framework,      // Contract address (authorized party)
                winner.bidder,      // From winner's account
                auction.initiator,  // To Alice (away chain initiator)
                winner.amount,      // Amount to transfer
                auction_id          // Authorization scope
            );

            total_transferred = total_transferred + winner.amount;
            i = i + 1;
        };

        // All transfers succeeded (atomic) - mark settled
        auction.status = 2;  // Settled

        // Emit event with preimage and winner allocations
        // Winners can now claim their pro-rata ETH on Ethereum using preimage
    }

    // Helper: Calculate clearing price
    fun calculate_clearing_price(
        bids: &vector<Bid>,
        supply: u64,
    ): (u64, u64) {
        // Sort bids descending by max_price
        let sorted = sort_bids_desc(bids);

        let cumulative_demand = 0;
        let clearing_price = 0;
        let i = 0;

        while (i < vector::length(&sorted)) {
            let bid = vector::borrow(&sorted, i);
            cumulative_demand = cumulative_demand + bid.quantity;

            if (cumulative_demand >= supply) {
                clearing_price = bid.max_price;
                break
            };

            i = i + 1;
        };

        (clearing_price, supply)
    }

    // Helper: Get winning bids at clearing price
    fun get_winning_bids(
        bids: &vector<Bid>,
        clearing_price: u64,
        supply: u64,
    ): vector<WinningBid> {
        // Return all bids with max_price >= clearing_price
        // Pro-rata allocation if needed
        // ... implementation details
    }
}
```

## 4. Key Design Elements

### 4.1 No Escrow on Home Chain

**Critical advantage:** Users don't lock funds during auction period.

**Traditional HTLC:**
```
Bob locks 1000 OL for 24 hours → Capital locked
If swap fails → Bob waits 24h to recover funds
```

**This design:**
```
Bob bids "max 95 OL/ETH for 5 ETH" → Funds stay unlocked
Bob authorizes contract to withdraw max 475 OL → Authorization only
If auction clears → Transfer happens atomically using authorization
If auction fails → No need to recover (never locked)
```

**Authorization vs. Escrow:**

**Escrow (traditional):**
- Funds physically moved to contract
- Capital unavailable during lock period
- Requires manual refund mechanism
- Can't use same funds elsewhere

**Authorization (this design):**
- Funds stay in user's wallet
- Authorization = permission to withdraw
- No refund needed (funds never left)
- Can authorize multiple auctions with overlapping capital

**Security:** Move's transaction atomicity ensures:
- Either all transfers succeed (settlement)
- Or entire transaction reverts (no partial execution)
- No need for manual refunds on home chain

**Mechanism:**
```move
// At bid time: User authorizes withdrawal
coin::authorize_withdrawal(bidder, @contract, auction_id, max_amount);

// At settlement: Contract uses authorization
coin::withdraw_authorized(@contract, bidder, recipient, amount, auction_id);
```

**Key properties:**
- Authorization scoped to specific auction (can't be misused)
- Expires when auction settles or times out
- Users retain full custody until settlement moment
- Multiple auctions can share same capital (authorization != lock)

### 4.2 Atomic Multi-Party Execution

**Move's advantage:**
```move
// All of these happen atomically in ONE transaction
transfer(bob, alice, 475);
transfer(carol, alice, 285);
transfer(eve, alice, 190);
// Total: 950 OL

// If ANY transfer fails (insufficient balance), ALL revert
```

**Cannot happen on Ethereum HTLCs:** Each party must submit separate transaction.

**Cannot happen with ZK bridge:** Need escrow to guarantee funds availability.

**Move enables this** through:
- Single transaction multiple transfers
- Resource safety (coins can't disappear)
- Atomic execution guarantees

### 4.3 Auto-Bidding from User Settings

**User experience:**
```move
// One-time setup
public entry fun set_max_price(
    user: &signer,
    away_asset: vector<u8>,  // "ETH"
    max_price: u64,          // 100 OL per ETH
) {
    // Store user's standing preferences
    // System auto-bids on their behalf when auctions appear
}
```

**Example:**
```
Bob sets: "I'll buy ETH at max 95 OL/ETH, up to 5 ETH per auction"
Carol sets: "I'll buy ETH at max 100 OL/ETH, up to 10 ETH per auction"

When Alice creates auction:
- System auto-generates Bob's bid
- System auto-generates Carol's bid
- No manual intervention needed
```

**Benefits:**
- Passive participation
- Always-on liquidity
- No need to monitor for new auctions
- Users retain full custody (funds not locked)

### 4.4 Treasury Auction Clearing

**Why uniform price?**

**Alternative 1 - Discriminatory auction (pay your bid):**
```
Eve pays 105 OL/ETH
Carol pays 100 OL/ETH
Bob pays 95 OL/ETH
→ Total: 190 + 300 + 475 = 965 OL
```
Problem: Incentivizes lowballing, unfair to high bidders

**Alternative 2 - First-come-first-serve:**
```
First 10 ETH of bids win
→ Gaming through transaction ordering
→ MEV opportunities
→ Unfair to organic users
```

**Uniform price (treasury auction):**
```
Everyone pays 95 OL/ETH (clearing price)
→ Total: 950 OL
→ Fair, no gaming incentive
→ Simple to understand
```

### 4.5 Price Discovery Without Orderbook

**No central orderbook needed:**
- Each auction is independent
- Price discovered per auction through bidding
- Historical auctions inform future bids
- Market efficiency emerges organically

**Advantages:**
- No orderbook state to maintain
- No zkBridge complexity
- No checkpoint mechanisms
- Simple, stateless design

**Trade-offs:**
- Price discovery per auction (not continuous)
- May have price variance between auctions
- Depends on participation for efficiency

## 5. Complete Swap Flow

### 5.1 Happy Path

**Step 1: Alice initiates on Ethereum**
```solidity
// Alice locks 10 ETH
lockETH(
    lockId: keccak256("alice-swap-123"),
    hashLock: sha256(secret),
    timeLock: now + 24 hours,
    minAcceptable: 900 OL
)
```

**Step 2: Alice announces on Libra**
```move
// Alice creates auction
create_auction<LibraCoin>(
    away_asset: b"ETH",
    away_amount: 10_000_000_000_000_000_000,  // 10 ETH in wei
    away_lock_id: b"alice-swap-123",
    away_hash_lock: sha256(secret),
    min_home_amount: 900_000_000,  // 900 OL
    auction_duration: 7200,  // 2 hours
    time_lock: 86400,  // 24 hours
)
```

**Step 3: Libra users bid (auto or manual)**
```move
// Auto-bids triggered based on user settings
Bob's auto-bid: 5 ETH @ 95 OL/ETH
Carol's auto-bid: 3 ETH @ 100 OL/ETH
Eve's manual bid: 2 ETH @ 105 OL/ETH
```

**Step 4: Auction clears (2 hours later)**
```move
// Anyone can trigger clearing
clear_auction<LibraCoin>(auction_id: 1);

// Result:
// Clearing price: 95 OL/ETH
// Winners: Eve (2 ETH), Carol (3 ETH), Bob (5 ETH)
// Total: 10 ETH for 950 OL
```

**Step 5: Settlement on Libra (atomic)**
```move
// Anyone can trigger with preimage
settle_auction<LibraCoin>(
    auction_id: 1,
    preimage: secret
);

// ATOMIC EXECUTION:
// Transfer 190 OL from Eve to Alice
// Transfer 285 OL from Carol to Alice
// Transfer 475 OL from Bob to Alice
// Total: 950 OL → Alice receives instantly
```

**Step 6: Winners set allocations on Ethereum**
```solidity
// Anyone can submit (usually Alice or a winner)
setAllocation(
    lockId: "alice-swap-123",
    winners: [Eve, Carol, Bob],
    amounts: [2 ETH, 3 ETH, 5 ETH],
    preimage: secret  // Proves Libra settlement occurred
)
```

**Step 7: Winners withdraw their ETH**
```solidity
// Eve withdraws
withdraw("alice-swap-123");  // Receives 2 ETH

// Carol withdraws
withdraw("alice-swap-123");  // Receives 3 ETH

// Bob withdraws
withdraw("alice-swap-123");  // Receives 5 ETH
```

**Complete! No escrow on Libra side, atomic settlement.**

### 5.2 Failure Scenarios

**Scenario 1: Auction doesn't clear (insufficient bids)**
```
Total bids: 8 ETH (< 10 ETH supply)
Or: Clearing price would yield < 900 OL minimum

Result:
- Auction expires without clearing
- No settlement on Libra
- Alice refunds her ETH on Ethereum after timelock
- No funds locked on Libra (nothing to refund)
```

**Scenario 2: Winner lacks balance at settlement**
```
Auction clears, but Bob spent his coins before settlement

Result:
- settle_auction() transaction reverts (atomic execution)
- Auction remains in "Cleared" state
- Can retry settlement when Bob has balance
- Or timeout and Alice refunds on Ethereum
```

**Scenario 3: Alice never reveals preimage**
```
Auction clears, winners identified

Result:
- Cannot call settle_auction() without preimage
- Timeout expires (24 hours)
- Alice refunds her ETH on Ethereum
- No settlement on Libra (no funds were locked)
- Winners' funds never left their wallets
```

**Scenario 4: Winners don't withdraw ETH**
```
Settlement succeeded on Libra (Alice has OL)
But Eve/Carol/Bob don't withdraw their ETH

Result:
- Their ETH allocations remain in contract
- They can withdraw any time (no timeout on claiming)
- Their coins are safe (allocated to their addresses)
- No harm to them (just need to submit withdraw tx)
```

## 6. Security Analysis

### 6.1 Attack Vectors

**Attack 1: Bid without sufficient balance**
```
Attacker bids 100 ETH @ 200 OL/ETH
But has 0 OL balance

Mitigation:
- Balance check at bid time (line of sight check)
- Balance check at settlement (atomic execution)
- If balance insufficient → entire settlement reverts
- No partial execution possible
```

**Attack 2: Spend funds after bidding**
```
Bob bids 5 ETH @ 95 OL/ETH (has 500 OL)
Bob spends 400 OL before settlement
Now Bob has 100 OL (insufficient)

Mitigation:
- Settlement transaction reverts (atomic execution)
- Auction remains "Cleared" (can retry)
- If timeout expires → Alice refunds on Ethereum
- Bob's attack only hurts himself (misses opportunity)
```

**Attack 3: Front-run auction clearing**
```
Attacker sees clearing transaction coming
Submits bid at last second with higher price

Mitigation:
- Auction has fixed end time (bidding window closed)
- Late bids rejected (timestamp check)
- Clearing is deterministic (not MEV-able)
```

**Attack 4: Manipulate clearing price**
```
Attacker submits many small bids to push price up/down

Mitigation:
- Treasury auction is incentive-compatible
- Bidding too high → Attacker overpays
- Bidding too low → Attacker doesn't win
- Uniform price means everyone pays same (fair)
```

**Attack 5: Withhold preimage strategically**
```
Alice sees clearing price is good for her
But decides she wants better price → withholds preimage

Mitigation:
- Alice locked ETH on Ethereum (cost to her)
- Timeout expires → Alice refunds but wasted gas + time
- No gain from withholding (can't get better price)
- Winners not harmed (funds were never locked)
```

### 6.2 Atomic Execution Guarantees

**Move's Transaction Model:**
```
BEGIN TRANSACTION
  transfer(eve, alice, 190)
  transfer(carol, alice, 285)
  transfer(bob, alice, 475)
COMMIT or ABORT

If ANY transfer fails → ALL abort (atomicity)
```

**Cannot happen:**
- Partial settlement (e.g., Eve pays but Carol doesn't)
- Double-spend by winners
- Balance going negative
- Funds disappearing

**Guaranteed:**
- All-or-nothing execution
- Balance consistency
- No manual rollback needed

### 6.3 Time Lock Safety

**Critical timing:**
```
Auction end: +2 hours (bidding closes)
Settlement window: 2h to 24h (can settle anytime)
Ethereum timelock: +24 hours (Alice can refund after)
```

**Safety margin:**
```
If auction fails to clear by hour 2:
→ Alice has 22 hours to refund on Ethereum ✓

If settlement fails (insufficient balance):
→ Can retry until hour 24 ✓

If Alice withholds preimage:
→ Timeout at hour 24, Alice refunds ✓
```

**No deadlock possible:**
- Winners never lock funds (can't get stuck)
- Alice can always refund after timeout
- Settlement can be retried until timeout

## 7. Comparison to Alternatives

### 7.1 vs. Traditional HTLC (Symmetric)

| Feature | Traditional HTLC | Treasury Auction Design |
|---------|------------------|------------------------|
| **Escrow on both sides** | Yes (both lock funds) | No (only away side) |
| **Multi-party fill** | No (1:1 only) | Yes (N:1) |
| **Capital efficiency** | Low (funds locked) | High (funds unlocked) |
| **Price discovery** | Pre-negotiated | Auction mechanism |
| **Automation** | Manual coordination | Auto-bidding |
| **Counterparty risk** | Single party | Distributed |
| **Complexity** | Low | Medium |

### 7.2 vs. zkBridge + Orderbook

| Feature | zkBridge Design | Treasury Auction Design |
|---------|-----------------|------------------------|
| **Infrastructure needed** | ZK provers, checkpoints | None (just blockchain) |
| **Orderbook state** | Complex (continuous) | Simple (per-auction) |
| **Cross-chain proofs** | ZK proofs both ways | Preimage only |
| **Escrow** | Both sides | Away side only |
| **Price discovery** | Continuous orderbook | Per-auction clearing |
| **Trust assumptions** | Checkpoints, validators | Blockchain only |
| **Complexity** | Very high | Medium |

### 7.3 vs. Traditional DEX Bridge

| Feature | Bridge + DEX | Treasury Auction Design |
|---------|--------------|------------------------|
| **Wrapped assets** | Yes (always) | No (atomic) |
| **Liquidity fragmentation** | High | None (native assets) |
| **Bridge trust** | Validators/multisig | None (atomic swap) |
| **Censorship risk** | Medium (bridge can censor) | Low (permissionless) |
| **Capital efficiency** | High (pools) | Medium (per-auction) |
| **Price discovery** | Continuous AMM/orderbook | Per-auction |

## 8. Implementation Roadmap

### 8.1 Phase 1: Core HTLC Contracts (Week 1-2)

**Ethereum side:**
```
✓ MultiPartyHTLC.sol
  - lockETH()
  - setAllocation()
  - withdraw()
  - refund()

✓ Test coverage:
  - Multi-party withdrawal
  - Pro-rata allocation
  - Preimage verification
  - Timeout refunds
```

**Libra side:**
```
✓ treasury_auction_swap.move
  - create_auction()
  - submit_bid()
  - clear_auction()
  - settle_auction()

✓ Test coverage:
  - Auction clearing logic
  - Atomic settlement
  - Balance checks
  - Preimage verification
```

### 8.2 Phase 2: Auto-Bidding System (Week 3-4)

```
✓ User settings module
  - set_max_price()
  - enable/disable auto-bid
  - Max quantity per auction

✓ Auto-bid trigger
  - Watch for new auctions
  - Generate bids from settings
  - Respect balance limits

✓ Test coverage:
  - Auto-bid generation
  - Multiple users
  - Balance constraints
```

### 8.3 Phase 3: Auction Clearing Algorithm (Week 4-5)

```
✓ Sorting logic (price-descending)
✓ Clearing price calculation
✓ Pro-rata allocation when needed
✓ Edge cases:
  - Ties at clearing price
  - Insufficient demand
  - Exact match

✓ Gas optimization
✓ Test coverage (comprehensive scenarios)
```

### 8.4 Phase 4: Integration & E2E Testing (Week 6-7)

```
✓ Docker compose:
  - Local Ethereum testnet (Anvil/Hardhat)
  - Local Libra testnet (libra ops testnet)

✓ CLI tooling:
  - Create auction
  - Submit bid
  - Trigger clearing
  - Monitor status

✓ E2E test scenarios:
  - Full swap flow
  - Failed auction
  - Timeout refund
  - Multi-party settlement
```

### 8.5 Phase 5: Optimizations & Mainnet Prep (Week 8+)

```
✓ Gas optimization (Ethereum)
✓ Move bytecode optimization
✓ Security audit
✓ Economic analysis
✓ Documentation
✓ Mainnet deployment
```

## 9. Critical Design Challenges

### 9.0 Cross-Chain Verification Problem (UNRESOLVED - Critical)

**The Problem:**

How does Libra (home chain) know Alice actually locked ETH on Ethereum before starting the auction?

**Attack scenario without verification:**
```
1. Alice claims: "I locked 10 ETH on Ethereum, tx hash 0xabc123"
2. Auction starts on Libra
3. Bidders participate (Bob, Carol, Eve)
4. Auction clears at 95 OL/ETH
5. Winners try to settle → Alice reveals preimage
6. Winners check Ethereum → NO ETH LOCK EXISTS!
7. Alice collected OL tokens, never locked any ETH (fraud)
```

**The Fundamental Issue:**

Cross-chain atomic swaps inherently require **cross-chain state verification**. We eliminated escrow on the home chain, but we still need to verify the away chain lock exists.

---

### 9.0.1 Solution Options Analysis

#### Option 1: No Verification (Trust Alice) ❌

**How it works:**
- Alice just announces auction with claimed ETH lock details
- No on-chain verification
- Auction proceeds on trust

**Attack:**
- Alice starts fake auction (no real ETH lock)
- Collects OL tokens
- Winners can't claim ETH (doesn't exist)

**Verdict: INSECURE - Cannot use**

---

#### Option 2: Manual Verification by Bidders (Decentralized but Poor UX) ⚠️

**How it works:**
```
1. Alice announces auction:
   - ETH contract address: 0x123...
   - Lock ID: 0xabc...
   - Ethereum tx hash: 0xdef...

2. Before bidding, each user:
   - Connects to Ethereum RPC (Infura, Alchemy, own node)
   - Calls contract.locks(lockId) to verify
   - Checks: amount, hashlock, timelock all match
   - Only bids if verification passes

3. Auction proceeds normally

4. At settlement:
   - Winners already verified
   - Safe to transfer OL tokens
```

**Advantages:**
- ✅ Fully decentralized (no oracle/relayer)
- ✅ No trusted third party
- ✅ No additional infrastructure
- ✅ Cryptographically secure (bidders check themselves)

**Disadvantages:**
- ❌ Every bidder needs Ethereum RPC access
- ❌ Manual process (can't fully automate)
- ❌ Network costs (RPC calls)
- ❌ Auto-bidding becomes complex (need monitoring service)

**Implementation:**
```move
// Auction just stores Alice's claim (unverified)
struct Auction<phantom HomeCoin> has key, store {
    // ...
    eth_contract: vector<u8>,
    eth_lock_id: vector<u8>,
    eth_tx_hash: vector<u8>,  // For bidders to verify
    // No on-chain verification!
}

// Off-chain: Bidder's responsibility
// Use libra CLI or wallet to check before bidding
libra txs swap verify-eth-lock \
  --contract 0x123... \
  --lock-id 0xabc... \
  --expected-amount 10 ETH \
  --expected-hashlock 0xdef...
# Returns: ✓ Verified or ✗ Not found
```

**Verdict: WORKABLE - Decentralized but requires user diligence**

---

#### Option 3: ZK Proof Verification (Trustless but Complex) ⚠️

**How it works:**
```
1. Alice locks ETH on Ethereum
2. Alice generates ZK proof: "ETH lock exists in block B"
3. Alice submits proof to Libra when creating auction
4. Libra verifies proof on-chain
5. Auction only starts if proof valid
```

**Advantages:**
- ✅ Trustless (cryptographic verification)
- ✅ On-chain verification (bidders don't need to check)
- ✅ Secure against fraud

**Disadvantages:**
- ❌ Requires ZK proof infrastructure (what we were avoiding!)
- ❌ Alice needs to run prover (30-60 seconds)
- ❌ Complex implementation (light client verifier)
- ❌ Gas costs on Libra (proof verification)

**Verdict: SECURE but brings back complexity we wanted to avoid**

---

#### Option 4: Optimistic Auction (Lazy Verification) 🤔

**How it works:**
```
1. Alice announces auction (no verification)
2. Auction proceeds normally
3. At clearing: Still no verification
4. At settlement time:
   - Winners must verify ETH lock exists before settling
   - If lock doesn't exist → don't call settle_auction()
   - Auction expires, no settlement
   - Alice wasted her time, bidders lose nothing

5. Optional: Challenge period
   - Anyone can challenge Alice's claim
   - Provide proof ETH lock doesn't exist
   - Alice loses posted bond
```

**Advantages:**
- ✅ No verification needed at auction start
- ✅ Simple implementation
- ✅ Bidders protected (don't settle if no lock)
- ✅ Honest Alice has smooth UX

**Disadvantages:**
- ⚠️ Wastes everyone's time if Alice is dishonest
- ⚠️ Bidders still need to verify before settlement
- ⚠️ Optional bond/challenge adds complexity

**Implementation:**
```move
// Auction proceeds without verification
create_auction<HomeCoin>(...);  // No proof required

// At settlement: Winner verifies off-chain first
// Only calls settle_auction() if they verified ETH lock exists
settle_auction<HomeCoin>(auction_id, preimage);

// If no one settles (because no lock exists):
// → Auction expires after timelock
// → No harm to bidders (funds never left wallets)
// → Alice wasted her time (reputation damage)
```

**Verdict: SIMPLE but relies on settlement-time verification**

---

#### Option 5: Light Oracle (Minimal Trust) 🤔

**How it works:**
```
1. Run simple oracle service (anyone can run it)
2. Oracle watches Ethereum chain
3. When Alice locks ETH:
   - Oracle posts attestation to Libra
   - "ETH lock 0xabc exists, verified at block N"

4. Auction creation requires oracle attestation
5. Multiple independent oracles (threshold signatures)
```

**Advantages:**
- ✅ On-chain verification (bidders don't check)
- ✅ Simpler than ZK proofs
- ✅ Can use multiple oracles (decentralize)

**Disadvantages:**
- ❌ Introduces trusted party (oracle)
- ❌ Oracle can censor/lie
- ❌ Requires running oracle infrastructure
- ❌ Need incentive mechanism for oracle operators

**Verdict: Works but centralizes (what we wanted to avoid)**

---

#### Option 6: Ethereum Light Client on Libra (Complex but Trustless) 🤔

**How it works:**
```
1. Libra runs Ethereum light client (on-chain or as module)
2. Light client syncs Ethereum block headers
3. Alice creates auction:
   - Provides Merkle proof of ETH lock
   - Proof verified against synced headers
   - Auction only starts if valid

4. Ongoing: Light client stays synced
   - Validators/nodes maintain sync
   - Or: checkpoint-based (submit headers periodically)
```

**Advantages:**
- ✅ Trustless (cryptographic verification)
- ✅ No external oracle needed
- ✅ On-chain verification

**Disadvantages:**
- ❌ Very complex implementation
- ❌ Ongoing sync overhead (who submits headers?)
- ❌ Storage cost (block headers)
- ❌ If checkpoints: Similar to zkBridge approach

**Verdict: Theoretically ideal but complex**

---

### 9.0.2 Recommended Approach: Hybrid Strategy

**Phase 1 - MVP (Optimistic + Manual):**
```
1. No on-chain verification required
2. Bidders manually verify ETH lock before bidding
3. Settlement requires verification by winners
4. Optional: Alice posts small bond (reputation stake)

Implementation:
- Simple smart contracts
- CLI tool for verification
- Documentation for users
```

**Advantages:**
- Simple to implement
- Fully decentralized
- No infrastructure dependencies

**User flow:**
```bash
# Alice locks ETH on Ethereum
cast send $HTLC_CONTRACT "lockETH(...)" --value 10ether

# Alice creates auction on Libra (just announces)
libra txs swap create-auction \
  --eth-contract 0x123... \
  --eth-lock-id 0xabc... \
  --eth-tx-hash 0xdef...

# Bob verifies before bidding
libra txs swap verify-eth-lock \
  --auction-id 1 \
  --ethereum-rpc $INFURA_URL
# Output: ✓ ETH lock verified

# Bob bids (after verification)
libra txs swap bid --auction-id 1 --max-price 95

# Settlement (Bob already verified, safe to proceed)
libra txs swap settle --auction-id 1 --preimage 0x...
```

**Phase 2 - Enhanced (Light Oracle):**
```
1. Community runs optional oracle services
2. Oracle watches Ethereum, posts attestations
3. Auctions with oracle attestation = higher trust
4. Auctions without attestation = require manual verification

Multi-sig oracle (3-of-5):
- 5 independent oracle operators
- 3 signatures required for attestation
- Decentralized but not fully trustless
```

**Phase 3 - Advanced (ZK or Light Client):**
```
If volume justifies complexity:
1. Implement ZK proof verification
2. Or: Ethereum light client on Libra
3. Full trustless verification
```

---

### 9.0.3 The Honest Trade-Off

**The fundamental truth:** Cross-chain atomic swaps CANNOT avoid cross-chain verification.

**Our options:**
1. **Trust** (oracle/relayer) → Centralization risk
2. **Cryptography** (ZK/light client) → Implementation complexity
3. **Manual** (users verify) → UX friction

**What we achieved with treasury auction design:**
- ✅ Eliminated escrow on home chain (capital efficiency)
- ✅ Eliminated complex orderbook (simplicity)
- ✅ Enabled multi-party fills (better liquidity)

**What we cannot eliminate:**
- ⚠️ Cross-chain state verification (inherent to atomic swaps)

**The verification must happen somewhere:**
- Traditional HTLC: Users verify manually
- zkBridge: ZK proof verification on-chain
- Traditional bridge: Oracle attestation
- **This design: User verification (same as traditional HTLC)**

**Compared to zkBridge approach:**
- zkBridge: On-chain verification (ZK proofs) → Complex but automated
- This design: Off-chain verification (manual) → Simple but manual

**Trade-off choice:**
- Accept manual verification for simplicity
- Or add ZK/oracle for automation (loses simplicity advantage)

---

### 9.1 Multi-Party Transfer Authorization (Resolved ✓)

**Question:** Can Move actually execute multi-party transfers atomically in one transaction?

**Answer: Yes** - Users can authorize the contract to withdraw from their accounts.

**Authorization Mechanism:**
```move
// Users grant withdrawal authorization when bidding
public entry fun submit_bid_with_authorization<HomeCoin>(
    bidder: &signer,
    auction_id: u64,
    max_price: u64,
    quantity: u64,
) acquires AuctionRegistry {
    // Submit bid
    submit_bid<HomeCoin>(bidder, auction_id, max_price, quantity);

    // Grant contract authorization to withdraw winning amount
    // This authorization is specific to this auction
    coin::delegate_withdrawal<HomeCoin>(
        bidder,
        @ol_framework,  // Contract address
        auction_id,     // Scoped to this auction
        max_price * quantity  // Maximum authorized amount
    );
}
```

**Atomic Settlement Pattern:**
```move
/// Atomic settlement - executes all transfers in one transaction
public entry fun settle_auction<HomeCoin>(
    caller: &signer,
    auction_id: u64,
    preimage: vector<u8>,
) acquires AuctionRegistry {
    let registry = borrow_global_mut<AuctionRegistry<HomeCoin>>(@ol_framework);
    let auction = table::borrow_mut(&mut registry.auctions, auction_id);

    // Verify preimage
    assert!(sha2_256(preimage) == auction.away_hash_lock, E_INVALID_PREIMAGE);

    let winners = get_winning_bids(auction_id, auction.clearing_price);

    // ATOMIC: All transfers execute or all fail
    let i = 0;
    while (i < vector::length(&winners)) {
        let winner = vector::borrow(&winners, i);

        // Contract uses pre-authorized withdrawal capability
        coin::withdraw_delegated<HomeCoin>(
            @ol_framework,      // Contract withdraws
            winner.bidder,      // From winner's account
            auction.initiator,  // To Alice
            winner.amount,      // Authorized amount
            auction_id          // Authorization scope
        );

        i = i + 1;
    };

    auction.status = 2;  // Settled
}
```

**Key Properties:**

1. **Pre-authorization at bid time**
   - Users authorize maximum withdrawal when bidding
   - Authorization scoped to specific auction
   - Can't be used for other purposes

2. **Atomic execution**
   - All withdrawals happen in one transaction
   - If any fails (insufficient balance), all revert
   - No partial settlements possible

3. **Security guarantees**
   - Authorization limited to auction amount
   - Expires when auction settles or times out
   - Users can revoke before settlement

4. **Capital efficiency**
   - Funds never locked/escrowed
   - Users retain custody until settlement
   - Can participate in multiple auctions simultaneously

**Why this works better than claim pattern:**
- Truly atomic (all transfers or none)
- Single transaction settlement (cheaper gas)
- Instant finality (no waiting for each claim)
- Simpler UX (winners don't need separate transactions)

### 9.2 Auction Duration Optimization

**Question:** What's the optimal auction duration?

**Considerations:**
- Too short → Not enough bids, poor price discovery
- Too long → Alice's capital locked longer, slow UX

**Research:**
- Empirical testing with different durations
- Does auto-bidding reduce need for long auctions?
- Can we use dynamic durations based on asset/amount?

### 9.3 MEV on Auction Clearing

**Question:** Can miners/validators extract MEV by timing auction clearing?

**Scenario:**
```
Block N: Auction ends, high clearing price visible
Block N+1: Validator delays clearing transaction
Block N+1: Validator's own bid submitted
Block N+2: Clearing happens with validator's bid included
```

**Mitigation options:**
1. Anyone can clear (first successful transaction wins)
2. Clearing is deterministic (MEV doesn't change outcome)
3. Late bids rejected (timestamp check)

**Still concerning:**
- Validator could censor competing bids
- Or delay clearing to allow friendly bids

**Research needed:**
- Is this actually profitable?
- Can we make clearing more MEV-resistant?

### 9.4 Cross-Chain Price Oracle

**Question:** How do users know fair prices for auto-bidding?

**Problem:**
- Bob sets max 100 OL/ETH
- But what if ETH is worth 200 OL on other exchanges?
- Bob overpays significantly

**Possible solutions:**
1. Off-chain price feeds (Chainlink, Pyth)
2. Historical auction results (on-chain)
3. User responsibility (they set their own max)

**Research:**
- Should protocol enforce price sanity checks?
- Or leave pricing entirely to users?
- Can we use recent auction results as reference?

### 9.5 Liquidity Bootstrapping

**Question:** How to ensure sufficient bids in early days?

**Cold start problem:**
- No auctions → No historical data
- No auto-bidders → No liquidity
- Poor clearing prices → Discourages use

**Potential solutions:**
1. Market makers commit to auto-bid for bootstrap period
2. Incentive program (protocol rewards early participants)
3. Gradual rollout (start with small amounts)

**Research:**
- What's minimum viable liquidity?
- How to incentivize early adopters?

### 9.6 Partial Fill Handling

**Question:** What if auction clears but settles only 8 of 10 ETH?

**Scenario:**
```
Auction for 10 ETH
Bids total 8 ETH at clearing price
→ Underfilled auction
```

**Current design:** Reject if minimum not met

**Alternative:** Allow partial fills?
```
Alice specified: minimum 900 OL (90 OL/ETH × 10 ETH)
Auction clears: 8 ETH at 95 OL/ETH = 760 OL
→ Below minimum, rejected

But what if minimum was 700 OL?
→ Could accept 8 ETH fill
```

**Research:**
- Should we support partial fills?
- Adds complexity on Ethereum side (refund 2 ETH to Alice)
- But improves fill rates

## 10. Economic Analysis

### 10.1 Capital Efficiency Comparison

**Traditional HTLC (both sides lock):**
```
Alice locks 10 ETH for 24h
Bob locks 1000 OL for 24h
→ Total: ~$20,000 locked (assuming $2k ETH)
→ Capital efficiency: Poor
```

**zkBridge design (escrow on both):**
```
Alice locks 10 ETH in escrow
Bob locks 1000 OL in escrow
→ Total: ~$20,000 locked
→ Capital efficiency: Poor (same as HTLC)
```

**Treasury auction (only away side locks):**
```
Alice locks 10 ETH for 24h
Bob/Carol/Eve: 0 OL locked (funds stay available)
→ Total locked: ~$20,000 (Alice only)
→ Capital efficiency: 50% better
```

**But wait - even better for bidders:**
```
Bob can bid on multiple auctions with same capital:
- Bids 500 OL on Alice's auction
- Bids 500 OL on Frank's auction
- Bids 500 OL on Grace's auction

Only pays when auction settles (atomic)
→ Capital efficiency: Much higher for Libra users
```

### 10.2 Price Efficiency

**Treasury auction uniform pricing:**
- Reduces winner's curse
- Encourages truthful bidding
- Well-studied mechanism (U.S. Treasury uses it)

**Expected outcomes:**
- Prices converge to market rate
- Low variance between auctions (with sufficient liquidity)
- Efficient price discovery

**Comparison to alternatives:**
- Better than discriminatory auction (fairer)
- Similar to continuous orderbook (with lag)
- Simpler than complex MEV-resistant mechanisms

### 10.3 Gas Costs

**Ethereum side:**
```
lockETH(): ~50k gas (~$5-10)
setAllocation(): ~100k gas (~$10-20) - scales with # winners
withdraw() × N: ~30k each (~$3-5 per winner)

Total for Alice: ~$15-30
Total per winner: ~$3-5
```

**Libra side:**
```
create_auction(): ~$0.01
submit_bid(): ~$0.001 each
clear_auction(): ~$0.05 (sorting logic)
settle_auction(): ~$0.10 (multi-transfer)

Total for Alice: ~$0.11
Total per winner: ~$0 (settlement pays for everyone)
```

**Overall cost:**
- Alice: ~$15-30 (Ethereum heavy)
- Winners: ~$3-5 each (Ethereum withdrawal only)
- Much cheaper than zkBridge (~$50-100 per swap with ZK proofs)

## 11. Advantages & Trade-offs

### 11.1 Advantages

**1. No escrow on home chain**
- Users retain control of funds
- No locked capital
- Can participate in multiple auctions

**2. Leverages Move's strengths**
- Atomic multi-party execution
- Resource safety
- No manual refunds needed

**3. Simple infrastructure**
- No ZK provers required
- No checkpoint mechanisms
- No oracle dependencies
- Just blockchain + auction logic

**4. Fair price discovery**
- Treasury auction well-studied
- Uniform pricing (no discrimination)
- Transparent process

**5. Automation-friendly**
- Auto-bidding from settings
- Passive participation
- Always-on liquidity

**6. No wrapped assets**
- True atomic swap
- No custody risk
- No bridge vulnerabilities

### 11.2 Trade-offs

**1. Auction latency**
- Must wait for auction to end (e.g., 2 hours)
- Not instant like orderbook
- Trade-off: Fairness vs. speed

**2. Price discovery lag**
- Prices update per-auction, not continuously
- May have variance between auctions
- Trade-off: Simplicity vs. efficiency

**3. Away side must lock entire amount**
- Can't fractionalize on Ethereum
- Alice locks all 10 ETH (even if only 8 ETH filled)
- Trade-off: Simplicity vs. flexibility

**4. Requires participation**
- Auctions fail without bids
- Liquidity not guaranteed
- Trade-off: Decentralization vs. reliability

**5. Multi-party coordination complexity**
- Multiple winners must withdraw on Ethereum
- Allocation mechanism needed
- Trade-off: Capital efficiency vs. complexity

## 12. Conclusion

This treasury auction atomic swap design offers a compelling middle ground:

**Simpler than zkBridge:**
- No ZK proofs, checkpoints, or complex infrastructure
- Auction clearing is straightforward algorithm
- Standard HTLC on away chain

**More efficient than traditional HTLC:**
- No escrow on home chain (capital efficiency)
- Multi-party filling (better liquidity)
- Auto-bidding (better UX)

**Leverages Libra's unique strengths:**
- Move's atomic execution
- Resource safety
- Transaction model that enables multi-party transfers

**Key innovation:** Asymmetric atomicity - simple locking on away chain, sophisticated auction settlement on home chain, with no escrow needed on home side.

**Next steps:**
1. Resolve open questions (especially multi-party transfer authorization)
2. Implement Phase 1 (core contracts)
3. Test auction clearing algorithm extensively
4. Build E2E test environment
5. Economic modeling and simulation

**Success criteria:**
- Auctions clear reliably (>90% success rate)
- Prices converge to market rates (low variance)
- Capital efficiency gains realized (measured in practice)
- Security properties maintained (no fund loss)
- Better UX than alternatives (faster, simpler)

This design represents a novel approach to cross-chain swaps that avoids both the complexity of zkBridges and the capital inefficiency of symmetric HTLCs by leveraging the specific capabilities of the Move programming language and treasury auction price discovery mechanisms.

## 13. Key Innovation Summary

### 13.1 Authorization-Based Atomicity

**The Core Insight:** Move's authorization mechanism enables multi-party atomic settlements without escrow.

**How it works:**
1. Users authorize contract to withdraw when bidding
2. Funds stay in user wallets (no lock/escrow)
3. At settlement, contract executes all authorized withdrawals atomically
4. All transfers succeed or all fail (Move transaction atomicity)

**Why this matters:**
- **No capital lock on home chain** - unprecedented capital efficiency
- **Multi-party fills** - many users fill one away-chain trade
- **True atomicity** - all transfers in one transaction
- **Simple infrastructure** - no ZK proofs, no checkpoints, no oracles

### 13.2 Asymmetric Simplicity

**Away chain (Ethereum):**
- Simple HTLC (hash + time lock)
- Single party locks entire amount
- ~100 lines of Solidity
- Battle-tested primitives

**Home chain (Libra):**
- Treasury auction clearing
- Multi-party authorization
- Atomic settlement
- Leverages Move's unique capabilities

**Result:** Complexity only where needed, simplicity where possible.

### 13.3 Comparison to zkBridge Approach

| Aspect | zkBridge Design | Treasury Auction Design |
|--------|-----------------|------------------------|
| **Infrastructure** | ZK provers, checkpoints, monitoring | None (just blockchain) |
| **Escrow** | Both chains | Only away chain |
| **Atomicity** | Checkpoints + ZK proofs | Move authorization + atomicity |
| **Multi-party** | Complex (orderbook state) | Simple (auction per trade) |
| **Capital efficiency** | Low (both sides lock) | High (home side no lock) |
| **Trust assumptions** | Validator signatures, checkpoints | Blockchain consensus only |
| **Complexity** | Very high | Medium |
| **Cost per swap** | ~$50-100 (ZK proofs) | ~$15-30 (HTLC only) |

### 13.4 The "Authorization Not Escrow" Paradigm

**Traditional thinking:**
- Cross-chain swap = both sides must escrow
- Escrow = move funds to contract
- Settlement = release escrowed funds

**This design:**
- Away chain = traditional escrow (simple HTLC)
- Home chain = authorization without escrow
- Settlement = execute authorized withdrawals atomically

**Enabled by:**
- Move's authorization capabilities
- Move's transaction atomicity guarantees
- Move's resource safety (coins can't disappear mid-transaction)

**Result:** Better capital efficiency without sacrificing security.

### 13.5 Production Readiness Path

**Phase 1 (Weeks 1-2):** Core contracts
- ✓ Simple, proven primitives
- ✓ No novel cryptography
- ✓ Testable independently

**Phase 2 (Weeks 3-4):** Auto-bidding
- ✓ Optional feature (works without it)
- ✓ User-controlled settings
- ✓ Enhances liquidity

**Phase 3 (Weeks 5-6):** Integration
- ✓ E2E testing
- ✓ Economic simulation
- ✓ Security audit

**Phase 4 (Weeks 7-8):** Launch
- ✓ Gradual rollout (small amounts first)
- ✓ Monitor auction clearing rates
- ✓ Iterate based on real usage

**Conservative estimate:** 8-12 weeks to production-ready implementation.

**Risk profile:** Low - uses proven primitives (HTLC + auction), no experimental tech.

---

## Final Verdict

### What This Design Achieves

**✓ Away assets traded in entirety** (no fractionalization on Ethereum)
**✓ Home assets filled fractionally** (multi-party via authorization)
**✓ No escrow on home chain** (capital efficiency - major win)
**✓ Simple away chain** (standard HTLC, ~100 LOC)
**✓ Leverages Move's strengths** (authorization + atomicity)
**✓ Multi-party atomic settlement** (enabled by Move's authorization model)

### What This Design Does NOT Eliminate

**⚠️ Cross-chain verification requirement** (inherent to atomic swaps)

**The fundamental limitation:**

Cross-chain atomic swaps CANNOT avoid verifying that the away-chain lock exists. This verification must happen through one of:

1. **Manual verification** (users check Ethereum themselves)
2. **Oracle/relayer** (trusted third party)
3. **ZK proofs** (cryptographic verification)
4. **Light client** (on-chain Ethereum state sync)

**Our recommendation: Manual verification (Phase 1 MVP)**
- Fully decentralized (no trust required)
- Simple implementation
- Users verify ETH lock before bidding
- Same trust model as traditional HTLCs

### Comparison to Alternatives

**vs. zkBridge approach:**
| Aspect | zkBridge | Treasury Auction |
|--------|----------|------------------|
| Home chain escrow | Yes | **No** ✓ |
| Away chain verification | ZK proof (on-chain) | Manual (off-chain) |
| Multi-party fills | Complex orderbook | Simple auction ✓ |
| Infrastructure | ZK provers, checkpoints | **None** ✓ |
| Complexity | Very high | Medium ✓ |
| Cost | ~$50-100 | ~$15-30 ✓ |

**Trade-off:**
- zkBridge: Automates verification (complex)
- This design: Manual verification (simple)

Both require verification, just different approaches.

**vs. Traditional symmetric HTLC:**
| Aspect | Symmetric HTLC | Treasury Auction |
|--------|----------------|------------------|
| Escrow both sides | Yes | Away only ✓ |
| Multi-party | No (1:1) | **Yes (N:1)** ✓ |
| Capital efficiency | Low | **High** ✓ |
| Verification | Manual | Manual (same) |

**Wins:**
- Better capital efficiency (no home escrow)
- Multi-party fills (better liquidity)
- Same verification model (manual)

### The Honest Assessment

**What we successfully eliminated:**
- ✅ Home chain escrow (big capital efficiency win)
- ✅ Complex orderbook state (simplicity win)
- ✅ zkBridge infrastructure (cost/complexity win)

**What we cannot eliminate:**
- ⚠️ Cross-chain verification (inherent to atomic swaps)

**Acceptable trade-off:**
- Accept manual verification (like traditional HTLC)
- Gain capital efficiency + multi-party fills
- Keep implementation simple

**Key enabler:** Move's authorization mechanism enables multi-party atomic settlements without escrow, which is genuinely novel.

**Bottom line:** This design offers a **better capital-efficient atomic swap** by eliminating home-chain escrow, but does not solve the cross-chain verification problem (no atomic swap design can eliminate this without trust/complexity trade-offs).

This represents a **pragmatic middle ground** between traditional HTLCs (inefficient capital) and zkBridges (complex infrastructure), optimized for the Move programming model's unique capabilities.
