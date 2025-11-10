//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/**
 * @title KipuBank
 * @author KipuBank Team
 * @notice A decentralized banking contract that handles ETH deposits, ERC20 token swaps, and USD liability tracking
 * @dev This contract integrates with Chainlink price feeds and Uniswap V2 for token swapping functionality
 */
contract KipuBank is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Mapping of ERC20 token balances for each user
    /// @dev token => user => amount structure for tracking individual token balances
    mapping(IERC20 token => mapping(address user => uint256 amount)) public erc20Balances;

    /// @notice Mapping of ETH balances for each user
    /// @dev Tracks native ETH deposits per user address
    mapping(address client => uint256 amount) public balances;

    /// @notice Maximum withdrawal amount allowed per transaction (in wei)
    uint256 public immutable WITHDRAW_MAX;
    
    /// @notice Maximum number of deposit transactions allowed
    uint256 public immutable BANKCAP;

    /// @notice Counter for total number of deposit transactions
    uint256 public transactionsCounter;
    
    /// @notice Counter for total number of withdrawal transactions
    uint256 public withdrawalCounter;

    /// @notice Chainlink ETH/USD price feed aggregator interface
    AggregatorV3Interface public immutable ETHUSDFEED;
    
    /// @notice Maximum USD liability cap for the bank (0 = unlimited)
    uint256 public immutable BANKUSDCAP;
    
    /// @notice Current total USD liabilities of the bank
    uint256 public bankUsdLiabilities;

    /// @notice USDC token contract (primary stable token for swaps)
    IERC20 public immutable USDC;
    
    /// @notice KGLD token contract (exempt from automatic swapping)
    IERC20 public immutable KGLD;
    
    /// @notice Uniswap V2 Router for token swapping operations
    IUniswapV2Router02 public immutable UNISWAPV2ROUTER;
    
    /// @notice Alias for UNISWAPV2ROUTER for compatibility
    IUniswapV2Router02 public immutable ROUTER;
    
    /// @notice Wrapped ETH contract address
    address public immutable WETH;

    /// @notice Emitted when a user deposits ETH
    /// @param client The address of the depositor
    /// @param amount The amount of ETH deposited in wei
    event depositDone(address client, uint256 amount);
    
    /// @notice Emitted when a user withdraws ETH
    /// @param client The address of the withdrawer
    /// @param amount The amount of ETH withdrawn in wei
    event withdrawalDone(address client, uint256 amount);

    /// @notice Emitted when a user deposits ERC20 tokens
    /// @param token The address of the deposited token
    /// @param client The address of the depositor
    /// @param amount The amount of tokens deposited
    event erc20DepositDone(address indexed token, address indexed client, uint256 amount);
    
    /// @notice Emitted when a user withdraws ERC20 tokens
    /// @param token The address of the withdrawn token
    /// @param client The address of the withdrawer
    /// @param amount The amount of tokens withdrawn
    event erc20WithdrawalDone(address indexed token, address indexed client, uint256 amount);
    
    /// @notice Emitted when a user deposits any token and receives USDC
    /// @param user The address of the depositor
    /// @param token The address of the input token
    /// @param amountIn The amount of input tokens
    /// @param usdcOut The amount of USDC received
    event Deposited(address indexed user, address indexed token, uint256 amountIn, uint256 usdcOut);

    /// @dev Transaction execution failed
    error transactionFailed();
    
    /// @dev Insufficient balance for the requested operation
    /// @param have Current balance available
    /// @param need Required balance for the operation
    error insufficientBalance(uint256 have, uint256 need);
    
    /// @dev Requested amount exceeds the allowed cap
    /// @param requested Amount requested by user
    /// @param cap Maximum allowed amount
    error capExceeded(uint256 requested, uint256 cap);
    
    /// @dev Unauthorized access attempt
    /// @param thief Address attempting unauthorized access
    /// @param victim Target address of unauthorized access
    error wrongUser(address thief, address victim);
    
    /// @dev Maximum number of transactions limit exceeded
    /// @param transactions Current transaction count
    /// @param limit Maximum allowed transactions
    error maxTransactionsLimit(uint256 transactions, uint256 limit);
    
    /// @dev Attempted deposit with zero value
    error zeroDeposit();
    
    /// @dev Constructor called with zero withdrawal cap
    error noCapWei();
    
    /// @dev Constructor called with zero transaction limit
    error noTransactions();
    
    /// @dev Reentrancy attack attempt detected
    error reentrancy();
    
    /// @dev Invalid or negative price from Chainlink oracle
    error invalidPrice();
    
    /// @dev Bank USD liability cap would be exceeded
    /// @param newLiability Total liability after operation
    /// @param cap Maximum allowed USD liability
    error bankUsdCapExceeded(uint256 newLiability, uint256 cap);

    /// @dev Only USDC or KGLD tokens are allowed for withdrawal
    error OnlyUSDCOrKGLD();
    
    /// @dev Token swap operation failed
    error SwapFailed();
    
    /// @dev Zero amount provided for operation
    error ZeroAmount();

    /**
     * @notice Initializes the KipuBank contract with required parameters
     * @param initialOwner The address that will own the contract
     * @param capWei Maximum withdrawal amount per transaction in wei
     * @param maxTransactions Maximum number of deposit transactions allowed
     * @param priceFeed Chainlink ETH/USD price feed aggregator (8 decimals)
     * @param bankUsdCap_ USD liability cap for ETH deposits (0 = unlimited)
     * @param usdc_ Address of the USDC token contract
     * @param kgld_ Address of the KGLD token contract (exempt from swapping)
     * @param router_ Address of the Uniswap V2 Router contract
     */
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
        ROUTER = router_;
        WETH = router_.WETH();
    }

    /**
     * @notice Ensures the transaction includes a non-zero ETH value
     * @dev Reverts if msg.value is zero
     */
    modifier nonZeroValue() {
        _nonZeroValue();
        _;
    }

    /**
     * @dev Internal function to check for non-zero value
     */
    function _nonZeroValue() internal {
        if (msg.value == 0) revert zeroDeposit();
    }

    /**
     * @notice Ensures the transaction count is under the bank cap
     * @dev Reverts if current transactions equal or exceed BANKCAP
     */
    modifier underTxCap() {
        _underTxCap();
        _;
    }

    /**
     * @dev Internal function to check transaction count limit
     */
    function _underTxCap() internal view {
        uint256 currentCounter = transactionsCounter;
        if (currentCounter >= BANKCAP) {
            revert maxTransactionsLimit(currentCounter, BANKCAP);
        }
    }

    /**
     * @notice Increments the deposit counter after function execution
     * @dev Executes function first, then increments transaction counter
     */
    modifier countDeposit() {
        _;
        _countDeposit();
    }

    /**
     * @dev Internal function to increment transaction counter
     */
    function _countDeposit() internal {
        transactionsCounter += 1;
    }

    /// @dev Reentrancy guard state variable
    uint256 private _locked;

    /**
     * @notice Prevents reentrancy attacks
     * @dev Uses a simple lock mechanism to prevent recursive calls
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /**
     * @dev Sets the reentrancy lock before function execution
     */
    function _nonReentrantBefore() internal {
        if (_locked == 1) revert reentrancy();
        _locked = 1;
    }

    /**
     * @dev Releases the reentrancy lock after function execution
     */
    function _nonReentrantAfter() internal {
        _locked = 0;
    }

    /**
     * @notice Increments the withdrawal counter after function execution
     * @dev Executes function first, then increments withdrawal counter
     */
    modifier countWithdrawal() {
        _;
        _countWithdrawal();
    }

    /**
     * @dev Internal function to increment withdrawal counter
     */
    function _countWithdrawal() internal {
        withdrawalCounter += 1;
    }

    /**
     * @notice Ensures user has sufficient ETH balance for the operation
     * @param amount The amount to check against user's balance
     * @dev Reverts if user's balance is insufficient
     */
    modifier hasFunds(uint256 amount) {
        _hasFunds(amount);
        _;
    }

    /**
     * @dev Internal function to check ETH balance sufficiency
     */
    function _hasFunds(uint256 amount) internal view{
        uint256 bal = balances[msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);
    }

    /**
     * @notice Ensures withdrawal amount is within the allowed cap
     * @param amount The amount to check against withdrawal cap
     * @dev Reverts if amount exceeds WITHDRAW_MAX
     */
    modifier withinWithdrawCap(uint256 amount) {
        _withinWithdrawCap(amount);
        _;
    }

    /**
     * @dev Internal function to check withdrawal cap compliance
     */
    function _withinWithdrawCap(uint256 amount) internal view{
        if (amount > WITHDRAW_MAX) revert capExceeded(amount, WITHDRAW_MAX);
    }

    /**
     * @notice Ensures user has sufficient ERC20 token balance
     * @param token The ERC20 token to check
     * @param amount The amount to check against user's token balance
     * @dev Reverts if user's token balance is insufficient
     */
    modifier hasFundsERC20(IERC20 token, uint256 amount) {
        _hasFundsERC20(token, amount);
        _;
    }

    /**
     * @dev Internal function to check ERC20 balance sufficiency
     */
    function _hasFundsERC20(IERC20 token, uint256 amount) internal view{
        uint256 bal = erc20Balances[token][msg.sender];
        if (amount > bal) revert insufficientBalance(bal, amount);
    }

    /**
     * @notice Ensures the operation won't exceed the bank's USD liability cap
     * @param weiAmount The ETH amount in wei to convert and check
     * @dev Reverts if adding this USD value would exceed BANKUSDCAP
     */
    modifier underUsdCap(uint256 weiAmount) {
        _underUsdCap(weiAmount);
        _;
    }

    /**
     * @dev Internal function to check USD liability cap compliance
     */
    function _underUsdCap(uint256 weiAmount) internal view {
        if (BANKUSDCAP != 0) {
            uint256 addUsd = _weiToUsd(weiAmount);
            uint256 currentLiabilities = bankUsdLiabilities;
            uint256 newLiability = currentLiabilities + addUsd;
            if (newLiability > BANKUSDCAP) {
                revert bankUsdCapExceeded(newLiability, BANKUSDCAP);
            }
        }
    }

    /**
     * @notice Allows users to deposit ETH into the bank
     * @dev Requires non-zero value, checks transaction cap and USD cap, increments counters
     * @dev Updates user's ETH balance and bank's USD liabilities
     */
    function deposit()
        external
        payable
        nonZeroValue
        underTxCap
        underUsdCap(msg.value)
        countDeposit
        whenNotPaused
    {
        uint256 currentBalance = balances[msg.sender];
        balances[msg.sender] = currentBalance + msg.value;
        uint256 currentLiabilities = bankUsdLiabilities;
        unchecked { bankUsdLiabilities = currentLiabilities + _weiToUsd(msg.value); }
        
        emit depositDone(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to withdraw ETH from their balance
     * @param value The amount of ETH to withdraw in wei
     * @dev Checks withdrawal cap, sufficient funds, prevents reentrancy, updates counters
     * @dev Reduces user's balance and bank's USD liabilities before transferring ETH
     */
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
        uint256 currentLiabilities = bankUsdLiabilities;
        unchecked { bankUsdLiabilities = subUsd > currentLiabilities ? 0 : currentLiabilities - subUsd; }
        
        (bool ok, ) = msg.sender.call{value: value}("");
        if (!ok) revert transactionFailed();
        emit withdrawalDone(msg.sender, value);
    }

    /**
     * @notice Returns the current statistics of the bank
     * @return totalDeposits The total number of deposit transactions
     * @return totalWithdrawals The total number of withdrawal transactions
     */
    function bankStats() external view returns (uint256 totalDeposits, uint256 totalWithdrawals) {
        return (transactionsCounter, withdrawalCounter);
    }

    /**
     * @dev Internal function to debit user's ETH balance
     * @param user The address of the user to debit
     * @param amount The amount to debit from user's balance
     */
    function _debit(address user, uint256 amount) private {
        uint256 bal = balances[user];
        if (amount > bal) revert insufficientBalance(bal, amount);
        unchecked { balances[user] = bal - amount; }
    }

    /**
     * @notice Pauses the contract, disabling deposits and withdrawals
     * @dev Only callable by the contract owner
     */
    function pause() external onlyOwner { _pause(); }
    
    /**
     * @notice Unpauses the contract, re-enabling deposits and withdrawals
     * @dev Only callable by the contract owner
     */
    function unpause() external onlyOwner { _unpause(); }

    /**
     * @dev Internal function to get the current ETH/USD price from Chainlink
     * @return price Current ETH price in USD with 8 decimals
     */
    function _getEthUsdPrice() internal view returns (uint256 price) {
        (, int256 answer,,,) = ETHUSDFEED.latestRoundData();
        if (answer <= 0) revert invalidPrice();
        price = uint256(answer);
    }

    /**
     * @dev Converts ETH amount (wei) to USD value using Chainlink price feed
     * @param weiAmount Amount of ETH in wei (18 decimals)
     * @return usdAmount Equivalent USD amount in 18 decimals
     */
    function _weiToUsd(uint256 weiAmount) internal view returns (uint256 usdAmount) {
        uint256 price = _getEthUsdPrice();
        usdAmount = (weiAmount * price * 1e10) / 1e18;
    }

    /**
     * @dev Internal function to credit USDC to user's balance
     * @param user The address to credit USDC to
     * @param amount The amount of USDC to credit (in contract's internal accounting)
     */
    function _credit(address user, uint256 amount) internal {
        uint256 currentBalance = erc20Balances[USDC][user];
        erc20Balances[USDC][user] = currentBalance + amount;
    }

    /**
     * @notice Deposits ERC20 tokens into the bank
     * @param token The ERC20 token contract to deposit
     * @param amount The amount of tokens to deposit
     * @dev If token is KGLD, deposits directly. Otherwise, swaps to USDC via Uniswap
     * @dev Updates transaction counter and enforces transaction cap
     */
    function depositERC20(IERC20 token, uint256 amount)
        external
        whenNotPaused
        underTxCap
        countDeposit
    {
        if (amount == 0) revert zeroDeposit();

        if (address(token) == address(KGLD)) {
            token.safeTransferFrom(msg.sender, address(this), amount);
            uint256 currentBalance = erc20Balances[token][msg.sender];
            erc20Balances[token][msg.sender] = currentBalance + amount;
            emit erc20DepositDone(address(token), msg.sender, amount);
            return;
        }

        uint256 usdcOut = _swapInToUsdc(token, amount);
        uint256 currentUsdcBalance = erc20Balances[USDC][msg.sender];
        erc20Balances[USDC][msg.sender] = currentUsdcBalance + (usdcOut * 1e12);

        emit erc20DepositDone(address(token), msg.sender, amount);
    }

    /**
     * @notice Withdraws ERC20 tokens from the user's balance
     * @param token The ERC20 token contract to withdraw (must be USDC or KGLD)
     * @param amount The amount of tokens to withdraw
     * @dev Only USDC and KGLD withdrawals are permitted
     * @dev Converts internal 18-decimal accounting to token's native decimals for USDC
     */
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
        uint256 currentBalance = erc20Balances[token][msg.sender];
        unchecked { erc20Balances[token][msg.sender] = currentBalance - amount; }
        uint256 transferAmount = amount;
        if (address(token) == address(USDC)) {
            transferAmount = amount / 1e12;
        }
        token.safeTransfer(msg.sender, transferAmount);
        emit erc20WithdrawalDone(address(token), msg.sender, amount);
    }

    /**
     * @dev Internal function to swap any ERC20 token to USDC via Uniswap V2
     * @param tokenIn The input ERC20 token to swap
     * @param amount The amount of input tokens to swap
     * @return usdcReceived The amount of USDC received from the swap
     * @dev Tries direct path first, then fallback via WETH. Applies 1% slippage protection
     */
    function _swapInToUsdc(IERC20 tokenIn, uint256 amount)
    internal
    returns (uint256 usdcReceived)
{
    if (amount == 0) revert ZeroAmount();
    tokenIn.safeTransferFrom(msg.sender, address(this), amount);
    tokenIn.forceApprove(address(UNISWAPV2ROUTER), 0);
    tokenIn.forceApprove(address(UNISWAPV2ROUTER), amount);
    address[] memory pathDirect = new address[](2);
    pathDirect[0] = address(tokenIn);
    pathDirect[1] = address(USDC);
    address[] memory pathViaWETH = new address[](3);
    pathViaWETH[0] = address(tokenIn);
    pathViaWETH[1] = UNISWAPV2ROUTER.WETH();
    pathViaWETH[2] = address(USDC);
    

   
    uint256 minOutDirect = 0;
    bool directOk = false;
    try UNISWAPV2ROUTER.getAmountsOut(amount, pathDirect) returns (uint[] memory amts) {
        if (amts.length == 2 && amts[1] > 0) {
            minOutDirect = (amts[1] * 99) / 100; 
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

    
    uint256 minOutVia = 0;
    try UNISWAPV2ROUTER.getAmountsOut(amount, pathViaWETH) returns (uint[] memory amts2) {
        if (amts2.length == 3 && amts2[2] > 0) {
            minOutVia = (amts2[2] * 99) / 100;
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

    /**
     * @notice Deposits any ERC20 token and receives USDC in return
     * @param tokenIn Address of the token to deposit
     * @param amountIn Amount of tokens to deposit
     * @param minUsdcOut Minimum USDC amount to receive (slippage protection)
     * @param deadline Transaction deadline for the swap
     * @dev If tokenIn is USDC, deposits directly. Otherwise swaps via Uniswap
     */
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

    /**
     * @notice Deposits native ETH and receives USDC in return
     * @param minUsdcOut Minimum USDC amount to receive (slippage protection)
     * @param deadline Transaction deadline for the swap
     * @dev Swaps ETH to USDC via Uniswap V2 and credits user's USDC balance
     */
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
