pragma solidity ^0.6.0;


import "./interfaces/IPriceOracleGetter.sol";


contract ConstantPriceOracle is IPriceOracleGetter{
    
    address weth;
    uint256 decimals=18;
    
    constructor (address _weth) public {
        weth=_weth;
    }
    
    function getAssetPrice(address _asset) public view override returns(uint256){
        require(_asset==weth);
        //consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut)
        uint256 amount=10**decimals;
        return amount;
    }
    
}