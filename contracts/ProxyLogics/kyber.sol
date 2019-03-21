pragma solidity 0.5.0;


import "./safemath.sol";

interface IERC20 {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface AddressRegistry {
    function getAddr(string calldata name) external view returns (address);
}

interface Kyber {
    // Kyber's trade function
    function trade(address src, uint srcAmount, address dest, address destAddress, uint maxDestAmount, uint minConversionRate, address walletId) external payable returns (uint);
    // Kyber's Get expected Rate function
    function getExpectedRate(address src, address dest, uint srcQty) external view returns (uint, uint);
}


contract Registry {
    address public addressRegistry;
    modifier onlyAdmin() {
        require(msg.sender == _getAddress("admin"), "Permission Denied");
        _;
    }
    function _getAddress(string memory name) internal view returns (address) {
        AddressRegistry addrReg = AddressRegistry(addressRegistry);
        return addrReg.getAddr(name);
    }
}


contract Trade is Registry {
    
    using SafeMath for uint;

    event KyberTrade(address src, uint srcAmt, address dest, uint destAmt, address beneficiary, uint minConversionRate, address affiliate);

    function _getToken(
        address trader,
        address src,
        uint srcAmt,
        address eth
    )
    internal
    returns (uint ethQty)
    {
        if (src == eth) {
            require(msg.value == srcAmt, "Invalid Operation");
            ethQty = srcAmt;
        } else {
            IERC20 tokenFunctions = IERC20(src);
            tokenFunctions.transferFrom(trader, address(this), srcAmt);
            ethQty = 0;
        }
    }


    function getExpectedRateKyber(address src, address dest, uint srcAmt) public view returns (uint, uint) {
        Kyber kyberFunctions = Kyber(_getAddress("kyber"));
        return kyberFunctions.getExpectedRate(src, dest, srcAmt);
    }

    function approveKyber(address[] memory tokenArr) public {
        address kyberProxy = _getAddress("kyber");
        for (uint i = 0; i < tokenArr.length; i++) {
            IERC20 tokenFunctions = IERC20(tokenArr[i]);
            tokenFunctions.approve(kyberProxy, 2 ** 256 - 1);
        }
    }

    /**
     * @title Kyber's trade when token to sell Amount fixed
     * @param src - Token address to sell (for ETH it's "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
     * @param srcAmt - amount of token for sell
     * @param dest - Token address to buy (for ETH it's "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
     * @param minDestAmt - min amount of token to buy (slippage)
    */
    function tradeSrcKyber(
        address src, // token to sell
        uint srcAmt, // amount of token for sell
        address dest, // token to buy
        uint minDestAmt // minimum slippage rate
    ) public payable returns (uint tokensBought) {
        address eth = _getAddress("eth");
        uint ethQty = _getToken(
            msg.sender,
            src,
            srcAmt,
            eth
        );

        // Interacting with Kyber Proxy Contract
        Kyber kyberFunctions = Kyber(_getAddress("kyber"));
        tokensBought = kyberFunctions.trade.value(ethQty)(
            src,
            srcAmt,
            dest,
            msg.sender,
            uint(0-1),
            minDestAmt,
            _getAddress("admin")
        );

        emit KyberTrade(src, srcAmt, dest, tokensBought, msg.sender, minDestAmt, _getAddress("admin"));

    }

    function tradeDestKyber(
        address src, // token to sell
        uint maxSrcAmt, // amount of token for sell
        address dest, // token to buy
        uint destAmt // minimum slippage rate
    ) public payable returns (uint tokensBought) {
        address eth = _getAddress("eth");
        uint ethQty = _getToken(
            msg.sender,
            src,
            maxSrcAmt,
            eth
        );

        // Interacting with Kyber Proxy Contract
        Kyber kyberFunctions = Kyber(_getAddress("kyber"));
        tokensBought = kyberFunctions.trade.value(ethQty)(
            src,
            maxSrcAmt,
            dest,
            msg.sender,
            destAmt,
            destAmt,
            _getAddress("admin")
        );

        // maxDestAmt usecase implementated
        if (src == eth && address(this).balance > 0) {
            msg.sender.transfer(address(this).balance);
        } else if (src != eth) {
            // as there is no balanceOf of eth
            IERC20 srcTkn = IERC20(src);
            uint srcBal = srcTkn.balanceOf(address(this));
            if (srcBal > 0) {
                srcTkn.transfer(msg.sender, srcBal);
            }
        }

        emit KyberTrade(src, maxSrcAmt, dest, tokensBought, msg.sender, destAmt, _getAddress("admin"));

    }

}


contract InstaKyber is Trade {
    constructor(address rAddr) public {
        addressRegistry = rAddr;
    }

    function() external payable {}

}