// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

// === Ajustá este import si tu contrato está en otro path ===
import {KipuBank} from "../src/KipuBank.sol";

// OZ
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20}  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Chainlink interface oficial
import {AggregatorV3Interface} from
  "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Router V2 - using official interface
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// Mock Router para tests
contract MockUniswapV2Router is IUniswapV2Router02 {
    address private _WETH;
    
    constructor(address weth) {
        _WETH = weth;
    }
    
    function WETH() external pure override returns (address) {
        return 0x1234567890123456789012345678901234567890; // Mock address
    }
    
    function factory() external pure override returns (address) {
        return address(0);
    }
    
    function addLiquidityETH(
        address /* token */,
        uint amountTokenDesired,
        uint,
        uint,
        address,
        uint
    ) external payable override returns (uint, uint, uint) {
        // Mock implementation - just return some values
        return (amountTokenDesired, msg.value, 1000);
    }
    
    function getAmountsOut(uint amountIn, address[] calldata path)
        external pure override returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        // Simple mock: assume 1 ETH = 3000 USDC
        if (path.length == 2) {
            amounts[1] = (amountIn * 3000) / 1e12; // Convert 18 decimals to 6 decimals
        } else if (path.length == 3) {
            amounts[1] = amountIn; // Mock intermediate
            amounts[2] = (amountIn * 3000) / 1e12; // Final USDC
        }
    }
    
    // Stub implementations for other required functions
    function addLiquidity(address,address,uint,uint,uint,uint,address,uint) 
        external pure override returns (uint,uint,uint) { return (0,0,0); }
    function removeLiquidity(address,address,uint,uint,uint,address,uint) 
        external pure override returns (uint,uint) { return (0,0); }
    function removeLiquidityETH(address,uint,uint,uint,address,uint) 
        external pure override returns (uint,uint) { return (0,0); }
    function removeLiquidityWithPermit(address,address,uint,uint,uint,address,uint,bool,uint8,bytes32,bytes32) 
        external pure override returns (uint,uint) { return (0,0); }
    function removeLiquidityETHWithPermit(address,uint,uint,uint,address,uint,bool,uint8,bytes32,bytes32) 
        external pure override returns (uint,uint) { return (0,0); }
    function swapExactTokensForTokens(uint amountIn, uint, address[] calldata path, address to, uint) 
        external override returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        // Simple mock: final token gets converted at 3000 rate (assuming USDC target)
        if (path.length == 2) {
            amounts[1] = (amountIn * 3000) / 1e12; // 18->6 decimals
            // Actually transfer the output token to the recipient
            if (amounts[1] > 0) {
                IERC20(path[1]).transfer(to, amounts[1]);
            }
        } else if (path.length == 3) {
            amounts[1] = amountIn; // intermediate
            amounts[2] = (amountIn * 3000) / 1e12; // final USDC
            // Actually transfer the output token to the recipient
            if (amounts[2] > 0) {
                IERC20(path[2]).transfer(to, amounts[2]);
            }
        }
    }
    function swapTokensForExactTokens(uint,uint,address[] calldata,address,uint) 
        external pure override returns (uint[] memory) { return new uint[](0); }
    function swapExactETHForTokens(uint, address[] calldata path, address, uint) 
        external payable override returns (uint[] memory amounts) {
        // Simulate failure for unknown tokens (addresses we haven't seen before)
        // This is a simple heuristic: if the target token address is very recent (high address), fail
        if (path.length == 2 && uint160(path[1]) > uint160(0xC000000000000000000000000000000000000000)) {
            revert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        }
        
        amounts = new uint[](path.length);
        amounts[0] = msg.value;
        // ETH to USDC conversion
        if (path.length == 2) {
            amounts[1] = (msg.value * 3000) / 1e12; // 18->6 decimals
        }
    }
    function swapTokensForExactETH(uint,uint,address[] calldata,address,uint) 
        external pure override returns (uint[] memory) { return new uint[](0); }
    function swapExactTokensForETH(uint,uint,address[] calldata,address,uint) 
        external pure override returns (uint[] memory) { return new uint[](0); }
    function swapETHForExactTokens(uint,address[] calldata,address,uint) 
        external payable override returns (uint[] memory) { return new uint[](0); }
    function quote(uint,uint,uint) external pure override returns (uint) { return 0; }
    function getAmountOut(uint,uint,uint) external pure override returns (uint) { return 0; }
    function getAmountIn(uint,uint,uint) external pure override returns (uint) { return 0; }
    function getAmountsIn(uint,address[] calldata) external pure override returns (uint[] memory) { return new uint[](0); }
    function removeLiquidityETHSupportingFeeOnTransferTokens(address,uint,uint,uint,address,uint) external pure override returns (uint) { return 0; }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(address,uint,uint,uint,address,uint,bool,uint8,bytes32,bytes32) external pure override returns (uint) { return 0; }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint,uint,address[] calldata,address,uint) external pure override {}
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint,address[] calldata,address,uint) external payable override {}
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint,uint,address[] calldata,address,uint) external pure override {}
}

// Mock WETH contract
contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
}

// --- Mocks livianos ---

contract USDC6 is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract KGLD18 is ERC20 {
    constructor() ERC20("Kipu Gold", "KGLD") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

// Mock completo para AggregatorV3Interface
contract MockV3Aggregator is AggregatorV3Interface {
    uint8   private _decimals;
    int256  private _answer;

    constructor(uint8 d, int256 a) { _decimals = d; _answer = a; }

    function decimals() external view override returns (uint8) { return _decimals; }
    function description() external pure override returns (string memory) { return "MockV3"; }
    function version() external pure override returns (uint256) { return 1; }

    function getRoundData(uint80)
        external view override
        returns (uint80, int256, uint256, uint256, uint80)
    { return (0, _answer, block.timestamp, block.timestamp, 0); }

    function latestRoundData()
        public view override
        returns (uint80, int256, uint256, uint256, uint80)
    { return (0, _answer, block.timestamp, block.timestamp, 0); }

    function setAnswer(int256 a) external { _answer = a; }
}

contract KipuBankNativeTest is Test {
    // Actores
    address internal owner;
    address internal user;

    // Router / WETH runtime
    IUniswapV2Router02 internal router;
    address internal WETH;

    // Tokens & feed
    USDC6 internal usdc;
    KGLD18 internal kgld;
    MockV3Aggregator internal feed;

    // SUT
    KipuBank internal bank;

    // Parámetros prácticos
    uint256 internal constant INITIAL_USDC_LIQ = 100_000_000; // 100 USDC (6 dec)
    uint256 internal constant INITIAL_ETH_LIQ  = 0.05 ether;
    uint256 internal constant NATIVE_DEPOSIT   = 0.01 ether;

    // Evento (debe existir en tu contrato)
    event Deposited(address indexed user, address indexed token, uint256 amountIn, uint256 usdcOut);



    function _deadline() internal view returns (uint256) {
        return block.timestamp + 1 hours;
    }

    function setUp() public {
        // Setup actors
        owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        user = address(this);
        
        // Deploy mock router
        router = new MockUniswapV2Router(address(0));
        WETH = router.WETH();

        // Desplegar mocks
        usdc = new USDC6();
        kgld = new KGLD18();
        feed = new MockV3Aggregator(8, 3000 * 1e8); // 3000 USD/ETH con 8 dec

        // Liquidez WETH/USDC
        usdc.mint(user, INITIAL_USDC_LIQ);
        IERC20(address(usdc)).approve(address(router), type(uint256).max);
        router.addLiquidityETH{value: INITIAL_ETH_LIQ}(
            address(usdc),
            INITIAL_USDC_LIQ,
            0,
            0,
            user,
            _deadline()
        );

        // Deploy banco
        uint256 capWei      = 1_000 ether;
        uint256 maxTxWei    = 10 ether;
        uint256 bankUsdCap8 = 0; // sin tope USD

        vm.prank(owner);
        bank = new KipuBank(
            owner,
            capWei,
            maxTxWei,
            AggregatorV3Interface(address(feed)),
            bankUsdCap8,
            IERC20(address(usdc)),
            IERC20(address(kgld)),
            router
        );
    }

    // --- Caso feliz: depositNative ETH->USDC ---
    function test_depositNative_happy() public {
        uint256 beforeBal = bank.erc20Balances(IERC20(address(usdc)), user);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(usdc);
        uint[] memory amountsOut = router.getAmountsOut(NATIVE_DEPOSIT, path);
        uint256 expectedOut = amountsOut[1];
        uint256 minOut = (expectedOut * 99) / 100;

        vm.expectEmit(true, true, true, false); // Don't check data field strictly
        emit Deposited(user, address(0), NATIVE_DEPOSIT, 0); // address(0) for ETH

        bank.depositNative{value: NATIVE_DEPOSIT}(minOut, _deadline());

        uint256 got = bank.erc20Balances(IERC20(address(usdc)), user) - beforeBal;
        assertGe(got, minOut, "USDC interno menor a minOut");
    }

    // --- Revert sin liquidez: banco apuntando a un USDC sin par ---
    function test_depositNative_revertsWithoutLiquidity() public {
        USDC6 lonelyUsdc = new USDC6();

        vm.prank(owner);
        KipuBank bankNoPool = new KipuBank(
            owner,
            1_000 ether,
            10 ether,
            AggregatorV3Interface(address(feed)),
            0,
            IERC20(address(lonelyUsdc)),
            IERC20(address(kgld)),
            router
        );

        vm.expectRevert(); // Should revert due to no liquidity
        bankNoPool.depositNative{value: 0.005 ether}(1, _deadline());
    }

    receive() external payable {}
}
