// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;

import "./interfaces/IPriceOracleGetter.sol";

import "./tokenization/GovernedERC20.sol";

import "./libraries/WadRayMath.sol";



struct UserReserveData {

        //amount of collateral deposited by user
        uint256 collateralAmount;

        //amount of syntheticToken minted
        uint256 borrowBalance;
        
    }


//parameters for initializing a CollateralizedTokenPool
struct CollateralizedTokenPoolInfo{
    
    
    //tokens
    GovernedERC20 syntheticToken;
    GovernedERC20 interestBearingToken;
    IERC20 collateralToken;
    
    
    //price oracles
    address asset; //asset we are tracking
    IPriceOracleGetter assetPrice;
    IPriceOracleGetter syntheticAssetPrice;

    //interest rates
    
    //how often interst rate is adjusted
    uint256 periodDuration;
    
    //default inflation
    uint256 inflationRate;//should be a RAY
    uint256 inflationStart;//timestamp when inflation == 100%
    uint256 scalingFactor; //should be a RAY (think 10% is a good amount)
    /*
    newInterestRate=oldInterstRate+(syntheticPrice/targetPrice-1)*scalingFactor
    */
    //default interest rate (this is a Ray!)
    uint256 startingInterestRate;
    //maximum interest rate  (this is a Ray!)
    uint256 maximumInterestRate;
    //maximum change per period
    uint256 maximumInterestRateChangePerPeriod;
    
    //amount of overcollateralization to avoid liquidation
    uint256 overCollateralization; //this is a ray (probably default to 150%)
    uint256 liquidationPenalty; //this is a ray (probably default to 115%)
    

}



contract CollateralizedTokenPool{
    
    /*
     This pool allows people to deposit collateral and mint syntheticToken
     it also allows them to stake syntheticToken and mint interestBearingToken
     
     Minting syntheticToken creates a debt against which interest is continously
     charged.
     This interest is paid to the holders of interestBearingToken which increases in value
     relative to syntheticToken over time.
     
     The following equalities should always hold
     userData[TOTAL_SUPPLY].borrowBalance * borrowPrice() == syntheticToken.totalSuppy()
     syntheticToken.balanceof(address(this)) == interestBearingToken.tokens()*interestBearingPrice();
     
     interestChargedThisPeriod == interestPaidThisPeriod
    
    
    */
    
    using WadRayMath  for uint256;
    using SafeMath  for uint256;
    
    address owner;
    
    //keep track of users
    mapping(address=>UserReserveData) userData;

    //keep track of interest on borrowed/staked synethetic token
    uint40 lastUpdateTimestamp;
    
    //how often iterest rate is updated
    uint256 lastPeriodStartTime;
    uint256 interestRate;//Should be  a RAY
    
    //keep track of insolvency
    mapping (address=>bool) insolventCreators;
    uint256 insolventCount;

    CollateralizedTokenPoolInfo _poolInfo;

    address constant TOTAL_SUPPLY=address(0);

    constructor() public{
        CollateralizedTokenPoolInfo memory poolInfo;
        _poolInfo=poolInfo;
        //initalize userData[0] where were store the total liquidity
        //pretty sure these lines are useless since default values are already 0;
        userData[TOTAL_SUPPLY].borrowBalance=0;
        userData[TOTAL_SUPPLY].collateralAmount=0;
        //period start time
        lastPeriodStartTime=block.timestamp;
        
        owner=msg.sender;
    }
    
    function setupTokens(
            GovernedERC20 syntheticToken,
            GovernedERC20 pooledToken,
            IERC20 collateralToken,
            address asset,
            IPriceOracleGetter assetPrice,
            IPriceOracleGetter syntheticAssetPrice
        ) public{
        require(msg.sender==owner);
        //tokens
        _poolInfo.syntheticToken=syntheticToken;
        _poolInfo.interestBearingToken=pooledToken;
        _poolInfo.collateralToken=collateralToken;
        //price oracles
        _poolInfo.asset=asset; //asset we are tracking
        _poolInfo.assetPrice=assetPrice;
        _poolInfo.syntheticAssetPrice=syntheticAssetPrice;
            
    }
    
    function setupInterestRate(
            uint256 periodDuration,
            uint256 inflationRate,
            uint40 inflationStart,
            uint256 scalingFactor,
            uint256 startingInterestRate,
            uint256 maximumInterestRate,
            uint256 maximumInterestRateChangePerPeriod,
            uint256 overCollateralization,
            uint256 liquidationPenalty
        
        ) public{
        require(msg.sender==owner);
        //how often interst rate is adjusted
        _poolInfo.periodDuration=periodDuration;
        //default inflation
        _poolInfo.inflationRate=inflationRate; //5% //should be a RAY
        _poolInfo.inflationStart=inflationStart;
        _poolInfo.scalingFactor=scalingFactor; //should be a RAY (think 10% is a good amount)
        //default interest rate (this is a Ray!)
        _poolInfo.startingInterestRate=startingInterestRate; // 5% to match inflation rate
        //maximum interest rate  (this is a Ray!)
        _poolInfo.maximumInterestRate=maximumInterestRate;//setting a cap on interest at 100%
        //maximum change per period
        _poolInfo.maximumInterestRateChangePerPeriod=maximumInterestRateChangePerPeriod; //setting to 10% (interset rates can increase by an absolute amount of 10%)
        //amount of overcollateralization to avoid liquidation
        _poolInfo.overCollateralization=overCollateralization; //this is a ray (probably default to 150%)
        _poolInfo.liquidationPenalty=liquidationPenalty; //this is a ray (probably default to 115%)
    }
    
    
    event InterestAccumulated(uint256 interestPerSecond, uint256 totalInterest, uint256 totalSupply, uint256 amountToMint);
    
    /*
      Calculate how much new syntheticToken must be minted and added to contract
    */
    function accumulateInterest() public  returns (uint256){
        
        uint256 one=1;
        
        if(_poolInfo.interestBearingToken.totalSupply()==0 || insolventCount>0){
            //don't accumulate interest if there's no one to pay or market is broken
            return 0;
            
        }else{
            
            uint256 secondsPerYear=31556952;
            uint256 expBasePerSecond = one.asRay().add(interestRate).rayPow(one.asRay().rayDiv(secondsPerYear.asRay()));
            uint256 totalInterest=WadRayMath.rayPow(expBasePerSecond,uint256(block.timestamp-lastUpdateTimestamp).asRay());
            
            //apply interest to borrowers
            //lastBorrowCumulativeIndex=lastBorrowCumulativeIndex.rayMul(totalInterest);
            
            uint amountToMint=_poolInfo.syntheticToken.totalSupply().asRay().rayMul(totalInterest)/WadRayMath.RAY-_poolInfo.syntheticToken.totalSupply();
            
            emit InterestAccumulated(expBasePerSecond,totalInterest,_poolInfo.syntheticToken.totalSupply(),amountToMint);
            
            return amountToMint;
            
        }
        
    }
    
    function applyInterestGrowth() public{
        
        //calculate how much interest has accumulated
        uint256 borrowGrowth=accumulateInterest();
    
        //all interest is paid directly to this contract (to be distributed later among stakers)    
        _poolInfo.syntheticToken.mint(address(this),borrowGrowth);
        
        //also distribue fees to owner
        
        lastUpdateTimestamp=uint40(block.timestamp);
    }
    

    function updateInterestRate() public{
        
        
        applyInterestGrowth();
        
        
        //wait until new period
        require(block.timestamp>lastPeriodStartTime+_poolInfo.periodDuration,"Must wait until next period!");

        //move to next period
        lastPeriodStartTime=block.timestamp;


        //inflation
        uint256 targetPrice=_poolInfo.assetPrice.getAssetPrice(_poolInfo.asset);
        //TODO: some magic here to make this a 1-day average
        uint256 currentPrice=_poolInfo.syntheticAssetPrice.getAssetPrice(address(_poolInfo.syntheticToken));
        
        //floating point implementation
        /*
        if(currentPrice>targetPrice){
            uint256 interestAdjustment=min(1.0,(currentPrice/targetPrice)-1.0);
            interestRate=max(0,interstRate-interestAdjustment)
        }else{
            uint256 interestAdjustment=min(1.0,(targetPrice/currentPrice)-1.0);
            interestRate=min(100,interstRate+interestAdjustment)
        };
        */
        if(currentPrice>targetPrice){
            //interestAdjustment=min(100,(currentPrice*100/targetPrice)-100);
            uint256 priceRatio=currentPrice.asRay().rayDiv(targetPrice.asRay())-WadRayMath.ray();
            uint256 interestAdjustment=priceRatio.rayMul(_poolInfo.scalingFactor);
            //maximumInterestRateChangePerPeriod
            if(interestAdjustment>_poolInfo.maximumInterestRateChangePerPeriod) interestAdjustment=_poolInfo.maximumInterestRateChangePerPeriod;
            if(interestRate<interestAdjustment) interestRate=0;//interest rate cannot go below 0% APR
            else interestRate-=interestAdjustment;
        }else{
            uint256 priceRatio=targetPrice.asRay().rayDiv(currentPrice.asRay())-WadRayMath.ray();
            uint256 interestAdjustment=priceRatio.rayMul(_poolInfo.scalingFactor);
            if(interestAdjustment>_poolInfo.maximumInterestRateChangePerPeriod) interestAdjustment=_poolInfo.maximumInterestRateChangePerPeriod;
            if(interestRate+interestAdjustment>_poolInfo.maximumInterestRate) interestRate=_poolInfo.maximumInterestRate;
            else interestRate+=interestAdjustment;
        }


        //set lastUpdateTimestamp
        lastUpdateTimestamp=uint40(block.timestamp);


    }
    
    
    
    
    
    //userData[TOTAL_SUPPLY].borrowAmount*borrowPrice=syntheticToken.totalSupply()
    function _synthToBorrow(uint256 syntheticAmount) private view returns(uint256){
        //need to make sure we are up-to-date
        require(lastUpdateTimestamp==block.timestamp);
        
        uint256 borrowAmount;
        if(_poolInfo.syntheticToken.totalSupply()==0) borrowAmount = syntheticAmount;//can't divide by 0
        else borrowAmount = syntheticAmount.mul(userData[TOTAL_SUPPLY].borrowBalance).div(_poolInfo.syntheticToken.totalSupply());
        return borrowAmount;
    }
    
    //userData[TOTAL_SUPPLY].borrowAmount*borrowPrice=syntheticToken.totalSupply()
    function _borrowToSynth(uint256 borrowAmount) private view returns(uint256){
        //need to make sure we are up-to-date
        require(lastUpdateTimestamp==block.timestamp);
        
        uint256 syntheticAmount;
        if(userData[TOTAL_SUPPLY].borrowBalance==0) syntheticAmount = borrowAmount;//can't divide by 0
        else syntheticAmount =  borrowAmount.mul(_poolInfo.syntheticToken.totalSupply()).div(userData[TOTAL_SUPPLY].borrowBalance);
        
        return syntheticAmount;
    }
    
    
    //interestBearingToken.totalSupply()*stakeAmount==syntheticToken.balanceOf(address(this))
    function _synthToStake(uint256 syntheticAmount) private view returns(uint256){
        //need to make sure we are up-to-date
        require(lastUpdateTimestamp==block.timestamp);
        
        uint256 stakeAmount;
        if(_poolInfo.syntheticToken.balanceOf(address(this)) == 0 ) stakeAmount = syntheticAmount;//can't divide by 0
        else stakeAmount =  syntheticAmount.mul(_poolInfo.interestBearingToken.totalSupply()).div(_poolInfo.syntheticToken.balanceOf(address(this)));
        
        return stakeAmount;
    }
    
    
    //interestBearingToken.totalSupply()*stakeAmount==syntheticToken.balanceOf(address(this))
    function _stakeToSynth(uint256 stakeAmount) private view returns(uint256){
        //need to make sure we are up-to-date
        require(lastUpdateTimestamp==block.timestamp);
        
        uint256 syntheticAmount;
        if(_poolInfo.interestBearingToken.totalSupply()==0) syntheticAmount = stakeAmount;//can't divide by 0
        else stakeAmount =  syntheticAmount.mul(_poolInfo.syntheticToken.balanceOf(address(this))).div(_poolInfo.interestBearingToken.totalSupply());
        
        return syntheticAmount;
    }
    
    
    //make sure user has enough collateral to cover debt
    function _sufficientCollateral(uint256 collateralAmount, uint256 borrowAmount) private view returns(bool){
        
        
        uint256 priceSynth = _poolInfo.assetPrice.getAssetPrice(_poolInfo.asset);
        
        uint256 syntheticAmount=_borrowToSynth(borrowAmount);
        
        return WadRayMath.ray().rayMul(collateralAmount.asRay()).rayDiv(_poolInfo.overCollateralization)>=priceSynth.asRay().rayMul(syntheticAmount);
        
        
    }
    
    //return the amount of collateral earned by liquidating syntheticAmount from user (assuming this is legal)
    
    function _computeLiquidationAmount(address user, uint256 syntheticAmount) private view returns(uint256){
        
        uint256 priceSynth = _poolInfo.assetPrice.getAssetPrice(_poolInfo.asset);
        
        uint256 liquidationAmount;
        
        //check if user has sufficent collateral to cover all liquidations
        uint256 synthTotalForLiquidation = _borrowToSynth(userData[user].borrowBalance.asRay());
        //this is the price (in collateral) of the user's entire debt
        uint256 totalLiquidationCost=(priceSynth.asRay().rayMul(synthTotalForLiquidation).rayMul(_poolInfo.liquidationPenalty))/WadRayMath.ray();//note we do some RAY math, but want result as a uint256
        if(totalLiquidationCost<userData[user].collateralAmount){
            //send collateral equal to syntheticAmount*overCollateralization*priceSynth/priceCollateral
            liquidationAmount = (priceSynth.asRay().rayMul(syntheticAmount.asRay()).rayMul(_poolInfo.liquidationPenalty))/WadRayMath.RAY;
        }else{
            //send fraction proportional to fraction of debt liquidated
            liquidationAmount=userData[user].collateralAmount.asRay().rayMul(syntheticAmount.asRay()).rayDiv(synthTotalForLiquidation.asRay())/WadRayMath.RAY;
        }
        
        return liquidationAmount;
        
    }
    
    


    //stablecoin interface
    //mint $amount of stablecoin
    function mintStablecoin(uint syntheticAmount) public{

        applyInterestGrowth();

        //mint token
        _poolInfo.syntheticToken.mint(msg.sender,syntheticAmount);
        
        uint256 borrowAmount=_synthToBorrow(syntheticAmount);
        
        //todo: update userData
        userData[msg.sender].borrowBalance+=borrowAmount;
        userData[TOTAL_SUPPLY].borrowBalance+=borrowAmount;
        
        //require that the user has sufficent collateral to manage their debt
        require(_sufficientCollateral(userData[msg.sender].collateralAmount,userData[msg.sender].borrowBalance));

    }

    //opposite of mint action
    // the user burns $amount of stablecoin
    function burnStablecoin(uint syntheticAmount) public{

         _burnStablecoin(msg.sender, syntheticAmount);
        

    }
    
    
    //opposite of mint action
    // the user burns $amount of stablecoin
    function _burnStablecoin(address account, uint syntheticAmount) private{
        
        applyInterestGrowth();

        //borrowAmount*borrowPrice=syntheticAmount
        //borrow price=syntheticToken.totalSupply()/userData[TOTAL_SUPPLY].borrowAmount;
        uint256 borrowAmount=_synthToBorrow(syntheticAmount);
        
        //verify we have enough token to burn
        require(_poolInfo.syntheticToken.balanceOf(account)>syntheticAmount);
        
        _poolInfo.syntheticToken.burn(account,syntheticAmount);

        //update userData
        userData[account].borrowBalance-=borrowAmount;
        userData[TOTAL_SUPPLY].borrowBalance-=borrowAmount;

    }
    
    

    //Todo: add convenience function mintAndStake
    //Todo: add convenience function unstakeAndBurn

    //stake unstake synthetic token
    function stakeSyntheticToken(uint syntheticAmount) public{

        applyInterestGrowth();

        require(_poolInfo.syntheticToken.transferFrom(msg.sender,address(this),syntheticAmount));
        
        //Todo: mint some aToken
        uint256 stakeAmount = _synthToStake(syntheticAmount);
        _poolInfo.interestBearingToken.mint(msg.sender,stakeAmount);

    }

    function withdrawStake(uint syntheticAmount) public{
        
        require(_sufficientCollateral(userData[msg.sender].collateralAmount,userData[msg.sender].borrowBalance));//do I really need to do this check?

        applyInterestGrowth();

        uint256 stakeAmount = _synthToStake(syntheticAmount);

        //make sure user has tokens to burn
        require(_poolInfo.interestBearingToken.balanceOf(msg.sender)>=stakeAmount);
        //burn staked tokens
        _poolInfo.interestBearingToken.mint(msg.sender,stakeAmount);
        

        //transfer syntheticToken from contract to user
        require(_poolInfo.syntheticToken.transferFrom(address(this),msg.sender,syntheticAmount));

    }

    //add reserves
    function depositCollateral(uint collateralAmount) public{
        //transfer collateral from user to contract
        require(_poolInfo.collateralToken.transferFrom(address(this),msg.sender,collateralAmount));
        //update balances
        userData[msg.sender].collateralAmount+=collateralAmount;
        userData[TOTAL_SUPPLY].collateralAmount+=collateralAmount;
    }

    //remove reserves
    function withdrawCollateral(uint collateralAmount) public{

        //make sure we have enough reserves after withdrawal
        require(_sufficientCollateral(userData[msg.sender].collateralAmount-collateralAmount,userData[msg.sender].borrowBalance));
        //transfer collateral from contract to user
        require(_poolInfo.collateralToken.transferFrom(msg.sender,address(this),collateralAmount));
        //update balances
        userData[msg.sender].collateralAmount-=collateralAmount;
        userData[TOTAL_SUPPLY].collateralAmount-=collateralAmount;
        
    }

    //liquidate a minter with insufficient reserves
    function liqiudate(address reserveHolder, uint syntheticAmount) public{
        
        //can only liquidate if user is insolvent
        require(!_sufficientCollateral(userData[msg.sender].collateralAmount,userData[msg.sender].borrowBalance));
        
        //how much of user's debt will be liquidated
        uint256 borrowAmount=_synthToBorrow(syntheticAmount);
        //can't liquidate more than user has borrowed
        require(userData[msg.sender].borrowBalance>=borrowAmount);
        
        uint256 liuidationAmount=_computeLiquidationAmount(reserveHolder, syntheticAmount);
        
        _burnStablecoin(msg.sender,syntheticAmount);
        require(_poolInfo.collateralToken.transferFrom(address(this),msg.sender,liuidationAmount));
        userData[reserveHolder].borrowBalance-=borrowAmount;

    }
    
    //TODO: add an unstakeAndRedeem function to allow people who are insolvent to unstake their staked tokens and become solvent again
    //  should probably disallow unstake otherwise;



    //market failure
    function markInsolvent(address reserveHolder) public{
       //is this account subjet to liquidation?
        require(!_sufficientCollateral(userData[reserveHolder].collateralAmount,userData[reserveHolder].borrowBalance));

        //mark as insolvent and increase count (if not already)
        if(!insolventCreators[reserveHolder]){
            insolventCreators[reserveHolder]=true;
            insolventCount+=1;
        }
    }

    function markSolvent( address reserveHolder) public{

        //verify that reserve holder is solvent
        require(_sufficientCollateral(userData[reserveHolder].collateralAmount,userData[reserveHolder].borrowBalance));

        //mark as not insolvent and increase count (if not already)
        if(insolventCreators[reserveHolder]){
            insolventCreators[reserveHolder]=false;
            insolventCount-=1;
        }

    }

}