// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Shubik's dollar auction in ESCL. Both highest bidders pay; only the winner receives the prize.
/// @dev Intended solely for the fixed-supply LaunchToken. No owner, fees, initial funding or ETH entry points.
contract DollarAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_PRIZE = 100 ether;
    uint256 public constant MIN_INCREMENT = 1 ether;
    uint256 public constant INACTIVITY_PERIOD = 1 hours;

    IERC20 public immutable token;
    uint256 public auctionCount;

    struct Auction {
        address seller;
        uint256 prize;
        uint256 lastActivity;
        address highestBidder;
        address secondBidder;
        bool settled;
    }

    mapping(uint256 id => Auction) private _auctions;
    // Losing bids are cleared on reclaim. The final top two bids remain as historical data.
    mapping(uint256 id => mapping(address bidder => uint256 amount)) public bidOf;
    mapping(address recipient => uint256 amount) public withdrawable;

    error InvalidToken();
    error UnknownAuction(uint256 id);
    error PrizeTooSmall();
    error AuctionSettled();
    error AuctionStillActive();
    error BiddingClosed();
    error SellerCannotBid();
    error AlreadyHighestBidder();
    error BidTooSmall();
    error AuctionNotSettled();
    error TopBidderCannotReclaim();
    error NothingToReclaim();
    error NothingToWithdraw();

    event Opened(uint256 indexed id, address indexed seller, uint256 prize, uint256 lastActivity);
    event Bid(uint256 indexed id, address indexed bidder, uint256 total, uint256 lastActivity);
    event Settled(uint256 indexed id, address indexed winner, uint256 prize, uint256 sellerTake);
    event Reclaimed(uint256 indexed id, address indexed bidder, uint256 amount);
    event Withdrawn(address indexed recipient, uint256 amount);

    /// @param token_ The already-deployed ESCL LaunchToken ($token in the launch manifest).
    constructor(address token_) {
        if (token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
    }

    /// @notice Escrow a prize and open an auction. IDs start at zero.
    function open(uint256 prize) external nonReentrant returns (uint256 id) {
        if (prize < MIN_PRIZE) revert PrizeTooSmall();
        id = auctionCount++;
        _auctions[id] = Auction(msg.sender, prize, block.timestamp, address(0), address(0), false);
        token.safeTransferFrom(msg.sender, address(this), prize);
        emit Opened(id, msg.sender, prize, block.timestamp);
    }

    /// @notice Become highest bidder by topping up your single standing bid to newTotal.
    function bid(uint256 id, uint256 newTotal) external nonReentrant {
        Auction storage a = _getAuction(id);
        if (a.settled) revert AuctionSettled();
        if (block.timestamp >= a.lastActivity + INACTIVITY_PERIOD) revert BiddingClosed();
        if (msg.sender == a.seller) revert SellerCannotBid();
        if (msg.sender == a.highestBidder) revert AlreadyHighestBidder();
        uint256 highest = bidOf[id][a.highestBidder];
        if (newTotal < highest + MIN_INCREMENT) revert BidTooSmall();

        uint256 payment = newTotal - bidOf[id][msg.sender];
        bidOf[id][msg.sender] = newTotal;
        // Every accepted bid exceeds all existing bids. The old highest is now second,
        // even when the new highest was previously second or a lower-ranked bidder.
        a.secondBidder = a.highestBidder;
        a.highestBidder = msg.sender;
        a.lastActivity = block.timestamp;
        token.safeTransferFrom(msg.sender, address(this), payment);
        emit Bid(id, msg.sender, newTotal, block.timestamp);
    }

    /// @notice Finalize after one hour of inactivity. Credits only; no external calls or bidder iteration.
    function settle(uint256 id) external nonReentrant {
        Auction storage a = _getAuction(id);
        if (a.settled) revert AuctionSettled();
        if (block.timestamp < a.lastActivity + INACTIVITY_PERIOD) revert AuctionStillActive();
        a.settled = true;

        address winner = a.highestBidder;
        uint256 sellerTake = 0;
        if (winner == address(0)) {
            withdrawable[a.seller] += a.prize;
        } else {
            sellerTake = bidOf[id][winner] + bidOf[id][a.secondBidder];
            withdrawable[winner] += a.prize;
            withdrawable[a.seller] += sellerTake;
        }
        emit Settled(id, winner, a.prize, sellerTake);
    }

    /// @notice Move a settled losing bid into the caller's withdrawable balance exactly once.
    function reclaim(uint256 id) external nonReentrant {
        Auction storage a = _getAuction(id);
        if (!a.settled) revert AuctionNotSettled();
        if (msg.sender == a.highestBidder || msg.sender == a.secondBidder) revert TopBidderCannotReclaim();
        uint256 amount = bidOf[id][msg.sender];
        if (amount == 0) revert NothingToReclaim();
        bidOf[id][msg.sender] = 0;
        withdrawable[msg.sender] += amount;
        emit Reclaimed(id, msg.sender, amount);
    }

    /// @notice Collect all of the caller's credits. Failed transfers restore the entire credit.
    function withdraw() external nonReentrant {
        uint256 amount = withdrawable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        withdrawable[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function auction(uint256 id) external view returns (Auction memory) {
        return _getAuction(id);
    }

    function topTwo(uint256 id)
        external
        view
        returns (address highestBidder, uint256 highestBid, address secondBidder, uint256 secondBid)
    {
        Auction storage a = _getAuction(id);
        return (a.highestBidder, bidOf[id][a.highestBidder], a.secondBidder, bidOf[id][a.secondBidder]);
    }

    function deadline(uint256 id) external view returns (uint256) {
        return _getAuction(id).lastActivity + INACTIVITY_PERIOD;
    }

    function _getAuction(uint256 id) private view returns (Auction storage a) {
        if (id >= auctionCount) revert UnknownAuction(id);
        a = _auctions[id];
    }
}
