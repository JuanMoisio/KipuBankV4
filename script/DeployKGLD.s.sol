// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {KipuGLD} from "../src/tokens/KipuGLD.sol";

contract DeployKGLD is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY"); // tu pk en decimal o usa vm.envBytes32 si la guardás 0x...
        address owner = vm.envAddress("OWNER");
        uint256 initialSupply = vm.envUint("INITIAL_SUPPLY"); // en wei

        vm.startBroadcast(pk);
        KipuGLD t = new KipuGLD(owner, initialSupply);
        console2.log("KGLD deployed at:", address(t));
        vm.stopBroadcast();
    }
}
