// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IMCV2_Bond — Interface for Mint Club V2 Bond contract on Base
/// @dev Deployed at 0xc5a076cad94176c2996B32d8466Be1cE757FAa27
/// @dev Reference: https://github.com/nicedoc/mintclub-v2
interface IMCV2_Bond {
    /// @notice Create a new token with bonding curve parameters
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param reserveToken Address of the reserve token (e.g. $PLOT)
    /// @param maxSupply Maximum supply of the new token
    /// @param stepRanges Array of supply thresholds for each price step
    /// @param stepPrices Array of prices at each step
    /// @param creatorAddress Address that receives royalties
    /// @param mintRoyalty Mint royalty in basis points (e.g. 500 = 5%)
    /// @param burnRoyalty Burn royalty in basis points
    function createToken(
        string calldata name,
        string calldata symbol,
        address reserveToken,
        uint256 maxSupply,
        uint256[] calldata stepRanges,
        uint256[] calldata stepPrices,
        address creatorAddress,
        uint16 mintRoyalty,
        uint16 burnRoyalty
    ) external returns (address tokenAddress);

    /// @notice Transfer the creator role (royalty recipient) for a token
    /// @param token Address of the token
    /// @param newCreator New creator address
    function updateBondCreator(address token, address newCreator) external;

    /// @notice Mint tokens on the bonding curve
    /// @param token Address of the token to mint
    /// @param tokensToMint Amount of tokens to mint
    /// @param maxReserveAmount Maximum reserve token amount willing to spend (slippage)
    /// @param receiver Address to receive the minted tokens
    function mint(
        address token,
        uint256 tokensToMint,
        uint256 maxReserveAmount,
        address receiver
    ) external;

    /// @notice Burn tokens on the bonding curve
    /// @param token Address of the token to burn
    /// @param tokensToBurn Amount of tokens to burn
    /// @param minRefund Minimum reserve token refund (slippage)
    /// @param receiver Address to receive the refund
    function burn(
        address token,
        uint256 tokensToBurn,
        uint256 minRefund,
        address receiver
    ) external;

    /// @notice Get the reserve amount required to mint a given number of tokens
    /// @param token Address of the token
    /// @param tokensToMint Amount of tokens to mint
    /// @return reserveAmount Required reserve token amount
    function getReserveForToken(
        address token,
        uint256 tokensToMint
    ) external view returns (uint256 reserveAmount);

    /// @notice Claim accumulated royalties for a token
    /// @param token Address of the token
    function claimRoyalties(address token) external;
}
