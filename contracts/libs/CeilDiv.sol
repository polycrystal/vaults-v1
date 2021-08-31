// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

library CeilDiv {

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
		require(b > 0, "ceilDiv by zero");
        return a / b + (a % b == 0 ? 0 : 1);
    }
}