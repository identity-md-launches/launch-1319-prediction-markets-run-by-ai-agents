# VERDICT

`VerdictToken` is the fixed-supply ERC-20 for **Prediction Markets Run by AI Agents**.
The deliverable is the token contract; the name does not imply a prediction market,
oracle, agent system, or governance implementation.

## Token parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `VerdictToken` |
| Source | `src/VerdictToken.sol` |
| Name | `Prediction Markets Run by AI Agents` |
| Symbol | `VERDICT` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (10^27) |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial recipient | Immediate deploying account (`msg.sender`) |

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. An IdentityMD factory deployment
therefore gives the factory the whole supply. Neither the transaction origin nor
the account calling the factory receives tokens during construction.

## Behavior and assumptions

The contract inherits the unmodified OpenZeppelin Contracts v5.0.2 ERC-20. There
are no public mint/burn functions, transfer taxes, rebases, transfer restrictions,
owner roles, pause controls, blacklists, upgrades, or initialization calls. Total
supply remains constant after construction. Every successful transfer credits
exactly the requested amount, including transfers to and from the factory,
distributor, and pool manager. These addresses need no exemptions or configuration.

Standard `transfer`, `approve`, and `transferFrom` return `true` on success and
revert with ERC-6093 custom errors on failure. Zero-value transfers between nonzero
addresses are allowed and emit `Transfer`; self-transfers preserve balances.
Transfers to the zero address and approvals to the zero address revert.

Approvals replace the previous allowance. Finite allowances decrease when spent;
`type(uint256).max` represents an unlimited allowance and does not decrease.
`approve` emits `Approval`; this OpenZeppelin version does not emit a new
`Approval` event when `transferFrom` consumes an allowance. Indexers should query
`allowance` for its current value. A failed transfer rolls back all balance and
allowance changes. Even the deployer needs an allowance to spend another holder's
tokens. Holders should grant only the allowances they need and revoke unused
ones. When replacing a live allowance, consider revoking it first and waiting for
confirmation to reduce the standard ERC-20 allowance replacement race.

All amounts in contract calls are base units: one VERDICT is `10^18` units. There
are no external calls in token operations, callbacks to recipients, oracle data,
randomness, signature handling, or time-dependent behavior. The contract does not
accept ordinary ETH payments. It has no asset recovery function; tokens sent to
the token contract itself, or assets sent to an incompatible recipient, may be
unrecoverable.

## Build and checks

Install Foundry and Solidity **0.8.26**, then run from this repository root:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licences are vendored in `lib/`; no network,
submodules, RPC endpoint, wallet, or environment variables are required by the
tests. See `DEPENDENCIES.md` for source versions and checksums. With the compiler
already installed, `forge build --offline` and `forge test --offline` also work.
The configuration pins the Cancun EVM, enables optimization with 200 runs, and
sets `bytecode_hash = "none"`. It grants no FFI or filesystem permissions.

Tests cover exact metadata and constructor minting, CREATE/CREATE2 factory
deployment, mint events, transfer/approval events, full and zero transfers,
self-transfers, finite and unlimited allowances, revocation, unauthorized
spending, invalid recipients, overdraws, rollback on failed delegated transfers,
absent administrative entry points, runtime opcode restrictions, and undiminished
launch distribution transfers. Five fuzz tests run 512 cases each. A stateful
invariant checks supply and balance conservation across 128 sequences of 64
transfers, approvals, and delegated transfers.

The local launch-flow test checks ERC-20 movements through labelled test accounts;
it does not execute Uniswap v4 liquidity or swaps. The supplied protected harness
is a separate launch integration test that requires the network's factory code,
pool infrastructure, resolved deployment bytecode, and manifest settings. Those
are supplied by the launch verifier, not invented by these unit tests.

## Deployment and launch responsibilities

Deploy the creation bytecode built for `src/VerdictToken.sol:VerdictToken` with no
constructor arguments, no attached ETH, and no linked libraries. The artifact is
`out/VerdictToken.sol/VerdictToken.json`. There are no constructor calls to external
contracts, so deployment works on an otherwise empty chain. The intended launch
chain is Ethereum (chain ID 1). No script in this project broadcasts transactions
or handles a wallet key.

The separate IdentityMD launch/manifest step selects the actual deployment
factory and records `VerdictToken`, its exact metadata, empty constructor arguments,
and base-unit supply. This project does not create `launch.json` or application
contracts. The factory is responsible for distributing the supply after deployment:

- 10% (`100,000,000` VERDICT) to the launch's MerkleDistributor.
- 80% (`800,000,000` VERDICT) for pool seeding.
- The remaining 10% (`100,000,000` VERDICT) to
  `0x6bf192ebef135e0f645e99d59d9bf44e7711606c`.

The supplied launch policy uses IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` as paired currency, fee `12500`
(1.25%), and tick spacing `60`. Its economics are `poolBps = 8000` and
`initialMarketCapWei = 2500000000000000000000` in IMD base units. The policy's
provenance price is `79228162514264337593543950336`; the factory derives the actual
opening price from the market cap, supply, and token ordering. These launch values
belong to the manifest and factory; they are not token constructor parameters or
on-chain settings in this contract.

## After launch

No owner settings, role transfers, initialization, keepers, or scheduled operations
are needed. The launch operator must verify the deployed source and compiler
settings, confirm the metadata and supply, and check distribution and liquidity
receipts. Holders control their own balances and allowances. There is no
administrator capable of recovering a mistaken transfer, freezing a holder, or
changing the token's code or supply.

The implementation and its reachable ERC-20 code were reviewed against the pinned
security reference. Foundry unit, fuzz, and invariant checks are local validation;
Slither and Mythril were not run. Independent adversarial review and deployment
verification remain the release operator's responsibilities.
