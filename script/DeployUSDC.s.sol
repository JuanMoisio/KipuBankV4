// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockUSDC} from "../src/tokens/MockUSDC.sol";

contract DeployUSDC is Script {
    function run() external returns (MockUSDC usdc) {
        address owner = vm.envAddress("OWNER");
        vm.startBroadcast();                 // usa la key que pases por CLI
        usdc = new MockUSDC(owner);
        vm.stopBroadcast();
    }
}
