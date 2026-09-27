# ABI reference

Exports are JSON ABI arrays generated from Solidity 0.8.26 artifacts by `scripts/export_abis.py`:

- [LaunchToken.json](abi/LaunchToken.json)
- [DollarAuction.json](abi/DollarAuction.json)

All writes are nonpayable. All amounts are unsigned 256-bit ESCL minor units (18 decimals). Timestamps are Unix seconds. All auction IDs are unsigned 256-bit values starting at zero. The contract does not return entire bidder arrays or all auctions in one call.

## LaunchToken

Constructor: `constructor()`. Name: `Escalation`; symbol: `ESCL`; decimals: `18`; fixed total supply: `10^27`. Supply is minted to `msg.sender` during construction only.

Standard ERC-20 views: `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)`, and `allowance(address,address)`.

Standard writes: `approve(address spender,uint256 amount)`, `transfer(address to,uint256 amount)`, and `transferFrom(address from,address to,uint256 amount)` return `bool`. Successful token calls return true; insufficient allowance/balance and invalid zero-address transfers revert with ERC-6093 errors included in the ABI. Max-uint allowance is not decremented. There is no permit interface.

Events: standard `Transfer(address indexed from,address indexed to,uint256 value)` and `Approval(address indexed owner,address indexed spender,uint256 value)`. Refresh allowance using its view after spending; transferFrom does not emit a new Approval event.

## DollarAuction

Constructor: `constructor(address token_)`. `token_` must have deployed code, and the reviewed manifest must resolve it to `$token` (LaunchToken). No deployment funds or initialization are required.

| Write | Return | Caller and preconditions | ESCL flow |
| --- | --- | --- | --- |
| `open(uint256 prize)` | `uint256 id` | Any caller; prize >= `100e18` | Pulls prize from caller |
| `bid(uint256 id,uint256 newTotal)` | None | Known, active auction before deadline; caller neither seller nor highest; total >= highest + `1e18` | Pulls newTotal minus caller's standing bid |
| `settle(uint256 id)` | None | Anyone; known, unsettled auction at/after deadline | Credits only, no transfer |
| `reclaim(uint256 id)` | None | Settled; caller outside top two with a nonzero standing bid | Moves standing bid into credit |
| `withdraw()` | None | Caller has nonzero credit | Transfers entire credit to caller |

Before `open`, approve the prize to DollarAuction. Before `bid`, approve only the top-up amount, computed from current `bidOf`. Allowance belongs to the auction contract, not the seller. ETH must not accompany any call. Reclaim and withdrawal are distinct actions and require no allowance. No user can direct a payout to another address.

| View | Return |
| --- | --- |
| `token()` | `address`: immutable currency |
| `auctionCount()` | `uint256`: number of auctions opened |
| `auction(uint256 id)` | `Auction` tuple, in order: `(address seller,uint256 prize,uint256 lastActivity,address highestBidder,address secondBidder,bool settled)` |
| `bidOf(uint256 id,address bidder)` | `uint256`: standing bid; losing bids clear on reclaim; final top-two values remain historical after settlement |
| `topTwo(uint256 id)` | `(address highestBidder,uint256 highestBid,address secondBidder,uint256 secondBid)` |
| `deadline(uint256 id)` | `uint256`: lastActivity + 3600; retained after settlement |
| `withdrawable(address recipient)` | `uint256`: total credit across auctions |
| `MIN_PRIZE()` | `uint256`: `100e18` |
| `MIN_INCREMENT()` | `uint256`: `1e18` |
| `INACTIVITY_PERIOD()` | `uint256`: `3600` |

`auction`, `topTwo`, and `deadline` reject nonexistent IDs with `UnknownAuction(id)`. `bidOf` is a raw mapping getter, returning zero for missing IDs/bidders. Absent top bidders are represented as zero address with zero amount. `highestBidder` is the winner once settled. Settled state is authoritative; the historical deadline alone does not indicate settlement.

| Event | Meaning |
| --- | --- |
| `Opened(uint256 indexed id,address indexed seller,uint256 prize,uint256 lastActivity)` | Escrowed prize; starts countdown |
| `Bid(uint256 indexed id,address indexed bidder,uint256 total,uint256 lastActivity)` | New standing total, not amount pulled; restarts countdown |
| `Settled(uint256 indexed id,address indexed winner,uint256 prize,uint256 sellerTake)` | Credits created. No bids: winner is zero, prize goes to seller, sellerTake is zero. Otherwise sellerTake is top-two sum |
| `Reclaimed(uint256 indexed id,address indexed bidder,uint256 amount)` | Losing bid converted to credit |
| `Withdrawn(address indexed recipient,uint256 amount)` | Credit paid successfully |

`Opened` and `Bid` timestamps come from the accepting block. For display, use a chain-derived timestamp and refresh after a new block; do not assume a local countdown decides transaction validity. Events do not include a separate approval step or represent token prices.

Application errors: `InvalidToken`, `UnknownAuction(uint256)`, `PrizeTooSmall`, `AuctionSettled`, `AuctionStillActive`, `BiddingClosed`, `SellerCannotBid`, `AlreadyHighestBidder`, `BidTooSmall`, `AuctionNotSettled`, `TopBidderCannotReclaim`, `NothingToReclaim`, and `NothingToWithdraw`. No-argument names denote zero-argument custom errors. Inherited/library errors include `ReentrancyGuardReentrantCall`, `SafeERC20FailedOperation(address)`, `AddressEmptyCode(address)`, and `FailedInnerCall`. Token revert data, including ERC-20 allowance/balance errors, can bubble through unchanged; decode using both ABIs.
