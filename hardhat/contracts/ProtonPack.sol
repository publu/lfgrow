pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./IProtonPack.sol";
/*
	ToDo List
    [✅] build an interface for this thing
	[✅] debt needs to be calculated from balance of debtToken (not just TotalDebt)
	[✅] charge a flat fee on top of the earned debt token (editable)
	[✅] enable buying risky debt from users
	[ ] check if aave pauses
	[ ] check supply/borrow caps
	[ ] active/frozen/paused market statuses
		[ ] if active good
		[ ] if frozen?
		[ ] if paused?
	[ ] Implement 4626? 
*/

interface ERC20 {
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success);
    function transfer(address _to, uint256 _value) external returns (bool success);
    function balanceOf(address _owner) external view returns (uint256 balance);
    function approve(address _spender, uint256 _value) external returns (bool success);
}

interface PriceSource {
    function latestRoundData() external view returns (uint256);
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

interface AaveInteractor {
	function depositStkAave ( uint256 depositAmt) external returns( uint256 pAaveAmt);
	function supply (address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
	function borrow ( address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
	function repay ( address GHO, uint256 amount, uint256 interestRateMode, address onBehalfOf) external;
	function withdraw(address tok, uint256 amt, address dst) external;
}

interface StakedAave is ERC20 {
	function stake(address _candidate,uint256 _amount) external;
	function claimRewards(address to, uint256 amount) external;
}

contract ProtonPack is IProtonPack {	

    /*	Groups money together to get better rates for GHO 	*/
	AaveInteractor aave = AaveInteractor(0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951);
	ERC20 gho = ERC20(0xc4bF5CbDaBE595361438F8c6a187bDc330539c60);
	ERC20 aghodebt = ERC20(0x67ae46EF043F7A4508BD1d6B94DB6c33F0915844);
	StakedAave stakedAaveContract = StakedAave(0x47805f115eD9Dffc3506c9cB9805725FAe1cA9d3);
	ERC20 aaveToken = ERC20(0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a);

	uint256 constant MAX_INT = 2**256 - 1;
	// user => underlying asset => aToken held
	mapping (address => uint256) public totalDeposits; // could also do deposits[address(this)] which would have the same effect.
	mapping (address => uint256) public debt;
    address public owner;
	mapping (address => mapping (address => uint256)) public deposits;

	uint256 constant public minLTV = 9_700;
	uint256 constant TEN_THOUSAND = 10_000;
	uint256 public totalDebt;

	uint256 public collatCount;
	mapping(uint256=>address) public allowedCollaterals;
	mapping(uint256=>address) public collateralOracles;

	mapping(address=>uint256) public stakedBalances;
	uint256 public stakedTotal;

	uint256 lastDebtTokenBalance;
	uint256 lastDebtTokenTime;
	uint256 accumulatedTokenBalance;
	uint256 extraFee;

    constructor() {	
    	// aToken, oracle
    	// aToken is 1:1
    	addCollaterals(0x29598b72eb5CeBd806C5dCD549490FdA35B13cD8,0x14866185B1962B63C3Ea9E03Bc1da838bab34C19);
    	extraFee=500; // 0.5%
        owner = msg.sender;
        // add here so we dont need to update contratc later, time's of essense rn
    }


    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function setOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }

    function addCollaterals(address atoken, address oracle) public {
    	allowedCollaterals[collatCount] = atoken; // testNetDai
    	collateralOracles[collatCount] = oracle;  // DAI/USD
    	collatCount+=1;
    }

	function getValue(address onBehalfOf, uint256 i) public view returns(uint256){
	    address asset = allowedCollaterals[i];
	    uint256 price = uint256(PriceSource(collateralOracles[i]).latestAnswer());
	    ERC20 AToken = ERC20(asset);
	    uint256 aTokenBalance = AToken.balanceOf(address(this));
	    return ((deposits[onBehalfOf][asset] * price * aTokenBalance) / totalDeposits[asset] );
	}

	function loanToValue(address onBehalfOf) public view returns(uint256 currentLTV){
	    // if debt is not 0, there must be collateral held by user.    
	    if(debt[msg.sender] > 0){
	        uint256 i = 0;                
	        uint256 value;
	        uint256 count = collatCount;
	        while (i < count) {
	            value += getValue(onBehalfOf, i);
	            i++;
	        }
		    ERC20 AToken = ERC20(aghodebt);
		    uint256 aTokenBalance = AToken.balanceOf(address(this));
		    uint256 currentDebt = ((debt[onBehalfOf] * aTokenBalance) / totalDebt);

	        currentLTV = ( currentDebt * TEN_THOUSAND * (10 ** 8) ) / value;
	    }
	}

	function supplyToken(uint256 i, uint256 amount, address onBehalfOf,uint16 referralCode) public {
		address asset = allowedCollaterals[i];
		ERC20(asset).transferFrom(msg.sender, address(this), amount);
		deposits[onBehalfOf][asset] += amount;
		totalDeposits[asset] += amount;
		uint256 bal = ERC20(asset).balanceOf(address(this));
	}

	function withdrawToken(uint256 i, uint256 amount) public {
		address asset = allowedCollaterals[i];
		require(deposits[msg.sender][asset]>=amount, "withdrawToken: amount cannot be more than deposited");
	    ERC20 AToken = ERC20(asset);
	    uint256 aTokenBalance = AToken.balanceOf(address(this));    
	    uint256 withdrawn = aTokenBalance * amount / totalDeposits[asset];
		deposits[msg.sender][asset] -= amount;
		totalDeposits[asset] -= amount;
	    require(loanToValue(msg.sender) < minLTV, "withdrawToken: ltv cannot be under min");
		ERC20(asset).transfer(msg.sender, withdrawn);
	}

	function borrow(uint256 amount) public {		
		debt[msg.sender]+=amount;
		totalDebt+=amount;
	    ERC20 AToken = ERC20(aghodebt);
	    uint256 aTokenBalanceBefore = AToken.balanceOf(address(this));
		aave.borrow( address(gho), amount, uint256(2), uint16(0), address(this));
        lastDebtTokenBalance += uint128(AToken.balanceOf(address(this)) - aTokenBalanceBefore);
	    require(loanToValue(msg.sender) < minLTV, "borrow: ltv cannot be under min");
		gho.transfer(msg.sender, amount);
	}

	// MOOSE. CHECK in/out
	function accrueFee() public {
	    ERC20 AToken = ERC20(aghodebt);
	    uint256 aTokenBalance = AToken.balanceOf(address(this));
        if (block.timestamp != lastDebtTokenTime) {
            uint256 newVaultBalance = AToken.balanceOf(address(this));
            uint256 newInterest = newVaultBalance > lastDebtTokenBalance ? newVaultBalance - lastDebtTokenBalance : 0;
            uint256 newFeesEarned = newInterest * extraFee / TEN_THOUSAND;
            accumulatedTokenBalance += uint128(newFeesEarned);
            totalDebt += newFeesEarned;
            lastDebtTokenBalance = uint128(newVaultBalance);
            lastDebtTokenTime = uint40(block.timestamp);
        }
	}

	// gets converted from ratio of total debt to amount of debttoken (based on held as well)
	function repay(uint256 amount, address onBehalfOf) public {
	    ERC20 AToken = ERC20(aghodebt);
	    uint256 aTokenBalance = AToken.balanceOf(address(this));
	    uint256 value = ((amount * aTokenBalance) / totalDebt);
		gho.transferFrom(msg.sender, address(this), value);
		gho.approve(address(aave), value);
		aave.repay( address(gho), value, uint256(2), address(this));

		debt[onBehalfOf]-=amount;
		totalDebt-=amount;
	}

	// lets anyone pay someone else's debt and take part of their collateral to improve the loan's health 
    function repayWithReward(uint256 amount, address onBehalfOf, uint256 assetIndex) public {
        uint256 ltv = loanToValue(onBehalfOf);
        require(ltv > minLTV, "repayWithReward: no reward");
        require(ltv <= TEN_THOUSAND, "repayWithReward: bad loan");

        repay(amount, onBehalfOf);

        // Calculate the reward as a percentage of the collateral based on the current LTV and the maximum allowed LTV
        uint256 rewardPercentage = ((TEN_THOUSAND - ltv) * 100) / (TEN_THOUSAND - minLTV);

        // Calculate the collateral value and the reward value for the specific asset
        uint256 collateralValue = getValue(onBehalfOf, assetIndex);
        uint256 rewardValue = (collateralValue * rewardPercentage) / 100;
        uint256 rewardAmount = (deposits[onBehalfOf][allowedCollaterals[assetIndex]] * rewardValue) / collateralValue;

        // Update deposits and total deposits mappings
        deposits[onBehalfOf][allowedCollaterals[assetIndex]] -= rewardAmount;
        totalDeposits[allowedCollaterals[assetIndex]] -= rewardAmount;
        deposits[msg.sender][allowedCollaterals[assetIndex]] += rewardAmount;
    
		uint256 new_ltv = loanToValue(onBehalfOf);
	    require(new_ltv>=9_000, "repayWithReward: cannot repay too much or user loses money");
	    require(ltv>=new_ltv, "repayWithReward: cannot reward for increasing loan ratio");
	}

	// any user can deposit their stkAave. which provides a discount to the other users borrowing through this platform
    function stakeAave(uint256 _amount) external {
    	claimRewards(MAX_INT);
        require(_amount > 0, "Amount must be greater than 0");
        // Transfer AAVE tokens from user to this contract
        stakedAaveContract.transferFrom(msg.sender, address(this), _amount);
        // Update the staked balance for the user
		uint256 what = ( _amount * stakedTotal ) / (stakedAaveContract.balanceOf(address(this)));
        stakedBalances[msg.sender] += what;
        stakedTotal+=_amount; // what users have put in
    }

    function claimRewards(uint256 amount) public {
    	stakedAaveContract.claimRewards(address(this), amount); // increases internal count, not affecting user balances
    }

    // TODO add unstaking 
}