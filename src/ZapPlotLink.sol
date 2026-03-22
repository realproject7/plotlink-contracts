// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IMCV2_Bond} from "./interfaces/IMCV2_Bond.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title ZapPlotLink — One-click buy: swap ETH via Uniswap V4, then mint storyline tokens on MCV2 bonding curve
/// @notice Accepts ETH, swaps to PLOT token via Uniswap V4, then mints storyline tokens via MCV2_Bond.
///         Supports exact-output (mint) and exact-input (mintReverse) patterns.
/// @dev Owner can update the plot token address via setPlotToken().
contract ZapPlotLink is IUnlockCallback {
    // --- Errors ---
    error OnlyOwner();
    error OnlyPoolManager();
    error ZeroAddress();
    error InsufficientOutput();
    error SwapFailed();
    error Reentrancy();

    // --- Events ---
    event PlotTokenUpdated(address indexed oldToken, address indexed newToken);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // --- Immutables ---
    IPoolManager public immutable poolManager;
    IMCV2_Bond public immutable bond;
    IMCV2_BondPeriphery public immutable bondPeriphery;
    address public immutable weth;

    // --- State ---
    address public owner;
    address public plotToken;
    PoolKey public poolKey;
    uint256 private _locked = 1;

    // --- Transient callback data ---
    struct SwapCallbackData {
        bool zeroForOne;
        int256 amountSpecified;
    }

    /// @param _poolManager Uniswap V4 PoolManager
    /// @param _bond MCV2_Bond bonding curve contract
    /// @param _bondPeriphery MCV2_BondPeriphery for mintWithReserveAmount
    /// @param _weth WETH address
    /// @param _plotToken Initial PLOT token address (reserve token for bonding curves)
    /// @param _poolKey The Uniswap V4 pool key for PLOT/WETH
    constructor(
        address _poolManager,
        address _bond,
        address _bondPeriphery,
        address _weth,
        address _plotToken,
        PoolKey memory _poolKey
    ) {
        if (
            _poolManager == address(0) || _bond == address(0) || _bondPeriphery == address(0) || _weth == address(0)
                || _plotToken == address(0)
        ) {
            revert ZeroAddress();
        }
        poolManager = IPoolManager(_poolManager);
        bond = IMCV2_Bond(_bond);
        bondPeriphery = IMCV2_BondPeriphery(_bondPeriphery);
        weth = _weth;
        plotToken = _plotToken;
        poolKey = _poolKey;
        owner = msg.sender;

        // Pre-approve PLOT token to Bond and BondPeriphery for minting
        IERC20(_plotToken).approve(_bond, type(uint256).max);
        IERC20(_plotToken).approve(_bondPeriphery, type(uint256).max);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked == 2) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ==================== Owner Functions ====================

    /// @notice Update the plot token address (e.g., when migrating from testnet WETH to real PLOT)
    /// @param newPlotToken The new plot token address
    function setPlotToken(address newPlotToken) external onlyOwner {
        if (newPlotToken == address(0)) revert ZeroAddress();
        address old = plotToken;

        // Revoke old approvals
        IERC20(old).approve(address(bond), 0);
        IERC20(old).approve(address(bondPeriphery), 0);

        plotToken = newPlotToken;

        // Approve new token to Bond and BondPeriphery
        IERC20(newPlotToken).approve(address(bond), type(uint256).max);
        IERC20(newPlotToken).approve(address(bondPeriphery), type(uint256).max);

        emit PlotTokenUpdated(old, newPlotToken);
    }

    /// @notice Update the pool key (e.g., when pool changes)
    function setPoolKey(PoolKey calldata newPoolKey) external onlyOwner {
        poolKey = newPoolKey;
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /// @notice Rescue stuck ETH
    function rescueETH(address payable to) external onlyOwner {
        (bool ok,) = to.call{value: address(this).balance}("");
        require(ok);
    }

    // ==================== Mint Functions ====================

    /// @notice Exact output: swap ETH → PLOT, then mint exact `tokensToMint` storyline tokens
    /// @param storylineToken The storyline token to mint on the bonding curve
    /// @param tokensToMint Exact number of storyline tokens desired
    /// @param receiver Address to receive minted tokens
    /// @return reserveUsed Amount of PLOT used for minting
    function mint(address storylineToken, uint256 tokensToMint, address receiver)
        external
        payable
        nonReentrant
        returns (uint256 reserveUsed)
    {
        // 1. Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // 2. Swap WETH → PLOT via Uniswap V4
        uint256 plotReceived = _swapExactInput(msg.value);

        // 3. Mint storyline tokens on bonding curve
        reserveUsed = bond.mint(storylineToken, tokensToMint, plotReceived, receiver);

        // 4. Refund excess PLOT as ETH
        _refundExcessPlot();
    }

    /// @notice Exact input: swap all sent ETH → PLOT, then mint as many storyline tokens as possible
    /// @param storylineToken The storyline token to mint
    /// @param minTokensOut Minimum acceptable storyline tokens (slippage protection)
    /// @param receiver Address to receive minted tokens
    /// @return tokensMinted Number of storyline tokens minted
    function mintReverse(address storylineToken, uint256 minTokensOut, address receiver)
        external
        payable
        nonReentrant
        returns (uint256 tokensMinted)
    {
        // 1. Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // 2. Swap all WETH → PLOT via Uniswap V4
        uint256 plotReceived = _swapExactInput(msg.value);

        // 3. Mint max storyline tokens using BondPeriphery.mintWithReserveAmount
        tokensMinted = bondPeriphery.mintWithReserveAmount(storylineToken, plotReceived, 0, receiver);

        if (tokensMinted < minTokensOut) revert InsufficientOutput();
    }

    // ==================== View / Estimate Functions ====================

    /// @notice Get the PLOT reserve cost to mint `tokensToMint` storyline tokens (bonding curve only)
    /// @dev Frontend should convert PLOT→ETH via Uniswap V4 Quoter off-chain for the full ETH estimate.
    ///      Call Quoter.quoteExactOutput(poolKey, plotRequired, ...) to get the ETH amount.
    /// @param storylineToken The storyline token
    /// @param tokensToMint Number of tokens to mint
    /// @return plotRequired PLOT tokens needed (reserve + royalty)
    function estimateMintCostInPlot(address storylineToken, uint256 tokensToMint)
        external
        view
        returns (uint256 plotRequired)
    {
        (uint256 reserveAmount, uint256 royalty) = bond.getReserveForToken(storylineToken, tokensToMint);
        plotRequired = reserveAmount + royalty;
    }

    /// @notice Estimate how many storyline tokens can be minted with `plotAmount` of PLOT
    /// @dev Frontend should first convert ETH→PLOT via Uniswap V4 Quoter off-chain,
    ///      then pass the quoted PLOT amount here.
    /// @param storylineToken The storyline token
    /// @param plotAmount Amount of PLOT tokens available for minting
    /// @return tokensOut Estimated storyline tokens receivable
    function estimateMintReverseFromPlot(address storylineToken, uint256 plotAmount)
        external
        view
        returns (uint256 tokensOut)
    {
        (tokensOut,) = bondPeriphery.getTokensForReserve(storylineToken, plotAmount);
    }

    /// @notice Get the current PLOT token address
    function getPlotToken() external view returns (address) {
        return plotToken;
    }

    /// @notice Get the current pool key
    function getPoolKey() external view returns (PoolKey memory) {
        return poolKey;
    }

    // ==================== Internal Swap Functions ====================

    /// @dev Swap exact WETH input → PLOT output via Uniswap V4
    function _swapExactInput(uint256 wethAmount) internal returns (uint256 plotReceived) {
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == weth;

        bytes memory callbackData =
            abi.encode(SwapCallbackData({zeroForOne: zeroForOne, amountSpecified: -int256(wethAmount)}));

        bytes memory result = poolManager.unlock(callbackData);
        (int256 delta0, int256 delta1) = abi.decode(result, (int256, int256));

        plotReceived = uint256(zeroForOne ? delta1 : delta0);
        if (plotReceived == 0) revert SwapFailed();
    }

    /// @dev Swap exact PLOT input → WETH output (for refunding excess)
    function _swapExactInputPlotToWeth(uint256 plotAmount) internal returns (uint256 wethReceived) {
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == plotToken;

        bytes memory callbackData =
            abi.encode(SwapCallbackData({zeroForOne: zeroForOne, amountSpecified: -int256(plotAmount)}));

        bytes memory result = poolManager.unlock(callbackData);
        (int256 delta0, int256 delta1) = abi.decode(result, (int256, int256));

        wethReceived = uint256(zeroForOne ? delta1 : delta0);
    }

    /// @dev Refund any excess PLOT tokens back to msg.sender as ETH
    function _refundExcessPlot() internal {
        uint256 plotRemaining = IERC20(plotToken).balanceOf(address(this));
        if (plotRemaining > 0) {
            uint256 wethBack = _swapExactInputPlotToWeth(plotRemaining);
            if (wethBack > 0) {
                IWETH(weth).withdraw(wethBack);
                (bool ok,) = msg.sender.call{value: wethBack}("");
                require(ok);
            }
        }
    }

    // ==================== Uniswap V4 Callback ====================

    /// @notice Called by PoolManager during unlock
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));

        uint160 sqrtPriceLimitX96 = swapData.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        BalanceDelta delta = poolManager.swap(
            poolKey,
            IPoolManager.SwapParams({
                zeroForOne: swapData.zeroForOne,
                amountSpecified: swapData.amountSpecified,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            ""
        );

        // Settle: pay input token to PoolManager
        // ERC-20 settlement requires: sync(currency) → transfer → settle()
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            poolManager.sync(poolKey.currency0);
            IERC20(Currency.unwrap(poolKey.currency0)).transfer(address(poolManager), uint128(-amount0));
            poolManager.settle();
        }
        if (amount1 < 0) {
            poolManager.sync(poolKey.currency1);
            IERC20(Currency.unwrap(poolKey.currency1)).transfer(address(poolManager), uint128(-amount1));
            poolManager.settle();
        }

        // Take: receive output tokens from PoolManager
        if (amount0 > 0) {
            poolManager.take(poolKey.currency0, address(this), uint128(amount0));
        }
        if (amount1 > 0) {
            poolManager.take(poolKey.currency1, address(this), uint128(amount1));
        }

        return abi.encode(amount0, amount1);
    }

    // ==================== Receive ETH ====================

    /// @dev Only accepts ETH from WETH unwrap. Not a general-purpose deposit.
    receive() external payable {
        require(msg.sender == weth);
    }
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IMCV2_BondPeriphery {
    function mintWithReserveAmount(address token, uint256 reserveAmount, uint256 minTokensToMint, address receiver)
        external
        returns (uint256 tokensMinted);
    function getTokensForReserve(address tokenAddress, uint256 reserveAmount)
        external
        view
        returns (uint256 tokensToMint, address reserveAddress);
}
