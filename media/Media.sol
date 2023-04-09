// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;
import "./ERC721Burnable.sol";
import "./ERC721.sol";
import "./EnumerableSet.sol";
import "./Counters.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Decimal.sol";
import "./IMarket.sol";
import "./IMedia.sol";
contract Media is IMedia, ERC721Burnable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    // Address for the market
    address public marketContract;
    // Mapping from token to previous owner of the token
    mapping(uint256 => address) public previousTokenOwners;
    // Mapping from token id to creator address
    mapping(uint256 => address) public tokenCreators;
    // Mapping from creator address to their (enumerable) set of created tokens
    mapping(address => EnumerableSet.UintSet) private _creatorTokens;
    // Mapping from token id to sha256 hash of content
    mapping(uint256 => bytes32) public tokenContentHashes;
    // Mapping from token id to sha256 hash of metadata
    mapping(uint256 => bytes32) public tokenMetadataHashes;
    // Mapping from token id to metadataURI
    mapping(uint256 => string) private _tokenMetadataURIs;
    // Mapping from contentHash to bool
    mapping(bytes32 => bool) private _contentHashes;
    //keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH =0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
    //keccak256("MintWithSig(bytes32 contentHash,bytes32 metadataHash,uint256 creatorShare,uint256 nonce,uint256 deadline)");
    bytes32 public constant MINT_WITH_SIG_TYPEHASH =0x2952e482b8e2b192305f87374d7af45dc2eafafe4f50d26a0c02e90f2fdbe14b;
    // Mapping from address to token id to permit nonce
    mapping(address => mapping(uint256 => uint256)) public permitNonces;
    // Mapping from address to mint with sig nonce
    mapping(address => uint256) public mintWithSigNonces;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x4e222e66;
    Counters.Counter private _tokenIdTracker;
    modifier onlyExistingToken(uint256 tokenId) {
        require(_exists(tokenId), "Media: nonexistent token");
        _;
    }
    modifier onlyTokenWithContentHash(uint256 tokenId) {
        require(tokenContentHashes[tokenId] != 0,"Media: token does not have hash of created content");
        _;
    }
    modifier onlyTokenWithMetadataHash(uint256 tokenId) {
        require(tokenMetadataHashes[tokenId] != 0,"Media: token does not have hash of its metadata");
        _;
    }
    modifier onlyApprovedOrOwner(address spender, uint256 tokenId) {
        require(_isApprovedOrOwner(spender, tokenId),"Media: Only approved or owner");
        _;
    }
    modifier onlyTokenCreated(uint256 tokenId) {
        require(_tokenIdTracker.current() > tokenId,"Media: token with that id does not exist");
        _;
    }
    modifier onlyValidURI(string memory uri) {
        require(bytes(uri).length != 0,"Media: specified uri must be non-empty");
        _;
    }
    constructor(address marketContractAddr) public ERC721("Zora", "ZORA") {
        marketContract = marketContractAddr;
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
    }
    function tokenURI(uint256 tokenId)public view override onlyTokenCreated(tokenId) returns (string memory){
        string memory _tokenURI = _tokenURIs[tokenId];
        return _tokenURI;
    }
    function tokenMetadataURI(uint256 tokenId)external view override onlyTokenCreated(tokenId) returns (string memory){
        return _tokenMetadataURIs[tokenId];
    }
    function mint(MediaData memory data, IMarket.BidShares memory bidShares) public override nonReentrant{
        _mintForCreator(msg.sender, data, bidShares);
    }
    function mintWithSig(address creator,MediaData memory data,IMarket.BidShares memory bidShares,EIP712Signature memory sig) public override nonReentrant {
        require(sig.deadline == 0 || sig.deadline >= block.timestamp,"Media: mintWithSig expired");
        bytes32 domainSeparator = _calculateDomainSeparator();
        bytes32 digest =keccak256(abi.encodePacked("\x19\x01",domainSeparator,keccak256(abi.encode(MINT_WITH_SIG_TYPEHASH,
            data.contentHash,data.metadataHash,bidShares.creator.value,mintWithSigNonces[creator]++,sig.deadline))));
        address recoveredAddress = ecrecover(digest, sig.v, sig.r, sig.s);
        require(recoveredAddress != address(0) && creator == recoveredAddress,"Media: Signature invalid");
        _mintForCreator(recoveredAddress, data, bidShares);
    }
    function auctionTransfer(uint256 tokenId, address recipient) external override{
        require(msg.sender == marketContract, "Media: only market contract");
        previousTokenOwners[tokenId] = ownerOf(tokenId);
        _safeTransfer(ownerOf(tokenId), recipient, tokenId, "");
    }
    function setAsk(uint256 tokenId, IMarket.Ask memory ask) public override nonReentrant onlyApprovedOrOwner(msg.sender, tokenId){
        IMarket(marketContract).setAsk(tokenId, ask);
    }
    function removeAsk(uint256 tokenId)external override nonReentrant onlyApprovedOrOwner(msg.sender, tokenId){
        IMarket(marketContract).removeAsk(tokenId);
    }
    function setBid(uint256 tokenId, IMarket.Bid memory bid)public override nonReentrant onlyExistingToken(tokenId){
        require(msg.sender == bid.bidder, "Market: Bidder must be msg sender");
        IMarket(marketContract).setBid(tokenId, bid, msg.sender);
    }
    function removeBid(uint256 tokenId) external override nonReentrant onlyTokenCreated(tokenId){
        IMarket(marketContract).removeBid(tokenId, msg.sender);
    }
    function acceptBid(uint256 tokenId, IMarket.Bid memory bid)public override nonReentrant onlyApprovedOrOwner(msg.sender, tokenId) {
        IMarket(marketContract).acceptBid(tokenId, bid);
    }
    function burn(uint256 tokenId)public override nonReentrant onlyExistingToken(tokenId) onlyApprovedOrOwner(msg.sender, tokenId){
        address owner = ownerOf(tokenId);
        require(tokenCreators[tokenId] == owner,"Media: owner is not creator of media");
        _burn(tokenId);
    }
    function revokeApproval(uint256 tokenId) external override nonReentrant {
        require(msg.sender == getApproved(tokenId),"Media: caller not approved address");
        _approve(address(0), tokenId);
    }
    function updateTokenURI(uint256 tokenId, string calldata tokenURI)external override nonReentrant onlyApprovedOrOwner(msg.sender, tokenId) onlyTokenWithContentHash(tokenId) onlyValidURI(tokenURI){
        _setTokenURI(tokenId, tokenURI);
        emit TokenURIUpdated(tokenId, msg.sender, tokenURI);
    }
    function updateTokenMetadataURI(uint256 tokenId,string calldata metadataURI)external override nonReentrant
        onlyApprovedOrOwner(msg.sender, tokenId) onlyTokenWithMetadataHash(tokenId) onlyValidURI(metadataURI){
        _setTokenMetadataURI(tokenId, metadataURI);
        emit TokenMetadataURIUpdated(tokenId, msg.sender, metadataURI);
    }
    function permit(address spender,uint256 tokenId,EIP712Signature memory sig) public override nonReentrant onlyExistingToken(tokenId) {
        require(sig.deadline == 0 || sig.deadline >= block.timestamp,"Media: Permit expired");
        require(spender != address(0), "Media: spender cannot be 0x0");
        bytes32 domainSeparator = _calculateDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01",domainSeparator,keccak256(abi.encode(PERMIT_TYPEHASH,
            spender,tokenId,permitNonces[ownerOf(tokenId)][tokenId]++,sig.deadline))));
        address recoveredAddress = ecrecover(digest, sig.v, sig.r, sig.s);
        require(recoveredAddress != address(0) && ownerOf(tokenId) == recoveredAddress,"Media: Signature invalid");
        _approve(spender, tokenId);
    }
    function _mintForCreator(address creator,MediaData memory data,IMarket.BidShares memory bidShares) internal onlyValidURI(data.tokenURI) onlyValidURI(data.metadataURI) {
        require(data.contentHash != 0, "Media: content hash must be non-zero");
        require(_contentHashes[data.contentHash] == false,"Media: a token has already been created with this content hash");
        require(data.metadataHash != 0,"Media: metadata hash must be non-zero");
        uint256 tokenId = _tokenIdTracker.current();
        _safeMint(creator, tokenId);
        _tokenIdTracker.increment();
        _setTokenContentHash(tokenId, data.contentHash);
        _setTokenMetadataHash(tokenId, data.metadataHash);
        _setTokenMetadataURI(tokenId, data.metadataURI);
        _setTokenURI(tokenId, data.tokenURI);
        _creatorTokens[creator].add(tokenId);
        _contentHashes[data.contentHash] = true;
        tokenCreators[tokenId] = creator;
        previousTokenOwners[tokenId] = creator;
        IMarket(marketContract).setBidShares(tokenId, bidShares);
    }
    function _setTokenContentHash(uint256 tokenId, bytes32 contentHash)internal virtual onlyExistingToken(tokenId){
        tokenContentHashes[tokenId] = contentHash;
    }
    function _setTokenMetadataHash(uint256 tokenId, bytes32 metadataHash)internal virtual onlyExistingToken(tokenId){
        tokenMetadataHashes[tokenId] = metadataHash;
    }
    function _setTokenMetadataURI(uint256 tokenId, string memory metadataURI)internal virtual onlyExistingToken(tokenId){
        _tokenMetadataURIs[tokenId] = metadataURI;
    }
    function _burn(uint256 tokenId) internal override {
        string memory tokenURI = _tokenURIs[tokenId];
        super._burn(tokenId);
        if (bytes(tokenURI).length != 0) {
            _tokenURIs[tokenId] = tokenURI;
        }
        delete previousTokenOwners[tokenId];
    }
    function _transfer(address from,address to,uint256 tokenId) internal override {
        IMarket(marketContract).removeAsk(tokenId);
        super._transfer(from, to, tokenId);
    }
    function _calculateDomainSeparator() internal view returns (bytes32) {
        uint256 chainID;
        /* solium-disable-next-line */
        assembly {
            chainID := chainid()
        }
        return keccak256(abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Zora")),keccak256(bytes("1")),chainID,address(this)));
    }
}