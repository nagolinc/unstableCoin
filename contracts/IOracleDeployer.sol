pragma solidity ^0.6.6;

import "./interfaces/IPriceOracleGetter.sol";
import "./IChainlink.sol";

interface IDeployOracle{
    
    function quotentOracle(ChainlinkOracle target_USD, ChainlinkOracle collateral_USD, uint256 twentyFourHours) external returns(IPriceOracleGetter);
    
    function uniswapIPriceOracleGetter(address syntheticToken, address collateral, uint256 twentyFourHours, uint8 granularity, address uniswapFactory, uint256 decimals) external returns(IPriceOracleGetter);
    
    function reciprocalOracle(ChainlinkOracle ETH_USD, uint256 twentyFourHours) external returns(IPriceOracleGetter);
    
}
