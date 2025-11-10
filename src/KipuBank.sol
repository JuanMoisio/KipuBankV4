//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";





contract KipuBank is Ownable, Pausable {
    using SafeERC20 for IERC20;

    // =========================
    // ERC-20 STORAGE
    // =========================

    mapping(IERC20 token => mapping(address user => uint256 amount)) public erc20Balances;

    // =========================
    // VARIABLES
    // =========================

    mapping(address client => uint256 amount) public balances;

    uint256 public immutable WITHDRAW_MAX;
    uint256 public immutable BANKCAP;

    uint256 public transactionsCounter;
    uint256 public withdrawalCounter;

    AggregatorV3Interface public immutable ETHUSDFEED;
    uint256 public immutable BANKUSDCAP;
    uint256 public bankUsdLiabilities;

    // === NUEVO: integraciones swap ===
    IERC20 public immutable USDC;                       // token estable destino
    IERC20 public immutable KGLD;                       // tu token que NO se swapea
    IUniswapV2Router02 public immutable UNISWAPV2ROUTER; // router Uniswap V2
    IUniswapV2Router02 public immutable ROUTER;         // alias para compatibilidad
    address public immutable WETH;                      // Wrapped ETH address

    // =========================
    // EVENTS
    // =========================

    event depositDone(address client, uint256 amount);
    event withdrawalDone(address client, uint256 amount);

    event erc20DepositDone(address indexed token, address indexed client, uint256 amount);
    event erc20WithdrawalDone(address indexed token, address indexed client, uint256 amount);
    
    event Deposited(address indexed user, address indexed token, uint256 amountIn, uint256 usdcOut);

    // =========================
    // ERRORS
    // =========================

    error transactionFailed();
    error insufficientBalance(uint256 have, uint256 need);
    error capExceeded(uint256 requested, uint256 cap);
    error wrongUser(address thief, address victim);
    error maxTransactionsLimit(uint256 transactions, uint256 limit);
    error zeroDeposit();
    error noCapWei();
    error noTransactions();
    error reentrancy();
    error invalidPrice();
    error bankUsdCapExceeded(uint256 newLiability, uint256 cap);

    // nuevos para swap/retirada
    error OnlyUSDCOrKGLD();
    error SwapFailed();
    error ZeroAmount();

    // =========================
    // CONSTRUCTOR
    // =========================

    /// @param initialOwner owner del contrato
    /// @param capWei tope por retiro en wei (ETH)
    /// @param maxTransactions tope global de depósitos (contador)
    /// @param priceFeed Chainlink ETH/USD (8 dec)
    /// @param bankUsdCap_ límite de pasivos en USD(8) para ETH (0 deshabilita)
    /// @param usdc_ dirección del token USDC
    /// @param kgld_ dirección del token KGLD (exento de swap)
    /// @param router_ dirección del UniswapV2Router02
    constructor(
        address initialOwner,
        uint256 capWei,
        uint256 maxTransactions,
        AggregatorV3Interface priceFeed,
        uint256 bankUsdCap_,
        IERC20 usdc_,
        IERC20 kgld_,
        IUniswapV2Router02 router_
    ) Ownable(initialOwner) {
        if (capWei == 0) revert noCapWei();
        if (maxTransactions == 0) revert noTransactions();

        WITHDRAW_MAX = capWei;
        BANKCAP = maxTransactions;
        ETHUSDFEED = priceFeed;
        BANKUSDCAP = bankUsdCap_;

        USDC = usdc_;
        KGLD = kgld_;
        UNISWAPV2ROUTER = router_;
        ROUTER = router_; // alias
        WETH = router_.WETH(); // get WETH from router
    }

    // =========================
    // MODIFIERS / GUARDS
    // =========================

    modifier nonZeroValue() {
        _nonZeroValue();
        _;
    }

    function _nonZeroValue() internal {
        if (msg.value == 0) revert zeroDeposit();
    }

    modifier underTxCap() {
        _underTxCap();
        _;
    }

    function _underTxCap() internal view {
        if (transactionsCounter >= BANKCAP) {
            revert maxTransactionsLimit(transactionsCounter, BANKCAP);
        }
    }

    modifier countDeposit() {
        _;
        _countDeposit();
    }

    function _countDeposit() internal {
        transactionsCounter += 1;
    }

    uint256 private _locked;

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_locked == 1) revert reentrancy();
        _locked = 1;
    }

    function _nonReentrantAfter() internal {
        _locked = 0;
    }

    modifier countWithdrawal() {
        _;
        _countWithdrawal();
    }

    function _countWithdrawal() internal {
        withdrawalCounter += 1;
    }

    modifier hasFunds(uint256 amount) {
        _hasFunds(amount);
        _;
    }

    function _hasFunds(uint256 amount) internal view{
        uint256 bal = balances[msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);
    }

    modifier withinWithdrawCap(uint256 amount) {
        _withinWithdrawCap(amount);
        _;
    }

    function _withinWithdrawCap(uint256 amount) internal view{
        if (amount > WITHDRAW_MAX) revert capExceeded(amount, WITHDRAW_MAX);
    }

    modifier hasFundsERC20(IERC20 token, uint256 amount) {
        _hasFundsERC20(token, amount);
        _;
    }

    function _hasFundsERC20(IERC20 token, uint256 amount) internal view{
        uint256 bal = erc20Balances[token][msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);
    }

    modifier underUsdCap(uint256 weiAmount) {
        _underUsdCap(weiAmount);
        _;
    }

    function _underUsdCap(uint256 weiAmount) internal view {
        uint256 addUsd = _weiToUsd(weiAmount);
        if (BANKUSDCAP != 0) {
            uint256 newLiability = bankUsdLiabilities + addUsd;
            if (newLiability > BANKUSDCAP) {
                revert bankUsdCapExceeded(newLiability, BANKUSDCAP);
            }
        }
    }

    // =========================
    // ETH FUNCTIONS 
    // =========================

    function deposit()
        external
        payable
        nonZeroValue
        underTxCap
        underUsdCap(msg.value)
        countDeposit
        whenNotPaused
    {
        balances[msg.sender] += msg.value;
        unchecked { bankUsdLiabilities += _weiToUsd(msg.value); }
        emit depositDone(msg.sender, msg.value);
    }

    function withdrawal(uint256 value)
        external
        nonReentrant
        withinWithdrawCap(value)
        hasFunds(value)
        countWithdrawal
        whenNotPaused
    {
        _debit(msg.sender, value);
        uint256 subUsd = _weiToUsd(value);
        unchecked { bankUsdLiabilities = subUsd > bankUsdLiabilities ? 0 : bankUsdLiabilities - subUsd; }
        (bool ok, ) = msg.sender.call{value: value}("");
        if (!ok) revert transactionFailed();
        emit withdrawalDone(msg.sender, value);
    }

    function bankStats() external view returns (uint256 totalDeposits, uint256 totalWithdrawals) {
        return (transactionsCounter, withdrawalCounter);
    }

    function _debit(address user, uint256 amount) private {
        uint256 bal = balances[user];
        if (amount > bal) revert insufficientBalance(bal, amount);
        unchecked { balances[user] = bal - amount; }
    }

    // =========================
    // ADMIN PAUSE
    // =========================

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // =========================
    // CHAINLINK HELPERS 
    // =========================

    function _getEthUsdPrice() internal view returns (uint256 price) {
        (, int256 answer,,,) = ETHUSDFEED.latestRoundData();
        if (answer <= 0) revert invalidPrice();

        price = uint256(answer);
    }

    function _weiToUsd(uint256 weiAmount) internal view returns (uint256 usdAmount) {
        uint256 price = _getEthUsdPrice();
        // price is in 8 decimals from Chainlink, need to scale to 18 decimals
        // weiAmount is in 18 decimals, result should be in 18 decimals USD
        usdAmount = (weiAmount * price * 1e10) / 1e18;
    }

    /// @dev Acredita USDC en el balance del usuario
    function _credit(address user, uint256 amount) internal {
        erc20Balances[USDC][user] += amount;
    }

    // =========================
    // ERC-20 DEPOSIT/WITHDRAW 
    // =========================

    /// @dev Mantiene la firma original. Si token == KGLD → deposita KGLD.
    ///      Si token != KGLD → swapea a USDC (vía Uniswap V2) y acredita USDC.
    function depositERC20(IERC20 token, uint256 amount)
        external
        whenNotPaused
        underTxCap
        countDeposit
    {
        if (amount == 0) revert zeroDeposit();

        if (address(token) == address(KGLD)) {
            // camino KGLD: igual que antes
            token.safeTransferFrom(msg.sender, address(this), amount);
            erc20Balances[token][msg.sender] += amount;
            emit erc20DepositDone(address(token), msg.sender, amount);
            return;
        }

        // camino genérico: token → USDC
        uint256 usdcOut = _swapInToUsdc(token, amount);
        // Normalize USDC (6 decimals) to internal 18 decimals
        erc20Balances[USDC][msg.sender] += usdcOut * 1e12;

        // Informamos depósito sobre el token original por compatibilidad de eventos
        emit erc20DepositDone(address(token), msg.sender, amount);
    }

    /// @dev Solo permite retirar USDC o KGLD.
    function withdrawalERC20(IERC20 token, uint256 amount)
        external
        whenNotPaused
        hasFundsERC20(token, amount)
        nonReentrant
        countWithdrawal
    {
        if (address(token) != address(USDC) && address(token) != address(KGLD)) {
            revert OnlyUSDCOrKGLD();
        }
        unchecked { erc20Balances[token][msg.sender] = erc20Balances[token][msg.sender] - amount; }
        
        // Convert internal 18 decimals to token's native decimals if USDC
        uint256 transferAmount = amount;
        if (address(token) == address(USDC)) {
            transferAmount = amount / 1e12; // Convert 18 decimals to 6 decimals
        }
        
        token.safeTransfer(msg.sender, transferAmount);
        emit erc20WithdrawalDone(address(token), msg.sender, amount);
    }

    // =========================
    // INTERNAL SWAP LOGIC
    // =========================

    /// @dev Transfiere `amount` del `tokenIn` desde el usuario, aprueba al router,
    ///      elige path [tokenIn, USDC] o fallback [tokenIn, WETH, USDC], calcula minOut≈1% slippage
    ///      y ejecuta swapExactTokensForTokens. Devuelve USDC recibido.
    function _swapInToUsdc(IERC20 tokenIn, uint256 amount)
    internal
    returns (uint256 usdcReceived)
{
    if (amount == 0) revert ZeroAmount();

    // CEI: primero traer los tokens y aprobar router
    tokenIn.safeTransferFrom(msg.sender, address(this), amount);

    // Con V2 es más seguro resetear y volver a aprobar para este monto
    tokenIn.forceApprove(address(UNISWAPV2ROUTER), 0);
    tokenIn.forceApprove(address(UNISWAPV2ROUTER), amount);

    // -------- paths en memoria --------
    // tokenIn -> USDC
    address[] memory pathDirect = new address[](2);
    pathDirect[0] = address(tokenIn);
    pathDirect[1] = address(USDC);

    // tokenIn -> WETH -> USDC
    address[] memory pathViaWETH = new address[](3);
    pathViaWETH[0] = address(tokenIn);
    pathViaWETH[1] = UNISWAPV2ROUTER.WETH();
    pathViaWETH[2] = address(USDC);
    // ----------------------------------

    // Intento directo
    uint256 minOutDirect = 0;
    bool directOk = false;
    try UNISWAPV2ROUTER.getAmountsOut(amount, pathDirect) returns (uint[] memory amts) {
        if (amts.length == 2 && amts[1] > 0) {
            minOutDirect = (amts[1] * 99) / 100; // 1% slippage
            directOk = true;
        }
    } catch { directOk = false; }

    if (directOk) {
        uint[] memory out = UNISWAPV2ROUTER.swapExactTokensForTokens(
            amount,
            minOutDirect,
            pathDirect,
            address(this),
            block.timestamp
        );
        if (out.length != 2 || out[1] == 0) revert SwapFailed();
        return out[1];
    }

    // Fallback vía WETH
    uint256 minOutVia = 0;
    try UNISWAPV2ROUTER.getAmountsOut(amount, pathViaWETH) returns (uint[] memory amts2) {
        if (amts2.length == 3 && amts2[2] > 0) {
            minOutVia = (amts2[2] * 99) / 100; // 1% slippage
        } else {
            revert SwapFailed();
        }
    } catch {
        revert SwapFailed();
    }

    uint[] memory out2 = UNISWAPV2ROUTER.swapExactTokensForTokens(
        amount,
        minOutVia,
        pathViaWETH,
        address(this),
        block.timestamp
    );
    if (out2.length != 3 || out2[2] == 0) revert SwapFailed();
    return out2[2];
    }


    function depositAnyToken(
        address tokenIn,
        uint256 amountIn,
        uint256 minUsdcOut,
        uint256 deadline
    ) external nonReentrant {
        require(amountIn > 0, "amount=0");

        if (tokenIn == address(USDC)) {
            USDC.safeTransferFrom(msg.sender, address(this), amountIn);
            _credit(msg.sender, amountIn); // contabilidad en USDC
            emit Deposited(msg.sender, address(USDC), amountIn, amountIn);
            return;
        }

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(address(ROUTER), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = address(USDC);

        uint[] memory amounts = ROUTER.swapExactTokensForTokens(
            amountIn,
            minUsdcOut,
            path,
            address(this),
            deadline
        );
        uint usdcGot = amounts[amounts.length - 1];
        _credit(msg.sender, usdcGot);
        emit Deposited(msg.sender, tokenIn, amountIn, usdcGot);
    }

    function depositNative(uint minUsdcOut, uint deadline) external payable nonReentrant {
        require(msg.value > 0, "value=0");
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(USDC);

        uint[] memory amounts = ROUTER.swapExactETHForTokens{value: msg.value}(
            minUsdcOut,
            path,
            address(this),
            deadline
        );
        uint usdcGot = amounts[amounts.length - 1];
        _credit(msg.sender, usdcGot);
        emit Deposited(msg.sender, address(0), msg.value, usdcGot);
    }




}
