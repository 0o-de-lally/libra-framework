# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Libra Framework is a Move language framework for the OpenLibra Network that runs on Diem Platform nodes. It contains the policies for the $LBR asset and OpenLibra Network business logic, including account creation, coin minting, asset transfers, code publishing, validator selection, and more.

**Key Principle**: The project maintains a light-touch approach with upstream dependencies (Diem Platform), optimizing for clean APIs and easy vendor library integration. The framework contains business logic only—no database, consensus, networking, or VM code.

## Repository Structure

This is a Cargo workspace with the following major components:

- **`framework/`**: Move language framework code
  - `libra-framework/`: Core framework with OpenLibra-specific modules in `sources/ol_sources/` (~58 modules)
  - `move-stdlib/`: Move standard library
  - `vendor-stdlib/`: Vendor-provided standard library extensions
  - `cached-packages/`: Build artifacts for faster compilation
  - `releases/`: Framework release bundles (.mrb files)

- **`tools/`**: Rust CLI tools and utilities
  - `cli/`: Main `libra` CLI binary (coordinates all subcommands)
  - `config/`: Configuration management
  - `genesis/`: Genesis creation tools
  - `query/`: Query blockchain state
  - `rescue/`: Recovery and upgrade tools
  - `storage/`: Database operations
  - `testnet/`: Local testnet management (virgin and twin modes)
  - `txs/`: Transaction submission utilities
  - `wallet/`: Wallet and key management

- **`types/`**: Core type definitions shared across the project
- **`smoke-tests/`**: Integration tests using Diem Forge
- **`upgrade-tests/`**: Framework upgrade compatibility tests
- **`compatibility/`**: Backwards compatibility testing

## Build and Test Commands

### Building

```bash
# Build all workspace members
cargo build

# Build release binary (optimized for size and performance)
cargo build --release

# Build the libra CLI specifically
cargo build -p libra

# Build and compile Move framework (using libra CLI)
cd framework
libra move framework release
```

### Testing

**IMPORTANT**: Many tests compile Move code and require increased stack size to avoid overflows. Always use `RUST_MIN_STACK=104857600` for tests involving framework compilation.

```bash
# Run all tests with increased stack and show all failures
RUST_MIN_STACK=104857600 cargo test --no-fail-fast

# Run tests for a specific package
cargo test -p libra-types

# Run smoke tests (requires libra binary)
export DIEM_FORGE_NODE_BIN_PATH=$HOME/.cargo/bin/libra
cd smoke-tests
cargo test --no-fail-fast -- --test-threads=1

# Run Move framework tests
cd framework/libra-framework
libra move test

# Run a single test
cargo test -p libra-txs test_transfer

# Generate upgrade test fixtures (required before upgrade tests)
RUST_MIN_STACK=104857600 cargo test -- make_the_upgrade_fixtures --include-ignored
```

### Development Workflow

```bash
# Format code
cargo fmt

# Lint
cargo clippy

# Check without building
cargo check

# Run specific test module
cargo test -p <package-name> <test-name>
```

## Move Framework Development

### Framework Address Space

All framework code lives at address `0x1`:
- `std` → `0x1` (Move stdlib)
- `diem_framework` → `0x1` (Base framework)
- `ol_framework` → `0x1` (OpenLibra extensions)

### Compiling Move Code

The `libra` CLI provides optimized Move compilation:

```bash
# Compile framework and create release bundle
cd framework
libra move framework release

# This creates head.mrb in framework/releases/
# The .mrb file contains compiled bytecode for deployment
```

### Move Testing

```bash
cd framework/libra-framework
libra move test
```

## Testing Infrastructure

### Testnet Tools

The project provides comprehensive testnet tooling supporting two modes:

**Virgin Mode**: Fresh testnet with new genesis
```bash
libra ops testnet smoke
```

**Twin Mode**: Fork existing mainnet state for realistic testing
```bash
# Restore from epoch backup
libra ops testnet --twin-epoch-restore=344 smoke

# Use existing database
libra ops testnet --twin-reference-db=$HOME/.libra/db_344 smoke
```

### Smoke Tests

Smoke tests use Diem Forge's Swarm framework for integration testing. They require:
1. Built `libra` binary
2. Environment variable: `DIEM_FORGE_NODE_BIN_PATH` pointing to binary
3. Tests run with `--test-threads=1` to avoid race conditions

```bash
export DIEM_FORGE_NODE_BIN_PATH=$HOME/.cargo/bin/libra
cd smoke-tests
cargo test --no-fail-fast -- --test-threads=1
```

## Upgrade Testing

Framework upgrades must maintain backwards compatibility unless explicitly marked as breaking by either:
- Including `[breaking]` in the commit message on main branch
- Using a `breaking/` prefix in the branch name

### Upgrade Test Fixtures

Upgrade tests use pre-generated fixtures in `framework/src/upgrade_fixtures/fixtures/`. If tests fail or fixtures are missing:

```bash
# Delete old fixtures and regenerate
cd framework/src/upgrade_fixtures/fixtures
rm -rf upgrade-*
RUST_MIN_STACK=104857600 cargo test -- make_the_upgrade_fixtures --include-ignored
```

### Running Upgrade Tests

```bash
cd upgrade-tests

# Test upgrade workflow
RUST_MIN_STACK=104857600 cargo test --no-fail-fast -- --skip compatible_ --test-threads=1

# Test backwards compatibility (only if not marked [breaking])
RUST_MIN_STACK=104857600 cargo test compatible_ --no-fail-fast -- --test-threads=1
```

## Architecture Patterns

### Dual-Language Architecture

The project combines:
- **Move**: Framework business logic, policies, on-chain code
- **Rust**: CLI tools, testing infrastructure, integration with Diem Platform

Communication happens through:
- Compiled Move bytecode (.mrb bundles)
- Transaction submission via Diem SDK
- Query interface for reading on-chain state

### Framework Release Process

1. Move code in `framework/libra-framework/sources/`
2. Compile with `libra move framework release`
3. Generates `head.mrb` in `framework/releases/`
4. The .mrb contains all compiled modules for deployment
5. Upgrade tests verify compatibility with previous versions

### Testing Philosophy

- **Smoke tests**: Integration tests with running nodes (Swarm-based)
- **Unit tests**: Standard Rust tests for tools/types
- **Move tests**: Unit tests in .move files
- **Upgrade tests**: Verify framework upgrade compatibility
- **Twin tests**: Production-identical state testing

### OpenLibra-Specific Modules

The `framework/libra-framework/sources/ol_sources/` directory contains ~58 OpenLibra-specific Move modules implementing network policies:

- Account lifecycle (ancestry, activity)
- Economics (burn, fee_maker, gas, inflation)
- Governance (donor_voice, vouching, proof_of_fee)
- Community features (community_wallet, match_index)
- Validator management (jail, grade, stake)
- And more...

These modules extend the base Diem framework with OpenLibra's specific economic and governance policies.

## CI/CD Notes

GitHub Actions workflows test:
- Framework compilation (builds Move framework first, creates artifact)
- Rust tests for each workspace member (types, wallet, query, genesis, txs, rescue, storage, testnet)
- Smoke tests with testnet
- Move framework tests (separate workflow in `.github/workflows/move.yaml`)
- Upgrade compatibility (skipped if `[breaking]` in main's last commit or `breaking/` in branch name)

All Rust test jobs depend on a successful framework build artifact to ensure consistent compiled Move code across test jobs. Tests that compile Move code use `RUST_MIN_STACK=104857600` and `--test-threads=1`.

## Common Patterns

### When working with Move code:
- Always rebuild framework after changes: `libra move framework release`
- Move tests don't need RUST_MIN_STACK, only Rust tests compiling Move
- Framework address is always `0x1`

### When running tests:
- Use `RUST_MIN_STACK=104857600` for tests compiling Move code
- Use `--test-threads=1` for integration tests (smoke, testnet)
- Use `--no-fail-fast` to see all test failures

### When testing upgrades:
- Ensure fixtures exist first
- Main branch compatibility is required unless marked `[breaking]`
- Check that `framework/releases/head.mrb` is current
