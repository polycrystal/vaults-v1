// SPDX-License-Identifier: MIT

/*
Join us at PolyCrystal.Finance!
█▀▀█ █▀▀█ █░░ █░░█ █▀▀ █▀▀█ █░░█ █▀▀ ▀▀█▀▀ █▀▀█ █░░ 
█░░█ █░░█ █░░ █▄▄█ █░░ █▄▄▀ █▄▄█ ▀▀█ ░░█░░ █▄▄█ █░░ 
█▀▀▀ ▀▀▀▀ ▀▀▀ ▄▄▄█ ▀▀▀ ▀░▀▀ ▄▄▄█ ▀▀▀ ░░▀░░ ▀░░▀ ▀▀▀
*/

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/math/Math.sol";

library Pyrite {

    function reverseArray(address[] memory _array) internal pure returns (address[] memory array) {
        
        array = new address[](_array.length);
        
        for (uint i; i < (_array.length + 1) / 2; i++) {
            uint j = _array.length - 1 - i;
            (array[i], array[j]) = (_array[j], _array[i]);
        }
        return array;
    }
}