// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken internal token;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndSupply() public view {
        assertEq(token.name(), "Escalation");
        assertEq(token.symbol(), "ESCL");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testFuzz_transfersPreserveSupply(uint256 amount) public {
        amount = bound(amount, 0, 1e27);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), 1e27 - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_approveTransferFromAndAllowance() public {
        token.approve(ALICE, 7 ether);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 5 ether));
        assertEq(token.allowance(address(this), ALICE), 2 ether);
        assertEq(token.balanceOf(BOB), 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 2 ether, 3 ether)
        );
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 3 ether);
    }

    function test_infiniteAllowanceAndSelfTransfer() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), address(this), 5 ether);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
    }

    function test_invalidRecipientAndInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_noMintAdminOrUpgradeEntryPoints() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, 1e27);
            (bool deployerOK,) = address(token).call(data);
            vm.prank(ALICE);
            (bool strangerOK,) = address(token).call(data);
            assertFalse(deployerOK);
            assertFalse(strangerOK);
            assertEq(token.totalSupply(), 1e27);
            assertEq(token.balanceOf(ALICE), 0);
        }
    }
}
