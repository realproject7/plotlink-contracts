// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMCV2_Bond, TokenParams, BondParams} from "./interfaces/IMCV2_Bond.sol";
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
    // Constants
    // -----------------------------------------------------------------------

    uint16 public constant MINT_ROYALTY = 500; // 5% (basis points, base 10000)
    uint16 public constant BURN_ROYALTY = 500; // 5%

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    IMCV2_Bond public immutable BOND;
    IERC20 public immutable PLOT_TOKEN;

    /// @notice Bonding curve step arrays (same for every storyline, set at deploy)
    uint128[] public stepRanges;
    uint128[] public stepPrices;
    uint128 public immutable MAX_SUPPLY;

    mapping(uint256 => Storyline) public storylines;
    uint256 public storylineCount;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _bond,
        address _plotToken,
        uint128 _maxSupply,
        uint128[] memory _stepRanges,
        uint128[] memory _stepPrices
    ) {
        require(_stepRanges.length == _stepPrices.length, "Step arrays length mismatch");
        require(_stepRanges.length > 0, "Empty step arrays");

        BOND = IMCV2_Bond(_bond);
        PLOT_TOKEN = IERC20(_plotToken);
        MAX_SUPPLY = _maxSupply;
        stepRanges = _stepRanges;
        stepPrices = _stepPrices;
    }

    // -----------------------------------------------------------------------
    // createStoryline
    // -----------------------------------------------------------------------

    /// @notice Create a new storyline with a genesis plot on a Mint Club V2 bonding curve
    /// @param title Human-readable title of the storyline
    /// @param openingCID IPFS CID of the genesis plot content
    /// @param openingHash keccak256 hash of the genesis plot content
    /// @param hasDeadline Whether the 72h deadline mechanism is enabled
    /// @return storylineId The ID of the newly created storyline
    function createStoryline(string calldata title, string calldata openingCID, bytes32 openingHash, bool hasDeadline)
        external
        returns (uint256 storylineId)
    {
        require(bytes(title).length > 0, "Empty title");
        require(bytes(openingCID).length >= 46 && bytes(openingCID).length <= 100, "Invalid CID");

        storylineId = ++storylineCount;

        // 1. Create token on Mint Club V2 bonding curve
        //    Factory becomes initial creator; we transfer to writer below
        TokenParams memory tp =
            TokenParams({name: title, symbol: string(abi.encodePacked("PLOT-", _uint2str(storylineId)))});

        BondParams memory bp = BondParams({
            mintRoyalty: MINT_ROYALTY,
            burnRoyalty: BURN_ROYALTY,
            reserveToken: address(PLOT_TOKEN),
            maxSupply: MAX_SUPPLY,
            stepRanges: stepRanges,
            stepPrices: stepPrices
        });

        address tokenAddress = BOND.createToken(tp, bp);

        // 2. Transfer creator role to writer (royalties go directly to them)
        BOND.updateBondCreator(tokenAddress, msg.sender);

        // 3. Store storyline
        storylines[storylineId] = Storyline({
            writer: msg.sender,
            token: tokenAddress,
            plotCount: 1,
            lastPlotTime: block.timestamp,
            hasDeadline: hasDeadline,
            sunset: false
        });

        // 4. Emit events
        emit StorylineCreated(storylineId, msg.sender, tokenAddress, title, hasDeadline, openingCID, openingHash);
        emit PlotChained(storylineId, 0, msg.sender, openingCID, openingHash);
    }

    // -----------------------------------------------------------------------
    // chainPlot
    // -----------------------------------------------------------------------

    /// @notice Chain a new plot to an existing storyline
    /// @param storylineId The storyline to chain to
    /// @param contentCID IPFS CID of the plot content
    /// @param contentHash keccak256 hash of the plot content
    function chainPlot(uint256 storylineId, string calldata contentCID, bytes32 contentHash) external {
        Storyline storage s = storylines[storylineId];
        require(msg.sender == s.writer, "Not writer");
        require(bytes(contentCID).length >= 46 && bytes(contentCID).length <= 100, "Invalid CID");
        require(!s.sunset, "Storyline sunset");
        if (s.hasDeadline) {
            require(block.timestamp <= s.lastPlotTime + 72 hours, "Deadline passed");
        }

        s.plotCount++;
        s.lastPlotTime = block.timestamp;

        emit PlotChained(storylineId, s.plotCount, msg.sender, contentCID, contentHash);
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /// @dev Convert uint to decimal string (for token symbol generation)
    function _uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
