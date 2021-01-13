pragma solidity ^0.6.6;


import "./CollateralizedTokenPool.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IWETH.sol";
import "./libraries/SafeMath.sol";
import "./IOracleDeployer.sol";

/*

 for our initial deployment, we will use weth as collateral and
 deploy synthetic versions of USD, Euro, Yen

*/

contract DeployUnstableCoin{
    
    using WadRayMath for uint256;
    using SafeMath for uint256;
    
    ChainlinkOracle JPY_USD = ChainlinkOracle(0xBcE206caE7f0ec07b545EddE332A47C2F75bbeb3); // JPY/USD
    ChainlinkOracle EUR_USD = ChainlinkOracle(0x3309C3c1a468125639B2CB5bba264053309ad1D3); //EUR/USD (8 decimals..apparently this is standard)
    ChainlinkOracle ETH_USD = ChainlinkOracle(0xefcbc7ddbdB7204Db12CCcB13b7866d96836a81F); //ETH/USD (8 decimals)
    
    address uniswapFactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniswapRouter02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    CollateralizedTokenPoolInfo info;
    
    uint256 twentyFourHours=60*60*24;
    
    //futile effort to break up the contract into smaller bits
    IDeployOracle oracleDeployer;
    
    constructor(IDeployOracle _oracleDeployer) public{
        oracleDeployer=_oracleDeployer;
    }
    
    
    function create3Pairs() public payable returns(address,address,address){
        createPair(JPY_USD,ETH_USD,weth,
            ["unstable JPY","uJPY","pooledUnstableJPY","puJPY"]);
        createPair(EUR_USD,ETH_USD,weth,
            ["unstable EUR","uEUR","pooledUnstableEUR","puEUR"]);
        createPair(ChainlinkOracle(address(0)),ETH_USD,weth,
            ["unstable USD","uUSD","pooledUnstableUSD","puUSD"]);
    }
    
    event PairCreated(address syntheticToken, address pooledToken, address pool);
    
    
    
    function createPair(ChainlinkOracle target_USD, ChainlinkOracle collateral_USD, address collateral,
        string[4] memory names
    ) private returns(CollateralizedTokenPool){
        
        IPriceOracleGetter targetPrice;
        if(target_USD==ChainlinkOracle(address(0))){
            //targetPrice = new ReciprocalOracle(ETH_USD,twentyFourHours);
            targetPrice = oracleDeployer.reciprocalOracle(ETH_USD,twentyFourHours);
        }else{
            //targetPrice= new QuotentOracle(target_USD,collateral_USD,twentyFourHours);
            targetPrice= oracleDeployer.quotentOracle(target_USD,collateral_USD,twentyFourHours);
        }
        
        GovernedERC20 syntheticToken = new GovernedERC20(names[0],names[1],address(this));
        GovernedERC20 pooledToken = new GovernedERC20(names[2],names[3],address(this));
        
        //create pair
        IUniswapV2Factory(uniswapFactory).createPair(address(syntheticToken), collateral);
        //inital amounts must be correct
        syntheticToken.mint(address(this),1e18);
        uint256 collateralAmount=(targetPrice.getAssetPrice(address(0)));
        //approve
        syntheticToken.approve(uniswapRouter02,1e18);
        IERC20(collateral).transferFrom(msg.sender,address(this),collateralAmount);
        IERC20(collateral).approve(uniswapRouter02,collateralAmount);
        IUniswapV2Router02(uniswapRouter02).addLiquidity(address(syntheticToken),collateral,1e18,collateralAmount,0,0,address(this),block.timestamp+twentyFourHours);
        //create oracle
        //IPriceOracleGetter sUSD_ETHoracle = new UniswapIPriceOracleGetter(address(syntheticToken), collateral, twentyFourHours, 24, uniswapFactory , 18);
        IPriceOracleGetter sUSD_ETHoracle = oracleDeployer.uniswapIPriceOracleGetter(address(syntheticToken), collateral, twentyFourHours, 24, uniswapFactory , 18);
        
        
        //create the pool
        CollateralizedTokenPool pool = createCollateralPool(
            syntheticToken,
            pooledToken,
            targetPrice,
            sUSD_ETHoracle,
            collateral
        );
        
        //give control of tokens to this contract
        syntheticToken.setMaster(address(pool));
        pooledToken.setMaster(address(pool));
        
        emit PairCreated(address(syntheticToken),address(pooledToken),address(pool));
        
        return pool;
        
        
    }
    
    
    function createCollateralPool(
        GovernedERC20 syntheticUSD,
        GovernedERC20 pooledUSD,
        IPriceOracleGetter usdEth,
        IPriceOracleGetter sUSD_ETHoracle,
        address collateral
    ) private returns(CollateralizedTokenPool){
        
        CollateralizedTokenPool usdPool = new CollateralizedTokenPool();
        
        usdPool.setupTokens(
            syntheticUSD,//synthetic token
            pooledUSD,//pooled token
            IERC20(collateral),//collateral token
            address(0),//asset address (0 because this isn't a real asset)
            usdEth,//target asset price
            sUSD_ETHoracle//synthetic asset price
        );
        
        uint256 RAY=WadRayMath.ray();
        
        usdPool.setupInterestRate(
            twentyFourHours, //uint256periodDuration,
            RAY.rayDiv(RAY*20),//uint256 inflationRate,
            uint40(block.timestamp),//uint40 inflationStart,
            RAY.rayDiv(RAY*10),//uint256 scalingFactor,
            RAY.rayDiv(RAY*20),//uint256 startingInterestRate,
            RAY,//uint256 maximumInterestRate,
            RAY.rayDiv(RAY*10), //uint256 maximumInterestRateChangePerPeriod,
            (RAY*150).rayDiv(RAY*100),//uint256 overCollateralization,
            (RAY*115).rayDiv(RAY*100) //uint256 liquidationPenalty
        );
        
        return usdPool;
    }
    
    
    
    
}