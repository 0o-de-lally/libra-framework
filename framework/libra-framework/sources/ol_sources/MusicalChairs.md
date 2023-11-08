# MUSICAL CHAIRS

#### TL;DR: We believe that the validator set size is a technical software constraint that should not be altered through political means. It's a crucial part of our community's vision: creating an independent blockchain without governance from a central "foundation" company or relying on Proof-of-Stake games.

## Problem Definition:
How does a network determine the appropriate number of validator seats for achieving consensus? In most practical BFT networks, this number is typically decided externally (by founders or a foundation). However, errors can arise in setting this number.

## Thesis:
Fundamentally, we believe that the number of participants in consensus is bound
by the quality of the software, considering:

A. The network architecture: The type of networking and consensus sets some upper bounds.
B. The implementation quality: Even the best architecture, if riddled with errors (such as state synchronization issues), sets limits on the network.
C. Network operator convenience: Is the software user-friendly, requiring minimal intervention? Is it accessible to casual users or solely manageable by professional IT organizations under contract to a foundation? These answers are usually not known a priori, and definitive solutions are elusive.

Any attempts to fix these issues might push the problem into the realm of "governance," necessitating interventions to set new upper bounds. However, this solution is not acceptable, as it only adds complexity to the decision space of the network. The validator set size is not merely a technical matter but also a political economy issue; enforcing an upper bound ensures some competition among validators, which might be undesirable for the least competitive.

You can then arrive at an equilibrium where you are overpaying for security, subsidizing the least competitive.

## History

We've learned this through experience. Initially, a hard limit of 100 validators was set at genesis. At that time, concerns were voiced about whether this limit was too low or unfairly privileged early validators. However, it later became evident (up to version 5) that the 100 limit was far too high due to synchronization architecture problems, requiring intervention biased towards more professional validators, alongside unwieldy software maintenance and debugging challenges.

The 0L reward auction did respond correctly throughout, but at a higher network cost than initially anticipated due to the increased rewards issued. Various engineering experiments were conducted to address these issues, but the community refrained from the seemingly "easy" solution of resetting the 100-node limit, understanding that such an alteration could spark prolonged political debates.

## BFT In the Wild
In the realm of consensus algorithms such as Byzantine Fault Tolerance (BFT), the typical upper limit for the validator set usually resides within a range of a few hundred nodes. However, it's noteworthy that in Proof-of-Stake frameworks, while there may be thousands of registered validators only a small fraction of those will actively participate in the block generation process. This discrepancy arises from the fact that a validator's voting influence is directly proportional to their stake. In contrast to the requirement in some systems where 66% of validators must sign, in Proof-of-Stake, only 66% of the economic stake needs to endorse the transactions. Consequently, the number of 'block-producing' validators operational in real-world networks seldom exceeds a count of 100. It's important to highlight that while this isn't a stipulation of BFT, it forms an economic incentive within PoS (on 0L, each validator has an equal vote).

As such, besides authorities hard-coding a limit to registration, in practice upper-bounds are also set by the ability of the validators to aggregate capital, and the curve of the allocation of that capital (e.g. what was the distribution of the premine", does the foundation "rent" stake to validators, do centralized exchanges offer "staking as a service").

So, how can a viable validator set size be consistently chosen without relying on politics, authority or PoS?

## The Approach
Our approach is named "Musical Chairs." This experiment aims to estimate the network's supportable nodes based on internal performance metrics: can the network sustain itself at the current validator set size, or should it be adjusted up or down?

Our approach involves employing a range of metrics, initially beginning with an on-chain simple heuristic: compliant node cardinality. Other potential heuristics may be explored, provided that the information is consistently and securely recorded within the blockchain.

The criteria we establish primarily revolve around the maximum number of seats per validator. If all validators perform optimally, the network cautiously increases the threshold by 1 node. However, validators don't have an assured entry into the subsequent epoch based on their performance. This concern has been addressed experimentally through our Proof-of-Fee game, a distinct approach from Proof-of-Stake.

Conversely, when the network performs poorly (few validators perform adequately), the threshold must be decreased. The reduction in seats shouldn't follow a predetermined unit but should match the number of compliant and performant nodes, resembling a "musical chairs" game.

Several implementation details are commented on in the code below (e.g., if less than 5% fail to perform, no changes occur). Generally, the primary implementation consideration is that the algorithm cautiously increases the validator set for optimal performance while predictably decreasing seats to ensure the network's peak performance.

The design objective is for the algorithm to have a "thermostatic" quality: continuously adjusting until it finds a balance suitable for the prevailing social, technical, and economic conditions.
