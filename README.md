# Escalation (ESCL): DollarAuction

**This is a Sepolia test toy with no real value. Bidding past the prize loses ESCL by design.**
The highest bidder gets the prize, but both the highest and second-highest bidders pay their bids to the seller.
Every other bidder can reclaim their full standing bid after settlement.

This contribution delivers the contracts, Foundry tests, vendored dependencies, ABI exports, and a deployment/integration handoff. The separate manifest assignment produces `launch.json`; an independent contributor reviews accepted source and manifest before the services publish, attest, admit and deploy. The frontend stage follows the live deployment. This repository does not claim a deployment or completed independent review.

## Build and check

Solidity is pinned to **0.8.26** in [foundry.toml](foundry.toml), with optimizer runs 200, Cancun EVM, and `bytecode_hash = "none"`. Foundry and that compiler must be installed in the checking environment. All Solidity dependencies are ordinary files under `lib/`; there are no submodules or install-time downloads. FFI and Foundry filesystem permissions are disabled.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

After changing a public interface, run `forge build` and `python3 scripts/export_abis.py` to regenerate the committed ABI JSON files. The script uses only Python's standard library and local build artifacts. See [dependency provenance](docs/DEPENDENCIES.md).

Tests have no environment-variable, RPC, wallet, or external-service dependency. Each test creates its own state. Coverage includes exact minimum increments, returning bidders from second and lower ranks, deadline ordering, invalid and duplicate actions, no/one/many-bidder settlements, isolated concurrent auctions, transfer failures, pull withdrawals, and hostile-token callback reentrancy. A factory fixture checks constructor supply preservation, runtime size, and forbidden opcodes.

The gas test compares identical final top-two states with 2 and 200 distinct bidders and requires **exactly equal** settlement gas. The stateful invariant uses eight funded actors across up to twelve auctions, with 128 runs of depth 96. An independent model recomputes ranks by scanning all actors and checks both credits and escrow liabilities after random actions; it drains all obligations at the end of each run. These tests are local evidence, not a security audit.

## Contracts and deployment parameters

| Artifact | Constructor arguments | Purpose |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None | Escalation / ESCL; 18 decimals; exactly `1000000000000000000000000000` minor units minted once to the constructor caller |
| `src/DollarAuction.sol:DollarAuction` | One `address token_`, resolved as `$token` | Immutable ESCL currency; fully operational at construction with zero initial balance |

Use the project factory on **Sepolia, chain ID 11155111**, with the token deployed before `DollarAuction`. The application identifier is `DollarAuction`, and its manifest `constructorArgs` must be `["$token"]`. Both constructors are nonpayable. Constructor execution must leave all launch supply with the factory. No initializer, app prefunding, owner argument, or follow-up administrative call is needed. The token has no external mint, burn, fee, pause, blocklist, ownership, or upgrade function; neither contract has an owner or upgrade mechanism.

The application only checks that `token_` has code. Services and the manifest reviewer must bind it to this exact LaunchToken; an arbitrary ERC-20 is not an approved deployment. In particular, accounting assumes 18 decimals and exact, non-rebasing, fee-free transfers. `SafeERC20` handles false/reverting/empty-return token calls but does not make arbitrary tokens economically safe. The contracts themselves have no chain-ID gate; deployment services and the frontend must restrict use to Sepolia.

Policy, signed-artifact linkage, pool configuration, reward allocation, and concrete deployed addresses are service/manifest responsibilities. They are not inferred from a constructor caller or hard-coded privileged wallet. Services should confirm the immutable `token()`, supply/decimals, deployment block, and verified source/ABI before starting the frontend. There is no deploy script that reads keys or broadcasts transactions.

## Rules, timing, and funds

All amounts are ESCL minor units: `1 ESCL = 10^18`. Solidity's `ether` literal in the contracts expresses this scale, never an ETH payment.

1. A seller approves DollarAuction to spend a prize of at least 100 ESCL and calls `open(prize)`. The prize is escrowed, and the returned auction ID starts at zero. `lastActivity` is the block timestamp.
2. Before the deadline, an address other than the seller or current highest bidder approves and calls `bid(id, newTotal)`. The new total must exceed the highest by at least 1 ESCL; the first bid is at least 1 ESCL. Fractional ESCL amounts are allowed subject to this increment. Only `newTotal - bidOf(id, caller)` is pulled. Each accepted bid resets the deadline to that block's timestamp plus one hour. A returning bidder updates their one standing bid.
3. At or after `deadline(id)`, anyone calls `settle(id)` once. Bidding at the exact deadline fails. A bid mined one second before the old deadline extends it, so settlement at the old deadline fails. Ordering uses the actual block timestamp, not the time a wallet submits a transaction.
4. With bids, settlement credits the prize to the winner and the sum of the top two standing bids to the seller (only the highest if there is one bidder). With no bids, the prize is credited back to the seller. Settlement performs no token transfers, bidder loops, or calls to recipients.
5. Each bidder outside the final top two calls `reclaim(id)` once after settlement. This clears their bid and moves the full amount to their withdrawable credit. The final top two cannot reclaim; their bids were allocated to the seller. There is no early exit, cancellation, or refund for those two participants.
6. A recipient calls `withdraw()` to collect their entire accumulated credit, across auctions, to their own address. Credits are cleared before the safe transfer, and every state-changing application entry point is `nonReentrant`. A failed transfer reverts atomically, preserving the credit for retry. One recipient's withdrawal failure cannot block settlement or another recipient's withdrawal.

Prizes, bids, and credits have no expiry. A third party may settle but cannot reclaim or withdraw on behalf of a recipient. Contract wallets must be able to make those calls themselves. There are no protocol fees, sweep/recovery functions, external oracles, random selection, or keepers. Players or any third party must submit settlement transactions; inactivity alone does not execute settlement. Sustained bidding can extend an auction indefinitely. Sellers escrow their prize until settlement, and even a winning bidder can lose ESCL by overbidding. Separate wallets controlled by one person cannot be distinguished by this game.

For funds received through the application's entry points, the invariant is:

```text
ESCL held = prizes and all standing bids in unsettled auctions
          + unreclaimed bids outside the final top two in settled auctions
          + all withdrawable credits
```

After settlement the final top-two `bidOf` values remain for historical display, but are no longer independent liabilities. Other bidders' values become zero on reclaim. Plain ERC-20 transfers to DollarAuction create uncredited, unrecoverable surplus; send ESCL only through approved `open` or `bid` calls. The equality assumes no unsolicited transfers. There is no payable method or receive/fallback, so ordinary ETH transfers fail. EVM-forced ETH can still arrive and has no recovery path; ETH is never used by the game.

## ABI and frontend handoff

Committed exports: [LaunchToken ABI](docs/abi/LaunchToken.json), [DollarAuction ABI](docs/abi/DollarAuction.json). [ABI documentation](docs/ABI.md) defines return values, events, errors, and approval amounts.

The later `lab-dollar-auction` page should use the two-sentence explanation above and prominently retain the no-value/overbidding warning. Read the currency address from `DollarAuction.token()`. Players obtain ESCL by swapping Sepolia ETH in the launch pool; no in-page swap is required. Show connected-wallet balance, allowance, and withdrawable credit. Before every paying action, show an Approve step for the prize or top-up amount, wait for confirmation, and refresh the highest bid and deadline before sending the action. A bid can become stale while approval confirms.

Use `auctionCount()`, IDs `0..count-1`, `auction(id)`, `topTwo(id)`, and `deadline(id)` to show prizes, top bids, and countdowns; retrieve IDs in bounded client batches. Use contract events through RPC for updates and refresh views after transactions/reorganizations. No backend or indexer is needed. Include bid, settle, reclaim, and withdraw controls; withdrawals always require the recipient's transaction. The service must provide the live app address and deployment block, enforce Sepolia in the wallet UI, and produce a static export with `dist/index.html` before approved publication/hosting.

## Independent review handoff

The independent reviewer must inspect the accepted source together with the generated manifest and constructor arguments. In addition to factory/token binding, attack second-highest accounting after repeated top-ups, attempted refund of bids already credited to a seller, both deadline transaction orderings, and withdraw reentrancy. [Review evidence](docs/REVIEW-HANDOFF.md) maps these attacks to reproducible tests and states remaining assumptions. Tests here are authored as part of implementation, not an independent review approval.
