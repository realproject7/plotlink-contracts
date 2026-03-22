// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// ============ Uniswap V4 Interfaces ============
interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IAllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IHooks {}

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    bytes hookData;
}

struct ExactOutputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountOut;
    uint128 amountInMaximum;
    bytes hookData;
}

struct QuoteExactSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 exactAmount;
    bytes hookData;
}

interface IV4Quoter {
    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint256 gasEstimate);

    function quoteExactOutputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountIn, uint256 gasEstimate);
}

// ============ Mint Club V2 Interfaces ============
interface IMCV2_BondFull {
    function mint(address token, uint256 tokensToMint, uint256 maxReserveAmount, address receiver)
        external
        returns (uint256);

    function getReserveForToken(address token, uint256 tokensToMint)
        external
        view
        returns (uint256 reserveAmount, uint256 royalty);
}

interface IMCV2_BondPeripheryFull {
    function mintWithReserveAmount(address token, uint256 reserveAmount, uint256 minTokensToMint, address receiver)
        external
        returns (uint256 tokensMinted);

    function getTokensForReserve(address tokenAddress, uint256 reserveAmount, bool useCeilDivision)
        external
        view
        returns (uint256 tokensToMint, address reserveAddress);
}

// ============ Constants ============
library Commands {
    uint256 constant SWEEP = 0x04;
    uint256 constant V4_SWAP = 0x10;
}

library Actions {
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 constant SWAP_EXACT_OUT_SINGLE = 0x08;
    uint256 constant SETTLE_ALL = 0x0c;
    uint256 constant TAKE = 0x0e;
}

library ActionConstants {
    uint256 constant OPEN_DELTA = 0;
}
