// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {InsuranceCover} from "../src/InsuranceCover.sol";
import {InsurancePool} from "../src/InsurancePool.sol";
import {Vaults} from "../src/Vaults.sol";
import {Governance} from "../src/Governance.sol";
import {BqBTC} from "../src/BqBTC.sol";

contract DeployScript is Script {
    InsuranceCover public insuranceCover;
    InsurancePool public insurancePool;
    Vaults public vaults;
    Governance public governance;
    BqBTC public bqBTC;

    function setUp() public {}

    function run() public returns (InsuranceCover, InsurancePool, Vaults, Governance, BqBTC) {
        vm.startBroadcast();
        address OWNER = 0x47C14E2dD82B7Cf0E7426c991225417e4C40Cd19;
        address ALT_TOKEN = 0x73795572FB8c1c737513156ecb8b1Cc9a3f9cA46;
        address poolCanister = 0x9DB1bc882935529E8E76abccB1165275BBf8Cbd8;
        uint256 MIN = 20000000000000;

        bqBTC = new BqBTC("BQ BTC", "BQBTC", 8, MIN, OWNER, ALT_TOKEN, 1000);
        address btcAddress = address(bqBTC);
        console.log("BqBTC address: ", btcAddress);

        insurancePool = new InsurancePool(OWNER, btcAddress);
        address poolAddress = address(insurancePool);
        console.log("InsurancePool address: ", poolAddress);

        insuranceCover = new InsuranceCover(poolAddress, OWNER, btcAddress);
        address coverAddress = address(insuranceCover);
        console.log("InsuranceCover address: ", coverAddress);

        vaults = new Vaults(OWNER, btcAddress, poolAddress, coverAddress);
        address vaultAddress = address(vaults);
        console.log("Vaults address: ", vaultAddress);

        governance = new Governance(btcAddress, poolAddress, vaultAddress, 2, OWNER);
        address governanceAddress = address(governance);
        console.log("Governance address: ", governanceAddress);

        vm.stopBroadcast();

        vm.startBroadcast(OWNER);
        insurancePool.setCover(coverAddress);
        insurancePool.setVault(vaultAddress);
        insurancePool.setPoolCanister(poolCanister);
        vaults.setPoolCanister(poolCanister);
        vaults.setCover(coverAddress);
        vaults.setPool(poolAddress);
        bqBTC.setContracts(poolAddress, coverAddress, vaultAddress);
        vm.stopBroadcast();

        return (insuranceCover, insurancePool, vaults, governance, bqBTC);
    }
}
