// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import "./Context.sol";
import "./ERC721.sol";
abstract contract ERC721Burnable is Context, ERC721 {
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId),"ERC721Burnable: caller is not owner nor approved");
        _burn(tokenId);
    }
}