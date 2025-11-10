// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";

contract DeployMockV3 is Script {
    function run() external {
        uint8  decimals = uint8(vm.envUint("FEED_DECIMALS"));
        int256 initial  = vm.envInt("FEED_INITIAL");

        vm.startBroadcast();
        MockV3Aggregator feed = new MockV3Aggregator(decimals, initial);
        vm.stopBroadcast();

        console2.log("MockV3Aggregator deployed at:", address(feed));
    }
}
