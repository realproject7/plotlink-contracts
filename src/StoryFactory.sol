// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMCV2_Bond} from "./interfaces/IMCV2_Bond.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title StoryFactory — PlotLink storyline and plot management
/// @notice Placeholder — full implementation in subsequent tickets
contract StoryFactory {
    IMCV2_Bond public immutable BOND;
    IERC20 public immutable PLOT_TOKEN;

    constructor(address _bond, address _plotToken) {
        BOND = IMCV2_Bond(_bond);
        PLOT_TOKEN = IERC20(_plotToken);
    }
}
