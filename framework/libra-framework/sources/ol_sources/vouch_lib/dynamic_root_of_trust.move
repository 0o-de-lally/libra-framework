/// This module implements a dynamic root of trust calculation mechanism
/// that identifies the actual roots of trust by finding addresses
/// that are commonly vouched for by all candidates in the root of trust list.
///
/// Instead of using a static list of root addresses, this implementation
/// calculates the "common denominator" of all vouches given by candidate roots.
/// This creates a more decentralized and consensus-based trust system.
module ol_framework::dynamic_root_of_trust {
    use std::vector;
    use ol_framework::root_of_trust;
    use ol_framework::vouch;

    #[view]
    /// Calculates the dynamic root of trust by finding addresses that all candidate
    /// roots vouch for (common vouches).
    ///
    /// @param registry - The address where the root of trust registry is stored
    /// @return Vector of addresses that are vouched for by all candidates
    public fun get_dynamic_roots(registry: address): vector<address> {
        // Get candidate roots from the registry
        let candidates = root_of_trust::get_current_roots_at_registry(registry);

        // If there are no candidates, return empty vector
        if (vector::length(&candidates) == 0) {
            return vector::empty<address>()
        };

        // Get the vouches of the first candidate as the initial set
        let first_candidate = *vector::borrow(&candidates, 0);
        let first_vouches = vouch::get_given_vouches_not_expired(first_candidate);

        // If the first candidate has no vouches, return empty vector
        if (vector::length(&first_vouches) == 0) {
            return vector::empty<address>()
        };

        // Initialize common vouches with the first candidate's vouches
        let common_vouches = first_vouches;
        // Add the first candidate's own address to their vouches
        // otherwise through iteration we end up with an empty vector
        // also doing the same within the loop.
        vector::push_back(&mut common_vouches, first_candidate);

        // For each additional candidate, find the intersection of vouches
        let i = 1;
        while (i < vector::length(&candidates)) {
            let candidate = *vector::borrow(&candidates, i);
            let candidate_vouches = vouch::get_given_vouches_not_expired(candidate);

            // Add the candidate's own address to their vouches
            vector::push_back(&mut candidate_vouches, candidate);

            // Update common_vouches to only include addresses that appear in both lists
            common_vouches = find_intersection(&common_vouches, &candidate_vouches);

            // If no common vouches remain, we can exit early
            if (vector::length(&common_vouches) == 0) {
                return vector::empty<address>()
            };

            i = i + 1;
        };

        // Let the sunshine (and let the sun shine on in), let the sun shine in
        // (Open up your heart) the sun shine in (and let it shine on you)
        // (And when you lonely) let the sunshine (hey, let it shine), let the sun shine in
        // (You gotta open up your heart) the sun shine in (and let it shine on in)
        // (And when you feel like you been mistreated)
        // Let the sunshine, let the sun shine in (and your friends turn their backs upon ya)
        // (Just open up your heart) the sun shine in (let it shine on in)
        // (You got to feel it) let the sunshine (you got to feel it), let the sun shine in
        // (Oh, open up your heart) the sun shine in (and let it shine on in)
        common_vouches
    }

    #[view]
    /// Checks if the candidate roots have any common vouches.
    /// Useful for determining if we need to fall back to using candidates directly.
    ///
    /// @param registry - The address where the root of trust registry is stored
    /// @return true if common vouches exist, false otherwise
    public fun has_common_vouches(registry: address): bool {
        let common_roots = get_dynamic_roots(registry);
        vector::length(&common_roots) > 0
    }

    /// Find the intersection of two address vectors (addresses that appear in both)
    ///
    /// @param list1 - First list of addresses
    /// @param list2 - Second list of addresses
    /// @return Vector containing only addresses that appear in both input lists
    fun find_intersection(list1: &vector<address>, list2: &vector<address>): vector<address> {
        let result = vector::empty<address>();

        let i = 0;
        while (i < vector::length(list1)) {
            let addr = *vector::borrow(list1, i);
            if (vector::contains(list2, &addr)) {
                vector::push_back(&mut result, addr);
            };
            i = i + 1;
        };

        result
    }

    #[test_only]
    /// Test helper to verify intersection calculation
    public fun test_find_intersection(list1: vector<address>, list2: vector<address>): vector<address> {
        find_intersection(&list1, &list2)
    }
}
