pragma solidity ^0.8.0;

interface IProtonPack {
    function addCollaterals(address atoken, address oracle) external;
    function getValue(address onBehalfOf, uint256 i) external view returns(uint256);
    function loanToValue(address onBehalfOf) external view returns(uint256 currentLTV);
    function supplyToken(uint256 i, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdrawToken(uint256 i, uint256 amount) external;
    function borrow(uint256 amount) external;
    function accrueFee() external;
    function repay(uint256 amount, address onBehalfOf) external;
    function repayWithReward(uint256 amount, address onBehalfOf, uint256 assetIndex) external;
    function stakeAave(uint256 _amount) external;
    function claimRewards(uint256 amount) external;
}
