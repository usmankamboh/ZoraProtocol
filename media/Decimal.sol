// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./Math.sol";
library Decimal {
    using SafeMath for uint256;
    uint256 constant BASE_POW = 18;
    uint256 constant BASE = 10**BASE_POW;
    struct D256 {
        uint256 value;
    }
    function one() internal pure returns (D256 memory) {
        return D256({value: BASE});
    }
    function onePlus(D256 memory d) internal pure returns (D256 memory) {
        return D256({value: d.value.add(BASE)});
    }
    function mul(uint256 target, D256 memory d)internal pure returns (uint256){
        return Math.getPartial(target, d.value, BASE);
    }
    function div(uint256 target, D256 memory d)internal pure returns (uint256){
        return Math.getPartial(target, BASE, d.value);
    }
}