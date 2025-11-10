// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// === Ajustá estos imports a tu repo real ===
import {KipuBank} from "../src/KipuBank.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from
  "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// IMPORTA LA MISMA INTERFAZ QUE USA KipuBank
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// Mock KGLD (18d) - Similar to the real KipuGLD contract
contract KGLD18 is ERC20, Ownable {
    constructor() ERC20("Kipu Gold", "KGLD") Ownable(msg.sender) {}
    
    function mint(address to, uint256 amount) external onlyOwner { 
        _mint(to, amount); 
    }
}

contract DeployAllSepolia is Script {
    // USDC fijo (Sepolia) provisto por el usuario
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // Parámetros del banco
    uint256 constant WITHDRAW_MAX   = 10 ether;    // tope por retiro de ETH (en wei)
    uint256 constant MAX_TRANSACTIONS = 10000;     // tope global de número de transacciones
    uint256 constant BANK_USD_CAP   = 0;           // 0 = sin tope USD (en 18 decimals)

    function run() external {
        // --- ENV ---
        address owner       = vm.envAddress("OWNER");
        address routerAddr  = vm.envAddress("ROUTER");
        address feedEthUsd  = vm.envAddress("FEED_ETH_USD");

        // Flags opcionales para añadir liquidez
        uint256 addLiquidityFlag = _envOrUint("ADD_LIQUIDITY", 0);
        uint256 liqUsdcAmount    = _envOrUint("LIQ_USDC_AMOUNT", 100_000_000);        // 100 USDC (6d)
        uint256 liqEthAmountWei  = _envOrUint("LIQ_ETH_AMOUNT_WEI", 0.01 ether);      // 0.01 ETH

        uint256 pk = vm.envUint("PRIVATE_KEY"); // clave que firmará

        console.log("== DeployAllSepolia ==");
        console.log("OWNER        :", owner);
        console.log("ROUTER       :", routerAddr);
        console.log("USDC         :", USDC);
        console.log("FEED_ETH_USD :", feedEthUsd);
        console.log("ADD_LIQUIDITY:", addLiquidityFlag);

        vm.startBroadcast(pk);

        // --- Router real con la MISMA interfaz que usa el contrato ---
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddr);
        address WETH = router.WETH();
        console.log("WETH         :", WETH);
        console.log("FACTORY      :", router.factory());

        // --- Desplegar KGLD ---
        KGLD18 kgld = new KGLD18();
        console.log("KGLD deployed at:", address(kgld));

        // (Opcional) Añadir liquidez WETH/USDC si hay saldo USDC real
        if (addLiquidityFlag == 1) {
            _addLiquidityWethUsdc(router, WETH, owner, liqUsdcAmount, liqEthAmountWei);
        }

        // --- Deploy KipuBank ---
        KipuBank bank = new KipuBank(
            owner,                                  // initialOwner
            WITHDRAW_MAX,                           // capWei (withdrawal cap in wei)
            MAX_TRANSACTIONS,                       // maxTransactions (number of transactions)
            AggregatorV3Interface(feedEthUsd),     // priceFeed
            BANK_USD_CAP,                          // bankUsdCap_
            IERC20(USDC),                          // usdc_
            IERC20(address(kgld)),                 // kgld_
            router                                 // router_
        );
        console.log("KipuBank deployed at:", address(bank));

        vm.stopBroadcast();

        console.log("==== DONE ====");
        console.log("USDC :", USDC);
        console.log("KGLD :", address(kgld));
        console.log("BANK :", address(bank));
        console.log("WETH :", WETH);
        console.log("ROUTER:", routerAddr);
        console.log("FEED  :", feedEthUsd);
    }

    // --- Helpers ---

    function _addLiquidityWethUsdc(
        IUniswapV2Router02 router,
        address /*WETH*/,
        address to,
        uint256 usdcAmount,
        uint256 ethAmountWei
    ) internal {
        // El msg.sender en broadcast es la EOA que firma
        address sender = msg.sender;
        uint256 bal = IERC20(USDC).balanceOf(sender);
        console.log("USDC balance(sender):", bal);
        require(bal >= usdcAmount, "Not enough USDC to add liquidity");

        // approve USDC -> router
        IERC20(USDC).approve(address(router), type(uint256).max);

        uint256 deadline = block.timestamp + 1 hours;

        (uint aT, uint aE, uint liq) = router.addLiquidityETH{value: ethAmountWei}(
            USDC,
            usdcAmount,
            0,
            0,
            to,
            deadline
        );

        console.log("addLiquidityETH -> amountToken:", aT);
        console.log("addLiquidityETH -> amountETH  :", aE);
        console.log("addLiquidityETH -> liquidity  :", liq);
    }

    function _envOrUint(string memory key, uint256 fallbackValue) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) { return v; } catch { return fallbackValue; }
    }
}
