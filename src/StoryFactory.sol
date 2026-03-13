// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMCV2_Bond} from "./interfaces/IMCV2_Bond.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title StoryFactory — PlotLink storyline and plot management
/// @notice Creates storylines on Mint Club V2 bonding curves, stores plots,
///         enforces access control and deadlines. No admin, no owner, immutable.
contract StoryFactory {
    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    struct Storyline {
        address writer; // sole author, royalty recipient
        address token; // storyline token address on Mint Club
        uint256 plotCount; // total plots chained
        uint256 lastPlotTime; // timestamp of last plot (for deadline)
        bool hasDeadline; // whether 72h deadline is enabled
        bool sunset; // true if deadline expired
    }

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event StorylineCreated(
        uint256 indexed storylineId,
        address indexed writer,
        address tokenAddress,
        string title,
        bool hasDeadline,
        string openingCID,
        bytes32 openingHash
    );

    event PlotChained(
        uint256 indexed storylineId,
        uint256 indexed plotIndex,
        address indexed writer,
        string contentCID,
        bytes32 contentHash
    );

    event Donation(uint256 indexed storylineId, address indexed donor, uint256 amount);

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    IMCV2_Bond public immutable BOND;
    IERC20 public immutable PLOT_TOKEN;

    mapping(uint256 => Storyline) public storylines;
    uint256 public storylineCount;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _bond, address _plotToken) {
        BOND = IMCV2_Bond(_bond);
        PLOT_TOKEN = IERC20(_plotToken);
    }
}
