// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {DollarAuction} from "../src/DollarAuction.sol";

contract DollarAuctionTest is Test {
    LaunchToken internal token;
    DollarAuction internal game;
    address internal constant SELLER = address(0x5E11);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    uint256 internal constant FUNDING = 1_000_000 ether;

    function setUp() public {
        vm.warp(1_000_000);
        token = new LaunchToken();
        game = new DollarAuction(address(token));
        _fund(SELLER);
        _fund(ALICE);
        _fund(BOB);
        _fund(CAROL);
    }

    function _fund(address user) internal {
        token.transfer(user, FUNDING);
        vm.prank(user);
        token.approve(address(game), type(uint256).max);
    }

    function _open(uint256 prize) internal returns (uint256 id) {
        vm.prank(SELLER);
        return game.open(prize);
    }

    function _bid(uint256 id, address user, uint256 amount) internal {
        vm.prank(user);
        game.bid(id, amount);
    }

    function _settle(uint256 id) internal {
        vm.warp(game.deadline(id));
        game.settle(id);
    }

    function _assertTop(uint256 id, address first, uint256 firstBid, address second, uint256 secondBid) internal view {
        (address h, uint256 hb, address s, uint256 sb) = game.topTwo(id);
        assertEq(h, first);
        assertEq(hb, firstBid);
        assertEq(s, second);
        assertEq(sb, secondBid);
    }

    function test_constructorAndEmptyDeployment() public {
        assertEq(address(game.token()), address(token));
        assertEq(token.balanceOf(address(game)), 0);
        assertEq(game.auctionCount(), 0);
        vm.expectRevert(DollarAuction.InvalidToken.selector);
        new DollarAuction(address(0));
        vm.expectRevert(DollarAuction.InvalidToken.selector);
        new DollarAuction(ALICE);
    }

    function test_openPullsMinimumPrizeAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(game));
        emit DollarAuction.Opened(0, SELLER, 100 ether, block.timestamp);
        uint256 id = _open(100 ether);
        assertEq(id, 0);
        assertEq(game.auctionCount(), 1);
        assertEq(token.balanceOf(address(game)), 100 ether);
        assertEq(token.balanceOf(SELLER), FUNDING - 100 ether);
        DollarAuction.Auction memory a = game.auction(id);
        assertEq(a.seller, SELLER);
        assertEq(a.prize, 100 ether);
        assertEq(a.lastActivity, block.timestamp);
        assertFalse(a.settled);
        assertEq(game.deadline(id), block.timestamp + 1 hours);
        _assertTop(id, address(0), 0, address(0), 0);
    }

    function test_rejectsSmallPrizeAndUnapprovedOpenAtomically() public {
        vm.expectRevert(DollarAuction.PrizeTooSmall.selector);
        _open(100 ether - 1);
        vm.prank(SELLER);
        token.approve(address(game), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(game), 0, 100 ether)
        );
        _open(100 ether);
        assertEq(game.auctionCount(), 0);
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_enforcesOneEsclIncrementIncludingFirstBidAndTies() public {
        uint256 id = _open(100 ether);
        vm.expectRevert(DollarAuction.BidTooSmall.selector);
        _bid(id, ALICE, 1 ether - 1);
        _bid(id, ALICE, 1 ether);
        vm.expectRevert(DollarAuction.BidTooSmall.selector);
        _bid(id, BOB, 1 ether);
        vm.expectRevert(DollarAuction.BidTooSmall.selector);
        _bid(id, BOB, 2 ether - 1);
        _bid(id, BOB, 2 ether);
        _assertTop(id, BOB, 2 ether, ALICE, 1 ether);
    }

    function test_sellerAndCurrentHighestCannotBid() public {
        uint256 id = _open(100 ether);
        vm.expectRevert(DollarAuction.SellerCannotBid.selector);
        _bid(id, SELLER, 1 ether);
        _bid(id, ALICE, 1 ether);
        vm.expectRevert(DollarAuction.AlreadyHighestBidder.selector);
        _bid(id, ALICE, 100 ether);
        assertEq(game.bidOf(id, ALICE), 1 ether);
    }

    function test_topUpsPreserveDistinctSecondHighestAndOnlyPullDifference() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 10 ether);
        _bid(id, BOB, 20 ether);
        vm.prank(ALICE);
        token.approve(address(game), 20 ether);
        _bid(id, ALICE, 30 ether);
        assertEq(token.allowance(ALICE, address(game)), 0);
        assertEq(token.balanceOf(ALICE), FUNDING - 30 ether);
        _assertTop(id, ALICE, 30 ether, BOB, 20 ether);
        _bid(id, CAROL, 40 ether);
        _bid(id, BOB, 50 ether);
        vm.prank(ALICE);
        token.approve(address(game), 30 ether);
        _bid(id, ALICE, 60 ether);
        _assertTop(id, ALICE, 60 ether, BOB, 50 ether);
        assertEq(token.balanceOf(address(game)), 250 ether);
        _settle(id);
        assertEq(game.withdrawable(SELLER), 110 ether);
        assertEq(game.withdrawable(ALICE), 100 ether);
        vm.prank(CAROL);
        game.reclaim(id);
        assertEq(game.withdrawable(CAROL), 40 ether);
        assertEq(game.bidOf(id, CAROL), 0);
        vm.prank(BOB);
        vm.expectRevert(DollarAuction.TopBidderCannotReclaim.selector);
        game.reclaim(id);
        // Every escrowed token is owed exactly once.
        assertEq(
            token.balanceOf(address(game)),
            game.withdrawable(SELLER) + game.withdrawable(ALICE) + game.withdrawable(CAROL)
        );
    }

    function test_bidEmitsAndExtendsDeadline() public {
        uint256 id = _open(100 ether);
        uint256 bidTime = vm.getBlockTimestamp() + 123;
        vm.warp(bidTime);
        vm.expectEmit(true, true, false, true, address(game));
        emit DollarAuction.Bid(id, ALICE, 1 ether, bidTime);
        _bid(id, ALICE, 1 ether);
        assertEq(game.auction(id).lastActivity, bidTime);
        assertEq(game.deadline(id), bidTime + 1 hours);
    }

    function test_lastSecondBidMakesOldDeadlineTooEarlyToSettle() public {
        uint256 id = _open(100 ether);
        uint256 oldDeadline = game.deadline(id);
        vm.warp(oldDeadline - 1);
        _bid(id, ALICE, 1 ether);
        vm.warp(oldDeadline);
        vm.expectRevert(DollarAuction.AuctionStillActive.selector);
        game.settle(id);
        assertEq(game.deadline(id), oldDeadline + 1 hours - 1);
        _settle(id);
        assertEq(game.withdrawable(ALICE), 100 ether);
    }

    function test_exactDeadlineRejectsBidAndAllowsSettle() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 1 ether);
        vm.warp(game.deadline(id) - 1);
        vm.expectRevert(DollarAuction.AuctionStillActive.selector);
        game.settle(id);
        vm.warp(game.deadline(id));
        vm.expectRevert(DollarAuction.BiddingClosed.selector);
        _bid(id, BOB, 2 ether);
        game.settle(id);
        vm.expectRevert(DollarAuction.AuctionSettled.selector);
        _bid(id, BOB, 2 ether);
        assertEq(game.withdrawable(ALICE), 100 ether);
    }

    function test_settleFirstAtDeadlineAlsoPreventsLateBid() public {
        uint256 id = _open(100 ether);
        _settle(id);
        vm.expectRevert(DollarAuction.AuctionSettled.selector);
        _bid(id, ALICE, 1 ether);
        assertEq(game.withdrawable(SELLER), 100 ether);
    }

    function test_noBidSettlementRefundsPrizeAndEmitsNoWinner() public {
        uint256 id = _open(100 ether);
        vm.warp(game.deadline(id));
        vm.expectEmit(true, true, false, true, address(game));
        emit DollarAuction.Settled(id, address(0), 100 ether, 0);
        game.settle(id);
        assertEq(game.withdrawable(SELLER), 100 ether);
        assertTrue(game.auction(id).settled);
        vm.prank(SELLER);
        game.withdraw();
        assertEq(token.balanceOf(SELLER), FUNDING);
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_singleBidderSettlementPullPayoutsAndDoubleWithdraw() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 150 ether);
        vm.warp(game.deadline(id));
        vm.expectEmit(true, true, false, true, address(game));
        emit DollarAuction.Settled(id, ALICE, 100 ether, 150 ether);
        vm.prank(CAROL); // Settlement is permissionless.
        game.settle(id);
        assertEq(game.withdrawable(ALICE), 100 ether);
        assertEq(game.withdrawable(SELLER), 150 ether);
        assertEq(token.balanceOf(ALICE), FUNDING - 150 ether); // No push payment.
        vm.expectEmit(true, false, false, true, address(game));
        emit DollarAuction.Withdrawn(ALICE, 100 ether);
        vm.prank(ALICE);
        game.withdraw();
        assertEq(token.balanceOf(ALICE), FUNDING - 50 ether); // Overbidding loses ESCL by design.
        vm.expectRevert(DollarAuction.NothingToWithdraw.selector);
        vm.prank(ALICE);
        game.withdraw();
        vm.prank(SELLER);
        game.withdraw();
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_reclaimsOnlyOtherBiddersOnceAfterSettlement() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 1 ether);
        _bid(id, BOB, 2 ether);
        _bid(id, CAROL, 3 ether);
        vm.expectRevert(DollarAuction.AuctionNotSettled.selector);
        vm.prank(ALICE);
        game.reclaim(id);
        _settle(id);
        assertEq(game.withdrawable(SELLER), 5 ether);
        vm.expectRevert(DollarAuction.TopBidderCannotReclaim.selector);
        vm.prank(CAROL);
        game.reclaim(id);
        vm.expectRevert(DollarAuction.TopBidderCannotReclaim.selector);
        vm.prank(BOB);
        game.reclaim(id);
        vm.expectRevert(DollarAuction.NothingToReclaim.selector);
        game.reclaim(id);
        vm.expectEmit(true, true, false, true, address(game));
        emit DollarAuction.Reclaimed(id, ALICE, 1 ether);
        vm.prank(ALICE);
        game.reclaim(id);
        assertEq(game.withdrawable(ALICE), 1 ether);
        vm.expectRevert(DollarAuction.NothingToReclaim.selector);
        vm.prank(ALICE);
        game.reclaim(id);
        _assertTop(id, CAROL, 3 ether, BOB, 2 ether);
    }

    function test_doubleSettleRevertsWithoutDoubleCredit() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 1 ether);
        _settle(id);
        vm.expectRevert(DollarAuction.AuctionSettled.selector);
        game.settle(id);
        assertEq(game.withdrawable(ALICE), 100 ether);
        assertEq(game.withdrawable(SELLER), 1 ether);
    }

    function test_failedBidLeavesRankAndDeadlineUnchanged() public {
        uint256 id = _open(100 ether);
        _bid(id, ALICE, 1 ether);
        uint256 beforeDeadline = game.deadline(id);
        vm.prank(BOB);
        token.approve(address(game), 0);
        vm.warp(block.timestamp + 300);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(game), 0, 2 ether)
        );
        _bid(id, BOB, 2 ether);
        _assertTop(id, ALICE, 1 ether, address(0), 0);
        assertEq(game.bidOf(id, BOB), 0);
        assertEq(game.deadline(id), beforeDeadline);
        assertEq(token.balanceOf(address(game)), 101 ether);
    }

    function test_bidBeyondBalanceRevertsAtomically() public {
        uint256 id = _open(100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, FUNDING, FUNDING + 1)
        );
        _bid(id, ALICE, FUNDING + 1);
        assertEq(game.bidOf(id, ALICE), 0);
        _assertTop(id, address(0), 0, address(0), 0);
        assertEq(token.balanceOf(address(game)), 100 ether);
    }

    function test_multipleAuctionsKeepBidsSeparateAndAccumulateCredits() public {
        uint256 first = _open(100 ether);
        uint256 second = _open(200 ether);
        assertEq(second, 1);
        _bid(first, ALICE, 2 ether);
        _bid(second, ALICE, 10 ether);
        _bid(second, BOB, 20 ether);
        _settle(first);
        assertFalse(game.auction(second).settled);
        assertEq(game.withdrawable(ALICE), 100 ether);
        _settle(second);
        assertEq(game.withdrawable(SELLER), 32 ether);
        assertEq(game.withdrawable(BOB), 200 ether);
        assertEq(game.bidOf(first, ALICE), 2 ether);
        assertEq(game.bidOf(second, ALICE), 10 ether);
        assertEq(token.balanceOf(address(game)), 332 ether);
        vm.prank(SELLER);
        game.withdraw();
        vm.prank(ALICE);
        game.withdraw();
        vm.prank(BOB);
        game.withdraw();
        assertEq(token.balanceOf(address(game)), 0);
    }

    function test_unknownIdsRevertExceptRawBidMapping() public {
        bytes memory errorData = abi.encodeWithSelector(DollarAuction.UnknownAuction.selector, 0);
        vm.expectRevert(errorData);
        game.auction(0);
        vm.expectRevert(errorData);
        game.topTwo(0);
        vm.expectRevert(errorData);
        game.deadline(0);
        vm.expectRevert(errorData);
        game.bid(0, 1 ether);
        vm.expectRevert(errorData);
        game.settle(0);
        vm.expectRevert(errorData);
        game.reclaim(0);
        assertEq(game.bidOf(0, ALICE), 0);
    }

    function test_rejectsEthAndUnknownSelectors() public {
        vm.deal(address(this), 1 ether);
        (bool receiveOK,) = address(game).call{value: 1}("");
        (bool payableOpenOK,) = address(game).call{value: 1}(abi.encodeCall(game.open, (100 ether)));
        (bool fallbackOK,) = address(game).call(hex"deadbeef");
        assertFalse(receiveOK);
        assertFalse(payableOpenOK);
        assertFalse(fallbackOK);
        assertEq(address(game).balance, 0);
    }

    function testFuzz_returningBidderPaysOnlyTopUp(uint96 first, uint96 increase, uint96 returnIncrease) public {
        uint256 x = bound(first, 1 ether, 100_000 ether);
        uint256 y = x + bound(increase, 1 ether, 100_000 ether);
        uint256 z = y + bound(returnIncrease, 1 ether, 100_000 ether);
        uint256 id = _open(100 ether);
        _bid(id, ALICE, x);
        _bid(id, BOB, y);
        _bid(id, ALICE, z);
        assertEq(token.balanceOf(ALICE), FUNDING - z);
        assertEq(token.balanceOf(address(game)), 100 ether + y + z);
        _settle(id);
        assertEq(game.withdrawable(SELLER), y + z);
        assertEq(game.withdrawable(ALICE), 100 ether);
        vm.expectRevert(DollarAuction.TopBidderCannotReclaim.selector);
        vm.prank(BOB);
        game.reclaim(id);
    }
}
