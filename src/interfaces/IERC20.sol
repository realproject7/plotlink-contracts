// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IERC20 — Minimal ERC-20 interface for StoryFactory interactions
interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}
