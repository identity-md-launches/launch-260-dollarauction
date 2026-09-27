// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {DollarAuction} from "../src/DollarAuction.sol";

/// @dev Independent model ranks bidders by scanning all participants, unlike the contract's cached top two.
contract AuctionHandler is Test {
    struct ModelAuction {
        address seller;
        uint256 prize;
        uint256 lastActivity;
        bool settled;
    }

    LaunchToken public immutable token;
    DollarAuction public immutable game;
    address[8] public actors;
    uint256 public count;
    uint256 public deposited;
    uint256 public paidOut;
    mapping(uint256 => ModelAuction) private _model;
    mapping(uint256 => mapping(address => uint256)) public standing;
    mapping(address => uint256) public credit;

    constructor(LaunchToken token_, DollarAuction game_) {
        token = token_;
        game = game_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(0x1000 + i));
        }
    }

    function model(uint256 id) external view returns (ModelAuction memory) {
        return _model[id];
    }

    function ranked(uint256 id) public view returns (address first, address second) {
        for (uint256 i; i < actors.length; ++i) {
            address user = actors[i];
            uint256 amount = standing[id][user];
            if (amount > standing[id][first]) {
                second = first;
                first = user;
            } else if (amount > standing[id][second]) {
                second = user;
            }
        }
    }

    function open(uint256 actorSeed, uint256 prizeSeed) external {
        if (count == 12) return;
        address seller = actors[actorSeed % actors.length];
        uint256 prize = bound(prizeSeed, 100 ether, 1000 ether);
        if (token.balanceOf(seller) < prize) return;
        vm.prank(seller);
        uint256 id = game.open(prize);
        assertEq(id, count++);
        _model[id] = ModelAuction(seller, prize, block.timestamp, false);
        deposited += prize;
    }

    function placeBid(uint256 idSeed, uint256 actorSeed, uint256 incrementSeed) external {
        if (count == 0) return;
        uint256 id = idSeed % count;
        ModelAuction storage m = _model[id];
        if (m.settled || block.timestamp >= m.lastActivity + 1 hours) return;
        address user = actors[actorSeed % actors.length];
        (address first,) = ranked(id);
        if (user == m.seller || user == first) return;
        uint256 newTotal = standing[id][first] + bound(incrementSeed, 1 ether, 200 ether);
        uint256 payment = newTotal - standing[id][user];
        if (token.balanceOf(user) < payment) return;
        uint256 beforeBalance = token.balanceOf(user);
        vm.prank(user);
        game.bid(id, newTotal);
        assertEq(beforeBalance - token.balanceOf(user), payment);
        standing[id][user] = newTotal;
        m.lastActivity = block.timestamp;
        deposited += payment;
    }

    function advance(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 0, 1 hours + 1));
    }

    function settle(uint256 idSeed) external {
        if (count == 0) return;
        uint256 id = idSeed % count;
        ModelAuction storage m = _model[id];
        if (m.settled || block.timestamp < m.lastActivity + 1 hours) return;
        game.settle(id);
        (address first, address second) = ranked(id);
        if (first == address(0)) {
            credit[m.seller] += m.prize;
        } else {
            credit[first] += m.prize;
            credit[m.seller] += standing[id][first] + standing[id][second];
        }
        m.settled = true;
    }

    function reclaim(uint256 idSeed, uint256 actorSeed) external {
        if (count == 0) return;
        uint256 id = idSeed % count;
        address user = actors[actorSeed % actors.length];
        if (!_model[id].settled || standing[id][user] == 0) return;
        (address first, address second) = ranked(id);
        if (user == first || user == second) return;
        vm.prank(user);
        game.reclaim(id);
        credit[user] += standing[id][user];
        standing[id][user] = 0;
    }

    function withdraw(uint256 actorSeed) external {
        address user = actors[actorSeed % actors.length];
        uint256 amount = credit[user];
        if (amount == 0) return;
        uint256 beforeBalance = token.balanceOf(user);
        vm.prank(user);
        game.withdraw();
        assertEq(token.balanceOf(user) - beforeBalance, amount);
        credit[user] = 0;
        paidOut += amount;
    }
}

contract DollarAuctionInvariantTest is Test {
    LaunchToken internal token;
    DollarAuction internal game;
    AuctionHandler internal handler;

    function setUp() public {
        token = new LaunchToken();
        game = new DollarAuction(address(token));
        handler = new AuctionHandler(token, game);
        for (uint256 i; i < 8; ++i) {
            address user = handler.actors(i);
            token.transfer(user, 1_000_000 ether);
            vm.prank(user);
            token.approve(address(game), type(uint256).max);
        }
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = AuctionHandler.open.selector;
        selectors[1] = AuctionHandler.placeBid.selector;
        selectors[2] = AuctionHandler.advance.selector;
        selectors[3] = AuctionHandler.settle.selector;
        selectors[4] = AuctionHandler.reclaim.selector;
        selectors[5] = AuctionHandler.withdraw.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
        // Guarantee auctions and returning bidders are present before random sequences.
        handler.open(0, 100 ether);
        handler.placeBid(0, 1, 1 ether);
        handler.placeBid(0, 2, 1 ether);
        handler.placeBid(0, 1, 1 ether);
        handler.placeBid(0, 3, 1 ether);
        handler.open(4, 200 ether);
    }

    function invariant_exactEscrowLiabilitiesAndIndependentBidRanking() public view {
        uint256 liabilities;
        assertEq(game.auctionCount(), handler.count());
        for (uint256 id; id < handler.count(); ++id) {
            AuctionHandler.ModelAuction memory m = handler.model(id);
            DollarAuction.Auction memory a = game.auction(id);
            (address first, address second) = handler.ranked(id);
            (address actualFirst, uint256 firstBid, address actualSecond, uint256 secondBid) = game.topTwo(id);
            assertEq(actualFirst, first);
            assertEq(actualSecond, second);
            assertEq(firstBid, handler.standing(id, first));
            assertEq(secondBid, handler.standing(id, second));
            assertEq(a.seller, m.seller);
            assertEq(a.prize, m.prize);
            assertEq(a.lastActivity, m.lastActivity);
            assertEq(a.settled, m.settled);
            if (!a.settled) liabilities += a.prize;
            for (uint256 i; i < 8; ++i) {
                address user = handler.actors(i);
                uint256 bid = game.bidOf(id, user);
                assertEq(bid, handler.standing(id, user));
                if (!a.settled || (user != first && user != second)) liabilities += bid;
            }
        }
        for (uint256 i; i < 8; ++i) {
            address user = handler.actors(i);
            assertEq(game.withdrawable(user), handler.credit(user));
            liabilities += game.withdrawable(user);
        }
        assertEq(token.balanceOf(address(game)), liabilities);
        assertEq(token.balanceOf(address(game)), handler.deposited() - handler.paidOut());
        assertEq(token.totalSupply(), 1e27);
    }

    /// @dev Drain every remaining obligation after a random run; no bidder's funds may be stranded.
    function afterInvariant() public {
        vm.warp(block.timestamp + 1 hours);
        for (uint256 id; id < handler.count(); ++id) {
            handler.settle(id);
            for (uint256 i; i < 8; ++i) {
                handler.reclaim(id, i);
            }
        }
        for (uint256 i; i < 8; ++i) {
            handler.withdraw(i);
        }
        assertEq(token.balanceOf(address(game)), 0);
        assertEq(handler.deposited(), handler.paidOut());
    }
}
