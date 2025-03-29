// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DeployScript} from "../script/Deploy.s.sol";
import "../src/InsurancePool.sol" as InsurancePool;

contract InsurancePoolTest is Test {
    InsurancePool public insurancePool;

    function setUp() public {
        Deploy deploy = new Deploy();
        (, insurancePool, , , , ) = deploy.run();
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
