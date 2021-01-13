pragma solidity ^0.6.6;


import "./UniswapIPriceOracleGetter.sol";
import "./QuotentOracle.sol";
import "./ReciprocalOracle.sol";
import "./IOracleDeployer.sol";

contract DeployOracle is IDeployOracle{
    
    function quotentOracle(ChainlinkOracle target_USD, ChainlinkOracle collateral_USD, uint256 twentyFourHours) external override returns(IPriceOracleGetter){
        return new QuotentOracle(target_USD,collateral_USD,twentyFourHours);
    }
    
    function uniswapIPriceOracleGetter(address syntheticToken, address collateral, uint256 twentyFourHours, uint8 granularity, address uniswapFactory, uint256 decimals) external override returns(IPriceOracleGetter){
        IPriceOracleGetter sUSD_ETHoracle = new UniswapIPriceOracleGetter(address(syntheticToken), collateral, twentyFourHours, granularity, uniswapFactory , decimals);
        return sUSD_ETHoracle;
    }
    
    function reciprocalOracle(ChainlinkOracle ETH_USD, uint256 twentyFourHours) external override returns(IPriceOracleGetter){
        return new ReciprocalOracle(ETH_USD,twentyFourHours);
    }
    
}
