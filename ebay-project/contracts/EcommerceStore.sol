pragma solidity ^0.4.24;


contract EcommerceStore {

    struct Product {
        //
        uint id;
        string name;
        string category;
        string imageLink;
        string descLink;

        uint startPrice;
        uint auctionStartTime;
        uint auctionEndTime;
        uint highestBid;
        uint totalBids;
        address highestBidder;
        uint secondHighestBid;
        ProductStatus status;
        ProductCondition condition;
        mapping(address => mapping(bytes32 => Bid)) bids;
    }

    enum ProductStatus {Open, Sold, Unsold}
    enum ProductCondition {Used, New}

    uint public productIndex;
    mapping(uint => address) public productIdToOwner;
    mapping(address => mapping(uint => Product)) stores;
     
    function addProductToStore(string _name, string _category, string _imageLink, string _descLink, uint _startTime, uint _endTime, uint _startPrice, uint condition) public {
        productIndex++;
        Product memory product = Product({
            id : productIndex,
            name : _name,
            category : _category,
            imageLink : _imageLink,
            descLink : _descLink,
            startPrice : _startPrice,
            auctionStartTime : _startTime,
            auctionEndTime : _endTime,
            highestBidder : 0,
            highestBid : 0,
            totalBids : 0,
            secondHighestBid : 0,
            status : ProductStatus.Open,
            condition : ProductCondition(condition)
            });


        //
        stores[msg.sender][productIndex] = product;
        productIdToOwner[productIndex] = msg.sender;
    }

    function getProductById(uint _productId) public view returns (uint, string, string, string, string, uint, uint, uint, uint){
        address owner = productIdToOwner[_productId];
        Product memory product = stores[owner][_productId];
        return (product.id, product.name, product.category, product.imageLink, product.descLink, product.auctionStartTime, product.auctionEndTime, product.startPrice, uint(product.status));
    }
    
    struct Bid {
        uint productId;
        uint price;
        bool isRevealed;
        address bidder;
    }
    function bid(uint _productId, bytes32 _bidHash) public payable {
        Product storage product = stores[productIdToOwner[_productId]][_productId];
        //require(now > product.auctionStartTime);
        //require(now < product.auctionEndTime);
        require(msg.value > product.startPrice);

        product.totalBids++;
        Bid memory bidLocal = Bid(_productId, msg.value, false, msg.sender);
        product.bids[msg.sender][_bidHash] = bidLocal;
    }
    
    function makeBidHash(string _realAmount, string _secret) public pure returns (bytes32){
        return sha3(_realAmount, _secret);
    }
    
    function getBidById(uint _productId, bytes32 _bidId) public view returns (uint, uint, bool, address) {
        Product storage product = stores[productIdToOwner[_productId]][_productId];

        Bid memory bid = product.bids[msg.sender][_bidId];
        return (bid.productId, bid.price, bid.isRevealed, bid.bidder);
    }
    
    function getBalance() public view returns (uint){
        return this.balance;
    }
    
    event revealEvent(uint productid, bytes32 bidId, uint confusePrice, uint price, uint refund);
    
    function revealBid(uint _productId, string _idealPrice, string _secret) public {
        Product storage product = stores[productIdToOwner[_productId]][_productId];
        bytes32 bidId = sha3(_idealPrice, _secret);
        Bid storage currBid = product.bids[msg.sender][bidId];
       // require(now > product.auctionStartTime);
        require(!currBid.isRevealed);
        require(currBid.bidder > 0);

        currBid.isRevealed = true;

        uint confusePrice = currBid.price;

        uint refund = 0;
        uint idealPrice = stringToUint(_idealPrice);
        if (confusePrice < idealPrice) {
            //路径1：无效交易
            refund = confusePrice;
        } else {
            if (idealPrice > product.highestBid) {
                if (product.highestBidder == 0) {
                    //当前账户是第一个揭标人
                    //路径2：
                    product.highestBidder = msg.sender;
                    product.highestBid = idealPrice;
                    product.secondHighestBid = product.startPrice;
                    refund = confusePrice - idealPrice;
                } else {
                    //路径3：出价更高
                    product.highestBidder.transfer(product.highestBid);
                    product.secondHighestBid = product.highestBid;
                    product.highestBid = idealPrice;
                    product.highestBidder = msg.sender;
                    refund = confusePrice - idealPrice;
                }
            } else {
                //路径4：价格低于最高价
                if (idealPrice > product.secondHighestBid) {
                    //路径4：更新次高价
                    product.secondHighestBid = idealPrice;
                    refund = confusePrice;
                } else {
                    //路径5：
                    refund = confusePrice;
                }
            }

        }

        emit revealEvent(_productId, bidId, confusePrice, currBid.price, refund);

        if (refund > 0) {
            msg.sender.transfer(refund);
        }
    }
    
    function stringToUint(string s) private pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 48 && b[i] <= 57) {
                result = result * 10 + (uint(b[i]) - 48);
            }
        }
        return result;
    }
    
    function getHighestBidInfo(uint _productId) public view returns(address, uint, uint) {
        Product memory product = stores[productIdToOwner[_productId]][_productId];
        return (product.highestBidder, product.highestBid, product.secondHighestBid);
    }
    
    
    mapping(uint => address) public productToEscrow;
    
    function finalizeAuction(uint _productId) public {
        Product storage product = stores[productIdToOwner[_productId]][_productId];
        address buyer = product.highestBidder;
        address seller = productIdToOwner[_productId];
        address arbiter = msg.sender;
        require(arbiter != buyer && arbiter != seller);
        //require(now > product.auctionEndTime);

        require(product.status == ProductStatus.Open);

        if (product.totalBids == 0) {
            product.status = ProductStatus.Unsold;
        } else {
            product.status = ProductStatus.Sold;
        }

        address escrow = (new Escrow).value(product.secondHighestBid)(buyer, seller, arbiter);
        productToEscrow[_productId] = escrow;
        buyer.transfer(product.highestBid - product.secondHighestBid);
    }
    
        function getEscrowInfo(uint _productId) public view returns (address, address, address, uint, uint) {
        address escrow = productToEscrow[_productId];
        Escrow instanceContract = Escrow(escrow);
        return instanceContract.escrowInfo();
    }

    function giveToSeller(uint _productId) public {
        Escrow(productToEscrow[_productId]).giveMoneyToSeller(msg.sender);
    }

    function giveToBuyer(uint _productId) public {
        Escrow(productToEscrow[_productId]).giveMoneyToBuyer(msg.sender);
    }
}

contract Escrow {

    // 属性：
    // 1. 买家
    address buyer;
    // 2. 卖家
    address seller;
    // 3. 仲裁人
    address arbiter;
    // 4. 卖家获得的票数
    uint sellerVotesCount;
    // 5. 买家获得的票数
    uint buyerVotesCount;
    // 6. 标记某个地址是否已经投票
    mapping(address => bool) addressVotedMap;

    // 7.
    bool isSpent = false;

    constructor(address _buyer, address _seller, address _arbiter) public payable {
        buyer = _buyer;
        seller = _seller;
        arbiter = _arbiter;
    }

    // 方法：
    function giveMoneyToSeller(address caller)  callerRestrict(caller) public {
        require(!addressVotedMap[caller]);
        addressVotedMap[caller] = true;
        require(!isSpent);
        //sellerVotesCount++;
        if (++sellerVotesCount == 2 ) {
            isSpent = true;
            seller.transfer(address(this).balance);
        }
    }

    function giveMoneyToBuyer(address caller) callerRestrict(caller) public {
        require(!addressVotedMap[caller]);
        addressVotedMap[caller] = true;
        require(!isSpent);
        if (++buyerVotesCount == 2) {
            buyer.transfer(address(this).balance);
        }
    }

    function getBalance () public view returns (uint) {
        return this.balance;
    }

    modifier callerRestrict(address caller ) {
        require(caller == seller || caller == buyer || caller == arbiter);
        _;
    }

    function escrowInfo() public view returns(address, address, address, uint, uint) {
        return (buyer, seller, arbiter, buyerVotesCount, sellerVotesCount);
    }
}

