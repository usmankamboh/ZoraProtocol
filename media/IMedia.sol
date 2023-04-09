// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;
import "./IMarket.sol";
interface IMedia {
    struct EIP712Signature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    struct MediaData {
        // A valid URI of the content represented by this token
        string tokenURI;
        // A valid URI of the metadata associated with this token
        string metadataURI;
        // A SHA256 hash of the content pointed to by tokenURI
        bytes32 contentHash;
        // A SHA256 hash of the content pointed to by metadataURI
        bytes32 metadataHash;
    }
    event TokenURIUpdated(uint256 indexed _tokenId, address owner, string _uri);
    event TokenMetadataURIUpdated(uint256 indexed _tokenId,address owner,string _uri);
    function tokenMetadataURI(uint256 tokenId) external view returns (string memory);
    function mint(MediaData calldata data, IMarket.BidShares calldata bidShares)external;
    function mintWithSig(address creator,MediaData calldata data,IMarket.BidShares calldata bidShares,EIP712Signature calldata sig) external;
    function auctionTransfer(uint256 tokenId, address recipient) external;
    function setAsk(uint256 tokenId, IMarket.Ask calldata ask) external;
    function removeAsk(uint256 tokenId) external;
    function setBid(uint256 tokenId, IMarket.Bid calldata bid) external;
    function removeBid(uint256 tokenId) external;
    function acceptBid(uint256 tokenId, IMarket.Bid calldata bid) external;
    function revokeApproval(uint256 tokenId) external;
    function updateTokenURI(uint256 tokenId, string calldata tokenURI) external;
    function updateTokenMetadataURI(uint256 tokenId,string calldata metadataURI) external;
    function permit(address spender,uint256 tokenId,EIP712Signature calldata sig) external;
}