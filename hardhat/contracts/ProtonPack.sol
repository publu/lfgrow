pragma solidity ^0.8.0;

import "hardhat/console.sol";

/*
	ToDo List

	[ ] debt needs to be calculated from balance of debtToken (not just TotalDebt)
	[ ] charge a flat fee on top of the earned debt token (editable)
	[ ] enable buying risky debt from users
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

contract Engine {	

}
