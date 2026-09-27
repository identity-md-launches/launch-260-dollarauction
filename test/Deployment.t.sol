// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {DollarAuction} from "../src/DollarAuction.sol";

contract FactoryFixture {
    function deploy() external returns (LaunchToken token, DollarAuction game) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        game = new DollarAuction{salt: bytes32(uint256(2))}(address(token));
    }
}

contract DeploymentTest is Test {
    function test_factoryConstructorsNeedNoInitializationOrApplicationFunding() public {
        vm.chainId(11155111);
        FactoryFixture factory = new FactoryFixture();
        (LaunchToken token, DollarAuction game) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(game)), 0);
        assertEq(address(game.token()), address(token));
        assertEq(game.auctionCount(), 0);
        _checkRuntime(address(token));
        _checkRuntime(address(game));
    }

    function _checkRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
            }
        }
    }
}
