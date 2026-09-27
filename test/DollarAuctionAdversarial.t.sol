// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DollarAuction} from "../src/DollarAuction.sol";

interface TokenReceiver {
    function onTokens() external;
}

/// @dev Only a test double. Production ESCL has no hooks, mint entry point or transfer switches.
contract HostileToken is ERC20 {
    bool public failIn;
    bool public omitReturn;
    bool public callbackIn;
    bool public callbackOut;
    address public blockedRecipient;

    constructor() ERC20("Test double", "TEST") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function configure(bool failIn_, bool omitReturn_, bool callbackIn_, bool callbackOut_, address blockedRecipient_)
        external
    {
        failIn = failIn_;
        omitReturn = omitReturn_;
        callbackIn = callbackIn_;
        callbackOut = callbackOut_;
        blockedRecipient = blockedRecipient_;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (failIn) return false;
        super.transferFrom(from, to, amount);
        if (callbackIn) TokenReceiver(from).onTokens();
        if (omitReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == blockedRecipient) return false;
        super.transfer(to, amount);
        if (callbackOut) TokenReceiver(to).onTokens();
        if (omitReturn) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }
}

contract CallbackBidder is TokenReceiver {
    DollarAuction public immutable game;
    uint256 public seenCredit;
    bool public reentered;
    bytes public reentryError;
    bool public rejectHook;

    error HookRejected();

    constructor(DollarAuction game_) {
        game = game_;
        game_.token().approve(address(game_), type(uint256).max);
    }

    function bid(uint256 id, uint256 amount) external {
        game.bid(id, amount);
    }

    function withdraw() external {
        game.withdraw();
    }

    function setRejectHook(bool reject_) external {
        rejectHook = reject_;
    }

    function onTokens() external {
        require(msg.sender == address(game.token()), "only test token");
        seenCredit = game.withdrawable(address(this));
        (reentered, reentryError) = address(game).call(abi.encodeCall(game.withdraw, ()));
        if (rejectHook) revert HookRejected();
    }
}

contract DollarAuctionAdversarialTest is Test {
    HostileToken internal token;
    DollarAuction internal game;
    CallbackBidder internal bidder;
    address internal constant OTHER = address(0xC0FFEE);

    function setUp() public {
        token = new HostileToken();
        game = new DollarAuction(address(token));
        bidder = new CallbackBidder(game);
        token.approve(address(game), type(uint256).max);
        token.transfer(address(bidder), 1000 ether);
        token.transfer(OTHER, 1000 ether);
        vm.prank(OTHER);
        token.approve(address(game), type(uint256).max);
    }

    function _winningCredit() private {
        game.open(100 ether);
        bidder.bid(0, 1 ether);
        vm.warp(game.deadline(0));
        game.settle(0);
    }

    function test_falseTransferFromRollsBackOpenAndBid() public {
        token.configure(true, false, false, false, address(0));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        game.open(100 ether);
        assertEq(game.auctionCount(), 0);
        token.configure(false, false, false, false, address(0));
        game.open(100 ether);
        token.configure(true, false, false, false, address(0));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        bidder.bid(0, 1 ether);
        assertEq(game.bidOf(0, address(bidder)), 0);
        assertEq(game.auction(0).highestBidder, address(0));
        assertEq(token.balanceOf(address(game)), 100 ether);
    }

    function test_optionalReturnTokenStillUsesSafeTransfers() public {
        token.configure(false, true, false, false, address(0));
        _winningCredit();
        bidder.withdraw();
        game.withdraw();
        assertEq(token.balanceOf(address(bidder)), 1099 ether);
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_failedRecipientDoesNotBlockSettleOrOtherWithdrawalsAndCanRetry() public {
        game.open(100 ether);
        bidder.bid(0, 1 ether);
        token.configure(false, false, false, false, address(bidder));
        vm.warp(game.deadline(0));
        game.settle(0); // Settlement cannot fail because of a token transfer.
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token)));
        bidder.withdraw();
        assertEq(game.withdrawable(address(bidder)), 100 ether);
        assertEq(token.balanceOf(address(game)), 101 ether);
        game.withdraw(); // Seller can collect independently.
        assertEq(token.balanceOf(address(game)), 100 ether);
        token.configure(false, false, false, false, address(0));
        bidder.withdraw();
        assertEq(game.withdrawable(address(bidder)), 0);
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_withdrawReentrancySeesZeroCreditAndCannotDrainTwice() public {
        _winningCredit();
        token.configure(false, false, false, true, address(0));
        bidder.withdraw();
        assertEq(bidder.seenCredit(), 0);
        assertFalse(bidder.reentered());
        assertEq(bidder.reentryError(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(game.withdrawable(address(bidder)), 0);
        assertEq(token.balanceOf(address(bidder)), 1099 ether);
        assertEq(token.balanceOf(address(game)), 1 ether);
    }

    function test_revertingCallbackRestoresCreditAndUnlocksGuard() public {
        _winningCredit();
        token.configure(false, false, false, true, address(0));
        bidder.setRejectHook(true);
        vm.expectRevert(CallbackBidder.HookRejected.selector);
        bidder.withdraw();
        assertEq(game.withdrawable(address(bidder)), 100 ether);
        assertEq(token.balanceOf(address(bidder)), 999 ether);
        assertEq(token.balanceOf(address(game)), 101 ether);
        bidder.setRejectHook(false);
        bidder.withdraw();
        assertEq(token.balanceOf(address(bidder)), 1099 ether);
    }

    function test_bidTransferCallbackCannotWithdrawExistingCredit() public {
        _winningCredit();
        uint256 id = game.open(100 ether);
        token.configure(false, false, true, false, address(0));
        bidder.bid(id, 1 ether);
        assertFalse(bidder.reentered());
        assertEq(bidder.seenCredit(), 100 ether);
        assertEq(bidder.reentryError(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(game.withdrawable(address(bidder)), 100 ether);
        token.configure(false, false, false, false, address(0));
        bidder.withdraw();
        assertEq(token.balanceOf(address(game)), 102 ether);
    }
}
