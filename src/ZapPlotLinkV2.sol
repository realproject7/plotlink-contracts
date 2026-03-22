// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IUniversalRouter,
    IAllowanceTransfer,
    IHooks,
    PoolKey,
    ExactInputSingleParams,
    ExactOutputSingleParams,
    QuoteExactSingleParams,
    IV4Quoter,
    IMCV2_BondFull,
    IMCV2_BondPeripheryFull,
    Commands,
    Actions,
    ActionConstants
} from "./interfaces/IZapInterfaces.sol";

/// @title ZapPlotLinkV2
/// @notice Zap contract to mint storyline tokens on PlotLink (MCV2) using various input tokens.
/// @dev Supports PLOT (direct), ETH, USDC, and HUNT as input tokens via Uniswap V4 swaps.
///      Two-hop path: fromToken → PLOT (Uniswap V4) → storyline token (MCV2_Bond).
///      Forked from MintPad ZapUniV4MCV2 with PlotLink adaptations.
contract ZapPlotLinkV2 {
    using SafeERC20 for IERC20;

    // ============ Token Addresses (Base Mainnet) ============
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant HUNT = 0x37f0c2915CeCC7e977183B8543Fc0864d03E064C;
    address public constant ETH_ADDRESS = address(0);

    // ============ Uniswap V4 Pool Parameters (0.3% fee) ============
    uint24 public constant POOL_FEE = 3000;
    int24 public constant TICK_SPACING = 60;

    // ============ External Contracts (Base Mainnet) ============
    IUniversalRouter public constant UNIVERSAL_ROUTER = IUniversalRouter(0x6fF5693b99212Da76ad316178A184AB56D299b43);
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IV4Quoter public constant QUOTER = IV4Quoter(0x0d5e0F971ED27FBfF6c2837bf31316121532048D);
    IMCV2_BondFull public constant BOND = IMCV2_BondFull(0xc5a076cad94176c2996B32d8466Be1cE757FAa27);
    IMCV2_BondPeripheryFull public constant BOND_PERIPHERY =
        IMCV2_BondPeripheryFull(0x492C412369Db76C9cdD9939e6C521579301473a3);

    // ============ Owner-updatable state ============
    address public owner;
    address public plotToken;

    // ============ Errors ============
    error ZapPlotLink__UnsupportedToken();
    error ZapPlotLink__InvalidAmount();
    error ZapPlotLink__SlippageExceeded();
    error ZapPlotLink__InsufficientPlotReceived();
    error ZapPlotLink__InvalidETHAmount();
    error ZapPlotLink__OnlyOwner();
    error ZapPlotLink__ZeroAddress();

    // ============ Events ============
    event Minted(
        address indexed user,
        address indexed fromToken,
        address indexed storylineToken,
        uint256 storylineAmount,
        uint256 fromTokenUsed,
        uint256 plotUsed
    );

    event MintedReverse(
        address indexed user,
        address indexed fromToken,
        address indexed storylineToken,
        uint256 storylineAmount,
        uint256 fromTokenUsed,
        uint256 plotUsed
    );

    event PlotTokenUpdated(address indexed oldToken, address indexed newToken);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    // ============ Modifiers ============
    modifier onlyOwner() {
        if (msg.sender != owner) revert ZapPlotLink__OnlyOwner();
        _;
    }

    // ============ Constructor ============
    constructor(address _plotToken) {
        if (_plotToken == address(0)) revert ZapPlotLink__ZeroAddress();
        owner = msg.sender;
        plotToken = _plotToken;

        // Approve PLOT for Bond and BondPeriphery contracts
        IERC20(_plotToken).approve(address(BOND), type(uint256).max);
        IERC20(_plotToken).approve(address(BOND_PERIPHERY), type(uint256).max);

        // Setup Permit2 approvals for swap input tokens
        _setupPermit2Approval(USDC);
        _setupPermit2Approval(HUNT);
    }

    receive() external payable {}

    // ============ Owner Functions ============

    /// @notice Update the PLOT token address
    function setPlotToken(address newPlotToken) external onlyOwner {
        if (newPlotToken == address(0)) revert ZapPlotLink__ZeroAddress();
        address old = plotToken;

        // Revoke old approvals
        IERC20(old).approve(address(BOND), 0);
        IERC20(old).approve(address(BOND_PERIPHERY), 0);

        plotToken = newPlotToken;

        // Approve new token
        IERC20(newPlotToken).approve(address(BOND), type(uint256).max);
        IERC20(newPlotToken).approve(address(BOND_PERIPHERY), type(uint256).max);

        emit PlotTokenUpdated(old, newPlotToken);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZapPlotLink__ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Rescue stuck ETH
    function rescueETH(address payable to) external onlyOwner {
        (bool ok,) = to.call{value: address(this).balance}("");
        require(ok);
    }

    // ============ External Mint Functions ============

    /// @notice Mint exact amount of storyline tokens using various input tokens
    /// @param fromToken Input token (PLOT, USDC, HUNT, or address(0) for ETH)
    /// @param storylineToken The storyline token to mint
    /// @param storylineAmount Exact amount of storyline tokens to mint
    /// @param maxFromTokenAmount Maximum fromToken to spend (slippage protection)
    /// @return fromTokenUsed Actual fromToken spent
    function mint(address fromToken, address storylineToken, uint256 storylineAmount, uint256 maxFromTokenAmount)
        external
        payable
        returns (uint256 fromTokenUsed)
    {
        if (storylineAmount == 0) revert ZapPlotLink__InvalidAmount();

        // getReserveForToken returns (reserveAmount, royalty) where reserveAmount already includes royalty
        (uint256 plotRequired,) = BOND.getReserveForToken(storylineToken, storylineAmount);

        if (fromToken == plotToken) {
            if (msg.value != 0) revert ZapPlotLink__InvalidETHAmount();
            if (plotRequired > maxFromTokenAmount) revert ZapPlotLink__SlippageExceeded();
            IERC20(plotToken).safeTransferFrom(msg.sender, address(this), plotRequired);
            fromTokenUsed = plotRequired;
        } else {
            _validateAndTransferInput(fromToken, maxFromTokenAmount);
            fromTokenUsed = _executeV4SwapExactOutput(fromToken, plotRequired, maxFromTokenAmount);
            _refundToken(fromToken, maxFromTokenAmount - fromTokenUsed);
        }

        uint256 plotUsed;
        try BOND.mint(storylineToken, storylineAmount, plotRequired, msg.sender) returns (uint256 actualPlotUsed) {
            plotUsed = actualPlotUsed;
        } catch {
            revert ZapPlotLink__SlippageExceeded();
        }

        _refundPlot();
        emit Minted(msg.sender, fromToken, storylineToken, storylineAmount, fromTokenUsed, plotUsed);
    }

    /// @notice Mint storyline tokens by specifying exact input amount
    /// @param fromToken Input token (PLOT, USDC, HUNT, or address(0) for ETH)
    /// @param storylineToken The storyline token to mint
    /// @param fromTokenAmount Exact fromToken to spend
    /// @param minStorylineAmount Minimum storyline tokens to receive (slippage protection)
    /// @return storylineAmount Actual storyline tokens minted
    function mintReverse(address fromToken, address storylineToken, uint256 fromTokenAmount, uint256 minStorylineAmount)
        external
        payable
        returns (uint256 storylineAmount)
    {
        if (fromTokenAmount == 0) revert ZapPlotLink__InvalidAmount();

        uint256 plotAmount;
        if (fromToken == plotToken) {
            if (msg.value != 0) revert ZapPlotLink__InvalidETHAmount();
            IERC20(plotToken).safeTransferFrom(msg.sender, address(this), fromTokenAmount);
            plotAmount = fromTokenAmount;
        } else {
            _validateAndTransferInput(fromToken, fromTokenAmount);
            plotAmount = _executeV4Swap(fromToken, fromTokenAmount);
        }

        try BOND_PERIPHERY.mintWithReserveAmount(storylineToken, plotAmount, minStorylineAmount, msg.sender) returns (
            uint256 minted
        ) {
            storylineAmount = minted;
        } catch {
            revert ZapPlotLink__SlippageExceeded();
        }

        _refundPlot();
        emit MintedReverse(msg.sender, fromToken, storylineToken, storylineAmount, fromTokenAmount, plotAmount);
    }

    // ============ Estimation Functions (call via eth_call) ============

    /// @notice Estimate fromToken amount needed to mint exact storylineAmount
    /// @dev Not view — call via staticcall/eth_call
    function estimateMint(address fromToken, address storylineToken, uint256 storylineAmount)
        external
        returns (uint256 fromTokenAmount, uint256 totalPlotRequired)
    {
        (totalPlotRequired,) = BOND.getReserveForToken(storylineToken, storylineAmount);

        if (fromToken == plotToken) {
            fromTokenAmount = totalPlotRequired;
        } else {
            (fromTokenAmount,) = QUOTER.quoteExactOutputSingle(_buildQuoteParams(fromToken, uint128(totalPlotRequired)));
        }
    }

    /// @notice Estimate storylineAmount received for exact fromTokenAmount
    /// @dev Not view — call via staticcall/eth_call
    function estimateMintReverse(address fromToken, address storylineToken, uint256 fromTokenAmount)
        external
        returns (uint256 storylineAmount, uint256 plotAmount)
    {
        if (fromToken == plotToken) {
            plotAmount = fromTokenAmount;
        } else {
            (plotAmount,) = QUOTER.quoteExactInputSingle(_buildQuoteParams(fromToken, uint128(fromTokenAmount)));
        }

        (storylineAmount,) = BOND_PERIPHERY.getTokensForReserve(storylineToken, plotAmount, false);
    }

    // ============ Internal Functions ============

    function _buildQuoteParams(address fromToken, uint128 amount) private view returns (QuoteExactSingleParams memory) {
        (address currency0, address currency1, bool zeroForOne) =
            fromToken == ETH_ADDRESS ? (ETH_ADDRESS, plotToken, true) : (plotToken, fromToken, false);

        return QuoteExactSingleParams({
            poolKey: PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: POOL_FEE,
                tickSpacing: TICK_SPACING,
                hooks: IHooks(address(0))
            }),
            zeroForOne: zeroForOne,
            exactAmount: amount,
            hookData: bytes("")
        });
    }

    function _setupPermit2Approval(address token) private {
        IERC20(token).approve(PERMIT2, type(uint256).max);
        IAllowanceTransfer(PERMIT2).approve(token, address(UNIVERSAL_ROUTER), type(uint160).max, type(uint48).max);
    }

    function _validateAndTransferInput(address fromToken, uint256 amount) private {
        if (fromToken == ETH_ADDRESS) {
            if (msg.value != amount) revert ZapPlotLink__InvalidETHAmount();
        } else if (fromToken == USDC || fromToken == HUNT) {
            if (msg.value != 0) revert ZapPlotLink__InvalidETHAmount();
            IERC20(fromToken).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            revert ZapPlotLink__UnsupportedToken();
        }
    }

    /// @notice Execute V4 exactInput swap to PLOT (used by mintReverse)
    function _executeV4Swap(address fromToken, uint256 amountIn) private returns (uint256 plotReceived) {
        uint256 plotBefore = IERC20(plotToken).balanceOf(address(this));

        (address currency0, address currency1, bool zeroForOne) =
            fromToken == ETH_ADDRESS ? (ETH_ADDRESS, plotToken, true) : (plotToken, fromToken, false);

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = _buildV4SwapInputExactIn(currency0, currency1, zeroForOne, uint128(amountIn));

        if (fromToken == ETH_ADDRESS) {
            UNIVERSAL_ROUTER.execute{value: amountIn}(commands, inputs, block.timestamp);
        } else {
            UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp);
        }

        plotReceived = IERC20(plotToken).balanceOf(address(this)) - plotBefore;
    }

    /// @notice Execute V4 exactOutput swap to get exact PLOT amount (used by mint)
    function _executeV4SwapExactOutput(address fromToken, uint256 plotAmountOut, uint256 amountInMax)
        private
        returns (uint256 amountIn)
    {
        uint256 balanceBefore =
            fromToken == ETH_ADDRESS ? address(this).balance : IERC20(fromToken).balanceOf(address(this));

        (address currency0, address currency1, bool zeroForOne) =
            fromToken == ETH_ADDRESS ? (ETH_ADDRESS, plotToken, true) : (plotToken, fromToken, false);

        bytes memory swapInput =
            _buildV4SwapInputExactOut(currency0, currency1, zeroForOne, uint128(plotAmountOut), uint128(amountInMax));

        if (fromToken == ETH_ADDRESS) {
            bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.SWEEP));
            bytes[] memory inputs = new bytes[](2);
            inputs[0] = swapInput;
            inputs[1] = abi.encode(ETH_ADDRESS, address(this), 0);
            UNIVERSAL_ROUTER.execute{value: amountInMax}(commands, inputs, block.timestamp);
        } else {
            bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
            bytes[] memory inputs = new bytes[](1);
            inputs[0] = swapInput;
            UNIVERSAL_ROUTER.execute(commands, inputs, block.timestamp);
        }

        uint256 balanceAfter =
            fromToken == ETH_ADDRESS ? address(this).balance : IERC20(fromToken).balanceOf(address(this));
        amountIn = balanceBefore - balanceAfter;
    }

    function _refundPlot() private {
        uint256 balance = IERC20(plotToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(plotToken).safeTransfer(msg.sender, balance);
        }
    }

    function _refundToken(address token, uint256 amount) private {
        if (amount == 0) return;
        if (token == ETH_ADDRESS) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "ETH refund failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _buildV4SwapInputExactIn(address currency0, address currency1, bool zeroForOne, uint128 amountIn)
        private
        view
        returns (bytes memory)
    {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE)
        );

        bytes[] memory params = new bytes[](3);

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        (address settleToken, address takeToken) = zeroForOne ? (currency0, currency1) : (currency1, currency0);

        params[0] = abi.encode(
            ExactInputSingleParams({
                poolKey: poolKey, zeroForOne: zeroForOne, amountIn: amountIn, amountOutMinimum: 0, hookData: bytes("")
            })
        );
        params[1] = abi.encode(settleToken, amountIn);
        params[2] = abi.encode(takeToken, address(this), ActionConstants.OPEN_DELTA);

        return abi.encode(actions, params);
    }

    function _buildV4SwapInputExactOut(
        address currency0,
        address currency1,
        bool zeroForOne,
        uint128 amountOut,
        uint128 amountInMax
    ) private view returns (bytes memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE)
        );

        bytes[] memory params = new bytes[](3);

        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        (address settleToken, address takeToken) = zeroForOne ? (currency0, currency1) : (currency1, currency0);

        params[0] = abi.encode(
            ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountOut: amountOut,
                amountInMaximum: amountInMax,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(settleToken, amountInMax);
        params[2] = abi.encode(takeToken, address(this), ActionConstants.OPEN_DELTA);

        return abi.encode(actions, params);
    }
}
