pragma solidity ^0.6.0;


import "./interfaces/IPriceOracleGetter.sol";

import "./libraries/SafeMath.sol";

import "./IChainlink.sol";


//convert a pair of oracles (e.g. JPY/USD, ETH/USD) into a single oracle
contract ProductOracle is IPriceOracleGetter{
    using SafeMath for uint256;
    
    uint256 decimals=18;
    uint256 window;
    ChainlinkOracle oracleTop;
    ChainlinkOracle oracleBottom;
    
    constructor (ChainlinkOracle _oracleTop, ChainlinkOracle _oracleBottom, uint256 _window) public {
        oracleTop=_oracleTop;
        oracleBottom=_oracleBottom;
        window=_window;
    }
    
    function getAssetPrice(address _asset) public view override returns(uint256){
        require(_asset==address(0));//there isn't a real address for our asset unfortunately
        //consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut)
        
        
        
        (
            ,//uint256 roundID_top, 
            int price_top,
            ,//uint256 startedAt_top,
            uint256 timeStamp_top,
            //uint256 answeredInRound_top
        ) = oracleTop.latestRoundData();
        
        uint256 uprice_top=uint256(price_top);
        
        (
            ,//uint256 roundID_bottom, 
            int price_bottom,
            ,//uint256 startedAt_bottom,
            uint256 timeStamp_bottom,
            //uint256 answeredInRound_bottom
        ) = oracleBottom.latestRoundData();
        
        uint256 uprice_bottom=uint256(price_bottom);
        
        require(timeStamp_top-block.timestamp<window);
        require(timeStamp_bottom-block.timestamp<window);
        
        uint256 amount=10**decimals;
        
        return uprice_top.mul(amount).mul(uprice_bottom);
    }
    
}