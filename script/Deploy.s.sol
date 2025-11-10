// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {KipuBank} from "../src/KipuBank.sol";
import {KipuGLD} from "../src/tokens/KipuGLD.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    function run() external {
        address owner         = vm.envAddress("OWNER");
        uint256 capWei        = vm.envUint("CAP_WEI");
        uint256 maxTx         = vm.envUint("MAX_TX");
        address feedEthUsd    = vm.envAddress("FEED_ETHUSD");  // Chainlink ETH/USD (8 dec)
        uint256 bankUsdCap8   = vm.envUint("BANK_USD_CAP8");   // ej 1_000e8
        address usdcAddr      = vm.envAddress("USDC");
        address kgldAddr      = vm.envAddress("KGLD");         // si querés, podemos desplegarlo si viene 0x0
        address routerAddr    = vm.envAddress("ROUTER");       // UniswapV2Router02

        vm.startBroadcast();

        // Si no pasaste KGLD, lo desplegamos acá (opcional)
        if (kgldAddr == address(0)) {
            KipuGLD kg = new KipuGLD(owner, 1_000_000 ether);
            kgldAddr = address(kg);
        }

        KipuBank bank = new KipuBank(
        owner,
        capWei,
        maxTx,
        AggregatorV3Interface(feedEthUsd),
        bankUsdCap8,
        IERC20(usdcAddr),
        IERC20(kgldAddr),
        IUniswapV2Router02(routerAddr)
        );

        vm.stopBroadcast();
    }
}
