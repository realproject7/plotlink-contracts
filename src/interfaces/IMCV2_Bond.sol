// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IMCV2_Bond — Interface for Mint Club V2 Bond contract on Base
/// @dev Deployed at 0xc5a076cad94176c2996B32d8466Be1cE757FAa27
/// @dev Source: github.com/Steemhunt/mint.club-v2-contract

struct TokenParams {
    string name;
    string symbol;
}

struct BondParams {
    uint16 mintRoyalty;
    uint16 burnRoyalty;
    address reserveToken;
    uint128 maxSupply;
    uint128[] stepRanges;
    uint128[] stepPrices;
}

interface IMCV2_Bond {
    /// @notice Create a new ERC-20 token with bonding curve
    function createToken(TokenParams calldata tp, BondParams calldata bp) external payable returns (address);

    /// @notice Transfer the creator role (royalty recipient) for a token
    function updateBondCreator(address token, address creator) external;

    /// @notice Mint tokens on the bonding curve
    /// @return reserveAmount Amount of reserve token spent
    function mint(address token, uint256 tokensToMint, uint256 maxReserveAmount, address receiver)
        external
        returns (uint256);

    /// @notice Burn tokens on the bonding curve
    /// @return refundAmount Amount of reserve token refunded
    function burn(address token, uint256 tokensToBurn, uint256 minRefund, address receiver) external returns (uint256);

    /// @notice Get the reserve amount required to mint tokens
    function getReserveForToken(address token, uint256 tokensToMint)
        external
        view
        returns (uint256 reserveAmount, uint256 royalty);

    /// @notice Get the refund for burning tokens
    function getRefundForTokens(address token, uint256 tokensToBurn)
        external
        view
        returns (uint256 refundAmount, uint256 royalty);

    /// @notice Claim accumulated royalties (inherited from MCV2_Royalty)
    function claimRoyalties(address reserveToken) external;
}
