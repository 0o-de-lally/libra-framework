# Dynamic Root of Trust Calculation

## Overview

This document outlines the specification for a dynamic Root of Trust (RoT) calculation mechanism for the Libra Framework. Instead of using a static list of "root" addresses, this approach identifies the actual roots of trust by finding the common vouches across all candidate root addresses.

## Motivation

A static list of root addresses can lead to centralization and single points of failure. By dynamically calculating the root of trust based on collective vouching behavior, we can create a more robust and decentralized trust system that adapts to changing network conditions.

## Architecture

### Components

1. **Candidate Roots**: The existing `RootOfTrust.roots` structure will be maintained as a list of candidate root addresses.

2. **Dynamic Root Calculation**: A new module `dynamic_root_of_trust` will calculate the actual roots of trust by identifying addresses that are vouched for by all candidates.

3. **Integration Points**: The existing trust score calculation will be modified to use the dynamic roots while maintaining backward compatibility.

### Design Principles

1. **Avoid Circular Dependencies**: The new module will import the `root_of_trust` and `vouch` modules but will not be imported by them, preventing circular dependencies.

2. **Use Modern API**: The implementation will use current view functions from the `vouch` module instead of deprecated structures.

3. **Fallback Mechanism**: If no common vouches are found among candidates, the system will fall back to using the original candidate list.

## Implementation Strategy

### 1. Dynamic Root Calculation Algorithm

The core algorithm works as follows:
1. Start with the outbound vouches (given_vouches) from the first candidate
2. For each additional candidate:
   - Find the intersection of their outbound vouches with the current set
   - Update the working set to only include addresses in this intersection
3. The final set represents addresses that all candidates vouch for

### 2. Module Structure

```
dynamic_root_of_trust
├── Imports: root_of_trust, vouch
├── Public Functions
│   ├── get_dynamic_roots() - Returns the common vouches across all candidates
│   └── has_common_vouches() - Checks if candidates have any common vouches
└── Internal Functions
    └── find_intersection() - Helper function for finding common addresses
```

### 3. Trust Score Integration

The existing scoring mechanism in `page_rank_lazy` will be updated to:
1. First attempt to use dynamically calculated roots
2. Fall back to candidate roots if no common vouches exist
3. Preserve all existing behavior for backward compatibility

## Benefits

1. **Decentralization**: Power shifts from designated candidates to collectively vouched-for addresses
2. **Consensus-Based Trust**: Root of trust emerges from agreement among candidates
3. **Resilience**: The system can adapt as vouching patterns change
4. **Backward Compatibility**: Existing mechanisms continue to work with minimal disruption

## Potential Challenges

1. **Empty Intersection**: If candidates have no common vouches, the system falls back to candidates
2. **Performance**: Finding intersections across many candidates could be computationally expensive
3. **Low-Trust Periods**: During transitions or disagreements, the common set might be small

## Future Enhancements

1. **Weighted Dynamic Roots**: Consider frequency of vouching when no perfect intersection exists
2. **Reputation Ranking**: Further rank dynamic roots by other on-chain metrics
3. **Time-Windowed Analysis**: Include time factors to prevent gaming of the system
