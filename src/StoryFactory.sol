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
        address writer; // slot 1: sole author, royalty recipient (160 bits)
        address token; // slot 2: storyline token address on Mint Club (160 bits)
        uint24 plotCount; // slot 2: total plots chained (+24 = 184 bits)
        uint40 lastPlotTime; // slot 2: timestamp of last plot (+40 = 224 bits)
        bool hasDeadline; // slot 2: whether 168h deadline is enabled (+8 = 232 bits)
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
        string title,
        string contentCID,
        bytes32 contentHash
    );

    event Donation(uint256 indexed storylineId, address indexed donor, uint256 amount);

    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    uint16 public constant MINT_ROYALTY = 100; // 1% (basis points, base 10000)
    uint16 public constant BURN_ROYALTY = 100; // 1%

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
        require(_bond != address(0), "Zero bond address");
        require(_plotToken != address(0), "Zero token address");
        require(_stepRanges.length == _stepPrices.length, "Step arrays length mismatch");
        require(_stepRanges.length > 0, "Empty step arrays");
        require(_stepRanges.length <= 1000, "Too many steps");

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
    /// @param hasDeadline Whether the 168h (7-day) deadline mechanism is enabled
    /// @return storylineId The ID of the newly created storyline
    function createStoryline(string calldata title, string calldata openingCID, bytes32 openingHash, bool hasDeadline)
        external
        payable
        returns (uint256 storylineId)
    {
        require(bytes(title).length > 0, "Empty title");
        require(bytes(openingCID).length >= 46 && bytes(openingCID).length <= 100, "Invalid CID");
        require(openingHash != bytes32(0), "Empty hash");

        storylineId = ++storylineCount;

        // 1. Create token on Mint Club V2 bonding curve
        //    Factory becomes initial creator; we transfer to writer below
        TokenParams memory tp =
            TokenParams({name: title, symbol: string(abi.encodePacked("PL-", _uint2str(storylineId)))});

        BondParams memory bp = BondParams({
            mintRoyalty: MINT_ROYALTY,
            burnRoyalty: BURN_ROYALTY,
            reserveToken: address(PLOT_TOKEN),
            maxSupply: MAX_SUPPLY,
            stepRanges: stepRanges,
            stepPrices: stepPrices
        });

        address tokenAddress = BOND.createToken{value: msg.value}(tp, bp);

        // 2. Transfer creator role to writer (royalties go directly to them)
        BOND.updateBondCreator(tokenAddress, msg.sender);

        // 3. Store storyline
        storylines[storylineId] = Storyline({
            writer: msg.sender,
            token: tokenAddress,
            plotCount: 1,
            lastPlotTime: uint40(block.timestamp),
            hasDeadline: hasDeadline
        });

        // 4. Emit events
        emit StorylineCreated(storylineId, msg.sender, tokenAddress, title, hasDeadline, openingCID, openingHash);
        emit PlotChained(storylineId, 0, msg.sender, title, openingCID, openingHash);
    }

    // -----------------------------------------------------------------------
    // chainPlot
    // -----------------------------------------------------------------------

    /// @notice Chain a new plot to an existing storyline
    /// @param storylineId The storyline to chain to
    /// @param title Human-readable title for the plot chapter
    /// @param contentCID IPFS CID of the plot content
    /// @param contentHash keccak256 hash of the plot content
    function chainPlot(uint256 storylineId, string calldata title, string calldata contentCID, bytes32 contentHash)
        external
    {
        Storyline storage s = storylines[storylineId];
        require(msg.sender == s.writer, "Not writer");
        require(bytes(title).length > 0, "Empty title");
        require(bytes(contentCID).length >= 46 && bytes(contentCID).length <= 100, "Invalid CID");
        require(contentHash != bytes32(0), "Empty hash");
        if (s.hasDeadline) {
            require(block.timestamp <= uint256(s.lastPlotTime) + 168 hours, "Deadline passed");
        }

        uint256 plotIndex = s.plotCount; // genesis = 0, so first chain = 1
        s.plotCount++;
        s.lastPlotTime = uint40(block.timestamp);

        emit PlotChained(storylineId, plotIndex, msg.sender, title, contentCID, contentHash);
    }

    // -----------------------------------------------------------------------
    // hasSunset
    // -----------------------------------------------------------------------

    /// @notice Check if a storyline's deadline has expired
    /// @param storylineId The storyline to check
    /// @return True if the storyline has a deadline and it has passed
    function hasSunset(uint256 storylineId) external view returns (bool) {
        Storyline storage s = storylines[storylineId];
        return s.hasDeadline && block.timestamp > uint256(s.lastPlotTime) + 168 hours;
    }

    // -----------------------------------------------------------------------
    // donate
    // -----------------------------------------------------------------------

    /// @notice Donate $PLOT directly to a storyline's writer
    /// @param storylineId The storyline whose writer receives the donation
    /// @param amount Amount of $PLOT to donate (in wei)
    function donate(uint256 storylineId, uint256 amount) external {
        require(amount > 0, "Zero amount");
        Storyline storage s = storylines[storylineId];
        require(s.writer != address(0), "Storyline does not exist");

        require(PLOT_TOKEN.transferFrom(msg.sender, s.writer, amount), "Transfer failed");

        emit Donation(storylineId, msg.sender, amount);
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
