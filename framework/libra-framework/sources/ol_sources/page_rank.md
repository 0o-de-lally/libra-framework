**Title:** Lazy Trust Scoring and Revocation Handling in Constrained Environments

**Context:**
We're working in a constrained compute/storage environment (e.g., a blockchain VM) and need to compute trust scores for user accounts. Each user can vouch for or revoke trust in another user. Our goal is to approximate how closely a node is connected to a fixed list of 20 trusted "root" accounts, with minimal storage and on-demand computation.

---

### 1. Problem Definition
- Each account can establish a **vouch (trust)** or **revoke (distrust)** relationship with another.
- We need to compute a **trust score** for each account that approximates closeness to the trusted roots.
- Due to constraints, storing full edge data and recomputing the graph on every change is infeasible.

---

### 2. Core Design: Dual Trust Graphs
We split the trust network into two parallel, append-only graphs:

#### A. Vouch Graph
- Directed edges from user A to user B indicate that A vouches for B.
- Trust propagates outward from the root nodes.

#### B. Revoke Graph
- Directed edges indicate a revocation of trust.
- This separately propagates negative influence.

**Final Trust Score:**
```text
total_score(node) = f(vouch_score(node), revoke_score(node))
```
Common combining functions:
- `max(0, vouch_score - revoke_score)`
- `vouch_score / (1 + revoke_score)`
- `alpha * vouch_score - beta * revoke_score`

This approach allows non-destructive updates and naturally supports lazy evaluation.

---

### 3. Lazy PageRank Approximation Strategies

To keep scores fresh and recomputation light, we apply **lazy approximations** of PageRank.

#### A. Monte Carlo PageRank (Random Walks)
- Simulate random walks from root nodes.
- At query time, run N walks of limited depth (e.g., 3–5 hops).
- Count the number of times each node is hit and normalize the score.

**Pros:**
- Fully on-demand, no graph materialization needed
- Separate walks for vouch and revoke graphs
- Easy to normalize and combine

#### B. Personalized PageRank (PPR) with Bookmarks
- Root nodes initiate walks with reset probability.
- Use memoization and time-decay to cache trust scores lazily.

#### C. Local Push (Forward Push)
- Propagate trust from updated nodes only when residual trust > epsilon.
- Useful for sparse, changing graphs.

---

### 4. Handling Revocations
Revocations often require full recomputation in naive models. We avoid this by:

#### A. Treating Revokes as a Separate Graph
- Revokes are appended to a separate graph.
- No destructive updates: trust scores remain until offset by revoke score.

#### B. Lazy Score Expiry or Invalidation
- Each node stores `trust_score`, `updated_at`, and TTL.
- If a vouch is revoked, the corresponding trust score decays naturally or gets marked for lazy recomputation.

#### C. Optional: Reverse Indexing for High-Trust Nodes
- For root or near-root nodes, keep a reverse index of downstreams to invalidate trust more directly.

---

### 5. Suggested Implementation Pattern

- Store per-node metadata:
```plaintext
trust_score_vouch
trust_score_revoke
last_updated_block
```
- On user interaction or trust query:
  1. Run N random walks from root nodes on both graphs.
  2. Combine hit counts into a final score.
  3. Cache result with expiration logic.

---

### 6. Alternatives Considered and Rejected

#### A. Full Graph Storage with Matrix PageRank
- **Why not:** Storage costs are prohibitive on-chain, and updating the matrix is not feasible after every edge change.

#### B. Recomputing Global PageRank on Every Write
- **Why not:** Requires reprocessing the entire graph on every vouch/revoke, which is computationally infeasible.

#### C. Merkleized DAG for Trust Paths
- **Why not:** Complex to implement and verify path validity across multiple hops, and not suitable for frequent edge churn.

#### D. Limiting Trust to One-Hop Relationships
- **Why not:** Too simplistic, doesn’t capture transitive trust which is central to PageRank-style models.

---

### 7. Summary
By modeling trust and revocation as dual graphs and using lazy Monte Carlo approximations, we can:
- Avoid global recomputation
- Achieve scalable, query-based trust evaluations
- Support revocation as a natural, non-destructive influence

This design supports flexible, real-time trust evaluation even in constrained environments like blockchain VMs.
