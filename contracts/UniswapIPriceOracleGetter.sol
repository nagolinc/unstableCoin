pragma solidity ^0.6.0;


import "./interfaces/IPriceOracleGetter.sol";
import "./ExampleSlidingWindowOracle.sol";
import "./interfaces/IERC20.sol";


contract UniswapIPriceOracleGetter is ExampleSlidingWindowOracle, IPriceOracleGetter{
    
    address tokenA;
    address collateral;
    uint256 decimals;
    
    
    constructor (address _tokenA, address _collateral, uint256 _windowSize, uint8 _granularity, address _factory , uint256 _decimals) 
    ExampleSlidingWindowOracle(_factory,_windowSize,_granularity)
    public {
        collateral=_collateral;
        tokenA=_tokenA;
        decimals=_decimals;
        
    }
    
    function getAssetPrice(address _asset) public view override returns(uint256){
        require(_asset==tokenA);
        //consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut)
        uint256 amount=10**decimals;
        return super.consult(_asset,amount, collateral);
    }
    
}