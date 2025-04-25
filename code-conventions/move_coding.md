
# Common errors
### warning: invalid documentation comment
This is incorrect because the documentation comments should not precede the `#[view]` annotation. It should actually immediately precede the function declaration.

```
    /// Checks if the candidate roots have any common vouches.
    /// Useful for determining if we need to fall back to using candidates directly.
    ///
    /// @param registry - The address where the root of trust registry is stored
    /// @return true if common vouches exist, false otherwise
    #[view]
    public fun has_common_vouches(registry: address): bool {
        let common_roots = get_dynamic_roots(registry);
        vector::length(&common_roots) > 0
    }
```
