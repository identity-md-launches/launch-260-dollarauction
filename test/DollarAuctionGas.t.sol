// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {DollarAuction} from "../src/DollarAuction.sol";

contract DollarAuctionGasTest is Test {
    LaunchToken internal token;
    DollarAuction internal small;
    DollarAuction internal large;

    function setUp() public {
        token = new LaunchToken();
        small = _prepare(2);
        large = _prepare(200);
        vm.warp(block.timestamp + 1 hours);
    }

    function _prepare(uint256 count) private returns (DollarAuction game) {
        game = new DollarAuction(address(token));
        token.approve(address(game), 100 ether);
        game.open(100 ether);
        // Both auctions end with the same highest/second amounts and addresses.
        for (uint256 i = 201 - count; i <= 200; ++i) {
            address bidder = address(uint160(10_000 + i));
            token.transfer(bidder, i * 1 ether);
            vm.startPrank(bidder);
            token.approve(address(game), i * 1 ether);
            game.bid(0, i * 1 ether);
            vm.stopPrank();
        }
    }

    function _measure(DollarAuction game) private returns (uint256 used) {
        // Equalize all account/storage access warmth; setup ran outside the measured calls.
        vm.cool(address(game));
        uint256 beforeGas = gasleft();
        game.settle(0);
        return beforeGas - gasleft();
    }

    function test_settleWith200BiddersCostsExactlyTheSameAsWith2() public {
        uint256 two = _measure(small);
        uint256 twoHundred = _measure(large);
        emit log_named_uint("settle with 2 bidders", two);
        emit log_named_uint("settle with 200 bidders", twoHundred);
        assertEq(twoHundred, two, "settlement cost must not depend on bidder count");
        assertEq(large.withdrawable(address(this)), 399 ether);
        assertEq(small.withdrawable(address(this)), 399 ether);
        assertEq(large.withdrawable(address(10_200)), 100 ether);
    }
}
