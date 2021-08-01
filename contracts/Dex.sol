pragma solidity 0.8.0; // don't need to use SafeMath Library. This default in solidity 0.8.x

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Dex {
    // describe the Side
    // enum can be casted to interger which means 0 = BUY, 1 = SELL
    enum Side {
        BUY,
        SELL
    }
    // describe the Token
    struct Token {
        bytes32 ticker;// use bytes32 instead of string to utilize storage. Eg: BTC, ETH,BNB,...
        address tokenAddress;
    }
    
    struct Order {
        uint id;
        address trader;
        Side side;
        bytes32 ticker;
        uint amount;
        uint filled; // an order can be filled or partially filled
        uint price; // if market order, price will be empty
        uint date;
    }
    
    mapping(bytes32 => Token) public tokens;
    bytes32[] public tokenList; // list of tickers
    mapping(address => mapping(bytes32 => uint)) public traderBalances;
    mapping(bytes32 => mapping(uint => Order[])) public orderBook;
    address public admin;
    uint public nextOrderId; // used to keep track of the orders
    uint public nextTradeId;// used to keep track of the trades
    bytes32 constant DAI = bytes32('DAI'); // DAI is quote token so we will use a lot, create a costant to reduce gas fee
    
    event NewTrade(
        uint tradeId,
        uint orderId,
        bytes32 indexed ticker, // indexed to search tiker in the front end
        address indexed trader1,
        address indexed trader2,
        uint amount,
        uint price,
        uint date
    );
    
    constructor() {
        admin = msg.sender;
    }
    //return a list of orders based conditions
    function getOrders(
      bytes32 ticker, 
      Side side) 
      external 
      view
      returns(Order[] memory) {
      return orderBook[ticker][uint(side)];
    }
    // return the list of tokens that is supported by the Dex
    function getTokens() 
      external 
      view 
      returns(Token[] memory) {
      Token[] memory _tokens = new Token[](tokenList.length);
      for (uint i = 0; i < tokenList.length; i++) {
        _tokens[i] = Token(
          tokens[tokenList[i]].ticker,
          tokens[tokenList[i]].tokenAddress
        );
      }
      return _tokens;
    }
    // add token the Dex
    function addToken(
        bytes32 ticker,
        address tokenAddress)
        onlyAdmin()
        external {
        tokens[ticker] = Token(ticker, tokenAddress);
        tokenList.push(ticker);
    }
    // call the transferFrom function of the token to execute a deligated transfer
    function deposit(
        uint amount,
        bytes32 ticker)
        tokenExist(ticker)
        external {
        IERC20(tokens[ticker].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        traderBalances[msg.sender][ticker] += amount;
    }
    // call the transfer method of the token and update the balance
    function withdraw(
        uint amount,
        bytes32 ticker)
        tokenExist(ticker)
        external {
        require(
            traderBalances[msg.sender][ticker] >= amount,
            'balance too low'
        ); 
        traderBalances[msg.sender][ticker] -= amount;
        IERC20(tokens[ticker].tokenAddress).transfer(msg.sender, amount);
    }

    function createLimitOrder(
        bytes32 ticker,
        uint amount,
        uint price,
        Side side)
        tokenExist(ticker)
        tokenIsNotDai(ticker)
        external {
        // create limit sell order
        if(side == Side.SELL) {
            //check the balance of the account
            require(
                traderBalances[msg.sender][ticker] >= amount, 
                'token balance too low'
            );
        } else {
            require(
                traderBalances[msg.sender][DAI] >= amount * price,
                'dai balance too low'
            );
        }
        // push the limit order into the order list
        Order[] storage orders = orderBook[ticker][uint(side)];
        orders.push(Order(
            nextOrderId,
            msg.sender,
            side,
            ticker,
            amount,
            0,
            price,
            block.timestamp // 'now' in solidity 0.6.x and older
        ));
        // implement the bubble sort algorithm to sort the list of the order
        uint i = orders.length > 0 ? orders.length - 1 : 0;// short form for if else in solidity
        while(i > 0) {
            // Breaking conditions: for BUY: highest price first, for SELL: opposite, loop break conditions
            if(side == Side.BUY && orders[i - 1].price > orders[i].price) {
                break;   
            }
            if(side == Side.SELL && orders[i - 1].price < orders[i].price) {
                break;   
            }
            Order memory order = orders[i - 1];
            orders[i - 1] = orders[i];
            orders[i] = order;
            i--;
        }
        nextOrderId++; // increament for the next time call create order the order ID is unique
    }
    
    function createMarketOrder(
        bytes32 ticker,
        uint amount,
        Side side)
        tokenExist(ticker)
        tokenIsNotDai(ticker)
        external {
        if(side == Side.SELL) {
            require(
                traderBalances[msg.sender][ticker] >= amount, // can not sell more than you have
                'token balance too low'
            );
        }
        Order[] storage orders = orderBook[ticker][uint(side == Side.BUY ? Side.SELL : Side.BUY)];// access the right order in the order orderBook
        uint i;
        uint remaining = amount;
        // matching process
        while(i < orders.length && remaining > 0) {
            uint available = orders[i].amount - orders[i].filled; // check for available liquidity in the order books
            uint matched = (remaining > available) ? available : remaining; //match all or partially matched
            remaining = remaining - matched;
            orders[i].filled = orders[i].filled + matched;
            emit NewTrade(
                nextTradeId,
                orders[i].id,
                ticker,
                orders[i].trader,
                msg.sender,
                matched,
                orders[i].price,
                block.timestamp
            );
            if(side == Side.SELL) {
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker] - matched;
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI] + (matched * orders[i].price);
                traderBalances[orders[i].trader][ticker] = traderBalances[orders[i].trader][ticker] + matched;
                traderBalances[orders[i].trader][DAI] = traderBalances[orders[i].trader][DAI] - (matched * orders[i].price);
            }
            if(side == Side.BUY) {
                require(
                    traderBalances[msg.sender][DAI] >= matched * orders[i].price,
                    'dai balance too low'
                );
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker] + matched;
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI] - (matched * orders[i].price);
                traderBalances[orders[i].trader][ticker] = traderBalances[orders[i].trader][ticker] - matched;
                traderBalances[orders[i].trader][DAI] = traderBalances[orders[i].trader][DAI] + (matched * orders[i].price);
            }
            nextTradeId++;
            i++;
        }
        
        // iterate through the orderBook and remove filled orders
        i = 0;
        while(i < orders.length && orders[i].filled == orders[i].amount) {
            for(uint j = i; j < orders.length - 1; j++ ) {
                orders[j] = orders[j + 1];
            }
            orders.pop();
            i++;
        }
    }
   
    modifier tokenIsNotDai(bytes32 ticker) {
       require(ticker != DAI, 'cannot trade DAI');
       _;
    }     
    
    modifier tokenExist(bytes32 ticker) {
        require(
            tokens[ticker].tokenAddress != address(0),
            'this token does not exist'
        );
        _;
    }
    
    modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }
}
