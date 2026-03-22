// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
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

    // --- Events ---
    event PlotTokenUpdated(address indexed oldToken, address indexed newToken);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // --- Immutables ---
    IPoolManager public immutable poolManager;
    IMCV2_Bond public immutable bond;
    address public immutable weth;

    // --- State ---
    address public owner;
    address public plotToken;
    PoolKey public poolKey;

    // --- Transient callback data ---
    struct SwapCallbackData {
        address payer;
        bool zeroForOne;
        int256 amountSpecified;
    }

    /// @param _poolManager Uniswap V4 PoolManager
    /// @param _bond MCV2_Bond bonding curve contract
    /// @param _weth WETH address
    /// @param _plotToken Initial PLOT token address (reserve token for bonding curves)
    /// @param _poolKey The Uniswap V4 pool key for PLOT/WETH
    constructor(address _poolManager, address _bond, address _weth, address _plotToken, PoolKey memory _poolKey) {
        if (_poolManager == address(0) || _bond == address(0) || _weth == address(0) || _plotToken == address(0)) {
            revert ZeroAddress();
        }
        poolManager = IPoolManager(_poolManager);
        bond = IMCV2_Bond(_bond);
        weth = _weth;
        plotToken = _plotToken;
        poolKey = _poolKey;
        owner = msg.sender;

        // Pre-approve PLOT token to Bond for minting
        IERC20(_plotToken).approve(_bond, type(uint256).max);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    // ==================== Owner Functions ====================

    /// @notice Update the plot token address (e.g., when migrating from testnet WETH to real PLOT)
    /// @param newPlotToken The new plot token address
    function setPlotToken(address newPlotToken) external onlyOwner {
        if (newPlotToken == address(0)) revert ZeroAddress();
        address old = plotToken;
        plotToken = newPlotToken;
        // Approve new token to Bond
        IERC20(newPlotToken).approve(address(bond), type(uint256).max);
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
        returns (uint256 reserveUsed)
    {
        // 1. Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // 2. Swap WETH → PLOT via Uniswap V4
        uint256 plotReceived = _swapExactInput(msg.value);

        // 3. Mint storyline tokens on bonding curve
        reserveUsed = bond.mint(storylineToken, tokensToMint, plotReceived, receiver);

        // 4. Refund excess PLOT
        uint256 plotRemaining = IERC20(plotToken).balanceOf(address(this));
        if (plotRemaining > 0) {
            // Swap remaining PLOT back to WETH and refund as ETH
            uint256 wethBack = _swapExactInput_PlotToWeth(plotRemaining);
            if (wethBack > 0) {
                IWETH(weth).withdraw(wethBack);
                (bool ok,) = msg.sender.call{value: wethBack}("");
                require(ok);
            }
        }
    }

    /// @notice Exact input: swap all sent ETH → PLOT, then mint as many storyline tokens as possible
    /// @param storylineToken The storyline token to mint
    /// @param minTokensOut Minimum acceptable storyline tokens (slippage protection)
    /// @param receiver Address to receive minted tokens
    /// @return tokensMinted Number of storyline tokens minted
    function mintReverse(address storylineToken, uint256 minTokensOut, address receiver)
        external
        payable
        returns (uint256 tokensMinted)
    {
        // 1. Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // 2. Swap all WETH → PLOT via Uniswap V4
        uint256 plotReceived = _swapExactInput(msg.value);

        // 3. Calculate how many storyline tokens we can mint with this PLOT amount
        // Use a binary search approach since MCV2_Bond doesn't have mintWithReserveAmount
        // For simplicity, mint with max reserve and let Bond handle it
        // We need to estimate tokens first
        tokensMinted = _mintWithReserve(storylineToken, plotReceived, receiver);

        if (tokensMinted < minTokensOut) revert InsufficientOutput();
    }

    // ==================== View / Estimate Functions ====================

    /// @notice Estimate how much ETH is needed to mint `tokensToMint` storyline tokens
    /// @param storylineToken The storyline token
    /// @param tokensToMint Number of tokens to mint
    /// @return ethRequired Estimated ETH needed (includes swap slippage buffer)
    function estimateMintCost(address storylineToken, uint256 tokensToMint)
        external
        view
        returns (uint256 ethRequired)
    {
        // Get reserve cost from bonding curve
        (uint256 reserveAmount, uint256 royalty) = bond.getReserveForToken(storylineToken, tokensToMint);
        uint256 totalPlot = reserveAmount + royalty;

        // Add 1% buffer for swap slippage
        ethRequired = (totalPlot * 101) / 100;
    }

    /// @notice Estimate how many storyline tokens can be minted with `ethAmount` of ETH
    /// @param storylineToken The storyline token
    /// @param ethAmount Amount of ETH to spend
    /// @return tokensOut Estimated storyline tokens receivable
    function estimateMintReverse(address storylineToken, uint256 ethAmount) external view returns (uint256 tokensOut) {
        // Approximate: assume 1:1 ETH→PLOT swap for estimation
        // In practice, the swap will have price impact
        // For a more accurate estimate, query the Uniswap V4 quoter off-chain
        (uint256 refund,) = bond.getRefundForTokens(storylineToken, 1e18);
        if (refund == 0) return 0;

        // Rough estimate: ethAmount / pricePerToken
        (uint256 reserveFor1Token,) = bond.getReserveForToken(storylineToken, 1e18);
        if (reserveFor1Token == 0) return 0;
        tokensOut = (ethAmount * 1e18) / reserveFor1Token;
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
        // Determine swap direction
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == weth;

        // Approve WETH to PoolManager for settlement
        IERC20(weth).approve(address(poolManager), wethAmount);

        bytes memory callbackData = abi.encode(
            SwapCallbackData({payer: address(this), zeroForOne: zeroForOne, amountSpecified: -int256(wethAmount)})
        );

        bytes memory result = poolManager.unlock(callbackData);
        int256 delta0;
        int256 delta1;
        (delta0, delta1) = abi.decode(result, (int256, int256));

        // The output amount is positive (tokens received)
        if (zeroForOne) {
            plotReceived = delta1 > 0 ? uint256(delta1) : 0;
        } else {
            plotReceived = delta0 > 0 ? uint256(delta0) : 0;
        }

        if (plotReceived == 0) revert SwapFailed();
    }

    /// @dev Swap exact PLOT input → WETH output (for refunding excess)
    function _swapExactInput_PlotToWeth(uint256 plotAmount) internal returns (uint256 wethReceived) {
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == plotToken;

        IERC20(plotToken).approve(address(poolManager), plotAmount);

        bytes memory callbackData = abi.encode(
            SwapCallbackData({payer: address(this), zeroForOne: zeroForOne, amountSpecified: -int256(plotAmount)})
        );

        bytes memory result = poolManager.unlock(callbackData);
        int256 delta0;
        int256 delta1;
        (delta0, delta1) = abi.decode(result, (int256, int256));

        if (zeroForOne) {
            wethReceived = delta1 > 0 ? uint256(delta1) : 0;
        } else {
            wethReceived = delta0 > 0 ? uint256(delta0) : 0;
        }
    }

    /// @dev Mint storyline tokens using available PLOT reserve
    function _mintWithReserve(address storylineToken, uint256 reserveAmount, address receiver)
        internal
        returns (uint256 tokensMinted)
    {
        // Binary search for max mintable tokens given reserve
        uint256 lo = 0;
        uint256 hi = reserveAmount * 1e18; // upper bound guess
        uint256 mid;

        // First try to get a rough upper bound
        for (uint256 i = 0; i < 20; i++) {
            (uint256 cost,) = bond.getReserveForToken(storylineToken, hi);
            if (cost <= reserveAmount) {
                hi = hi * 2;
            } else {
                break;
            }
        }

        // Binary search
        for (uint256 i = 0; i < 40; i++) {
            mid = (lo + hi) / 2;
            if (mid == lo) break;

            (uint256 cost,) = bond.getReserveForToken(storylineToken, mid);
            if (cost <= reserveAmount) {
                lo = mid;
            } else {
                hi = mid;
            }
        }

        if (lo > 0) {
            bond.mint(storylineToken, lo, reserveAmount, receiver);
            tokensMinted = lo;
        }
    }

    // ==================== Uniswap V4 Callback ====================

    /// @notice Called by PoolManager during unlock
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));

        // Execute swap
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
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // Negative delta = tokens owed to pool (input), positive = tokens owed to us (output)
        if (amount0 < 0) {
            address token0 = Currency.unwrap(poolKey.currency0);
            IERC20(token0).transfer(address(poolManager), uint128(-amount0));
            poolManager.settle();
        }
        if (amount1 < 0) {
            address token1 = Currency.unwrap(poolKey.currency1);
            IERC20(token1).transfer(address(poolManager), uint128(-amount1));
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

    receive() external payable {}
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}
