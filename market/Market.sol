// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./IERC721.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Decimal.sol";
import "./Media.sol";
import "./IMarket.sol";
contract Market is IMarket {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Address of the media contract that can call this market
    address public mediaContract;
    // Deployment Address
    address private _owner;
    // Mapping from token to mapping from bidder to bid
    mapping(uint256 => mapping(address => Bid)) private _tokenBidders;
    // Mapping from token to the bid shares for the token
    mapping(uint256 => BidShares) private _bidShares;
    // Mapping from token to the current ask for the token
    mapping(uint256 => Ask) private _tokenAsks;
    //@notice require that the msg.sender is the configured media contract
    modifier onlyMediaCaller() {
        require(mediaContract == msg.sender, "Market: Only media contract");
        _;
    }
    function bidForTokenBidder(uint256 tokenId, address bidder)external view override returns (Bid memory){
        return _tokenBidders[tokenId][bidder];
    }
    function currentAskForToken(uint256 tokenId)external view override returns (Ask memory){
        return _tokenAsks[tokenId];
    }
    function bidSharesForToken(uint256 tokenId)public view override returns (BidShares memory){
        return _bidShares[tokenId];
    }
    function isValidBid(uint256 tokenId, uint256 bidAmount)public view override returns (bool){
        BidShares memory bidShares = bidSharesForToken(tokenId);
        require(isValidBidShares(bidShares),"Market: Invalid bid shares for token");
        return bidAmount != 0 && (bidAmount == splitShare(bidShares.creator, bidAmount).add(splitShare(bidShares.prevOwner, bidAmount))
                    .add(splitShare(bidShares.owner, bidAmount)));
    }
    function isValidBidShares(BidShares memory bidShares)public pure override returns (bool){
        return bidShares.creator.value.add(bidShares.owner.value).add(bidShares.prevOwner.value) == uint256(100).mul(Decimal.BASE);
    }
    function splitShare(Decimal.D256 memory sharePercentage, uint256 amount)public pure override returns (uint256){
        return Decimal.mul(amount, sharePercentage).div(100);
    }
    constructor() public {
        _owner = msg.sender;
    }
    function configure(address mediaContractAddress) external override {
        require(msg.sender == _owner, "Market: Only owner");
        require(mediaContract == address(0), "Market: Already configured");
        require(mediaContractAddress != address(0),"Market: cannot set media contract as zero address");
        mediaContract = mediaContractAddress;
    }
    function setBidShares(uint256 tokenId, BidShares memory bidShares)public override onlyMediaCaller{
        require(isValidBidShares(bidShares),"Market: Invalid bid shares, must sum to 100");
        _bidShares[tokenId] = bidShares;
        emit BidShareUpdated(tokenId, bidShares);
    }
    function setAsk(uint256 tokenId, Ask memory ask)public override onlyMediaCaller{
        require(isValidBid(tokenId, ask.amount),"Market: Ask invalid for share splitting");
        _tokenAsks[tokenId] = ask;
        emit AskCreated(tokenId, ask);
    }
    function removeAsk(uint256 tokenId) external override onlyMediaCaller {
        emit AskRemoved(tokenId, _tokenAsks[tokenId]);
        delete _tokenAsks[tokenId];
    }
    function setBid(uint256 tokenId,Bid memory bid,address spender) public override onlyMediaCaller {
        BidShares memory bidShares = _bidShares[tokenId];
        require(bidShares.creator.value.add(bid.sellOnShare.value) <= uint256(100).mul(Decimal.BASE),"Market: Sell on fee invalid for share splitting");
        require(bid.bidder != address(0), "Market: bidder cannot be 0 address");
        require(bid.amount != 0, "Market: cannot bid amount of 0");
        require(bid.currency != address(0),"Market: bid currency cannot be 0 address");
        require(bid.recipient != address(0),"Market: bid recipient cannot be 0 address");
        Bid storage existingBid = _tokenBidders[tokenId][bid.bidder];
        // If there is an existing bid, refund it before continuing
        if (existingBid.amount > 0) {
            removeBid(tokenId, bid.bidder);
        }
        IERC20 token = IERC20(bid.currency);
        // We must check the balance that was actually transferred to the market,
        // as some tokens impose a transfer fee and would not actually transfer the
        // full amount to the market, resulting in locked funds for refunds & bid acceptance
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(spender, address(this), bid.amount);
        uint256 afterBalance = token.balanceOf(address(this));
        _tokenBidders[tokenId][bid.bidder] = Bid(afterBalance.sub(beforeBalance),bid.currency,bid.bidder,bid.recipient,bid.sellOnShare);
        emit BidCreated(tokenId, bid);
        // If a bid meets the criteria for an ask, automatically accept the bid.
        // If no ask is set or the bid does not meet the requirements, ignore.
        if ( _tokenAsks[tokenId].currency != address(0) && bid.currency == _tokenAsks[tokenId].currency && bid.amount >= _tokenAsks[tokenId].amount) {
            // Finalize exchange
            _finalizeNFTTransfer(tokenId, bid.bidder);
        }
    }
    function removeBid(uint256 tokenId, address bidder)public override onlyMediaCaller{
        Bid storage bid = _tokenBidders[tokenId][bidder];
        uint256 bidAmount = bid.amount;
        address bidCurrency = bid.currency;
        require(bid.amount > 0, "Market: cannot remove bid amount of 0");
        IERC20 token = IERC20(bidCurrency);
        emit BidRemoved(tokenId, bid);
        delete _tokenBidders[tokenId][bidder];
        token.safeTransfer(bidder, bidAmount);
    }
    function acceptBid(uint256 tokenId, Bid calldata expectedBid)external override onlyMediaCaller{
        Bid memory bid = _tokenBidders[tokenId][expectedBid.bidder];
        require(bid.amount > 0, "Market: cannot accept bid of 0");
        require(bid.amount == expectedBid.amount && bid.currency == expectedBid.currency &&bid.sellOnShare.value == expectedBid.sellOnShare.value && 
                bid.recipient == expectedBid.recipient,"Market: Unexpected bid found.");
        require(isValidBid(tokenId, bid.amount),"Market: Bid invalid for share splitting");
        _finalizeNFTTransfer(tokenId, bid.bidder);
    }
    function _finalizeNFTTransfer(uint256 tokenId, address bidder) private {
        Bid memory bid = _tokenBidders[tokenId][bidder];
        BidShares storage bidShares = _bidShares[tokenId];
        IERC20 token = IERC20(bid.currency);
        // Transfer bid share to owner of media
        token.safeTransfer(IERC721(mediaContract).ownerOf(tokenId),splitShare(bidShares.owner, bid.amount));
        // Transfer bid share to creator of media
        token.safeTransfer(Media(mediaContract).tokenCreators(tokenId),splitShare(bidShares.creator, bid.amount));
        // Transfer bid share to previous owner of media (if applicable)
        token.safeTransfer(Media(mediaContract).previousTokenOwners(tokenId),splitShare(bidShares.prevOwner, bid.amount));
        // Transfer media to bid recipient
        Media(mediaContract).auctionTransfer(tokenId, bid.recipient);
        // Calculate the bid share for the new owner,
        // equal to 100 - creatorShare - sellOnShare
        bidShares.owner = Decimal.D256(uint256(100).mul(Decimal.BASE).sub(_bidShares[tokenId].creator.value).sub(bid.sellOnShare.value));
        // Set the previous owner share to the accepted bid's sell-on fee
        bidShares.prevOwner = bid.sellOnShare;
        // Remove the accepted bid
        delete _tokenBidders[tokenId][bidder];
        emit BidShareUpdated(tokenId, bidShares);
        emit BidFinalized(tokenId, bid);
    }
}