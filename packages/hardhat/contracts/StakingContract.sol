//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Useful for debugging. Remove when deploying to a live network.
import "hardhat/console.sol";

// Use openzeppelin to inherit battle-tested implementations (ERC20, ERC721, etc)
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title W3MTokenInterface
 * @dev Interface for interacting with the W3M token.
 */
interface W3MTokenInterface {
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function balanceOf(address guy) external view returns (uint);
}

contract StakingContract is Ownable, ReentrancyGuard  {

	///////////////SMART CONTRACT VARIABLES///////////////
	
    // Contract-level variables for tracking rewards and staking data
    uint256 public currentTokenSupplyForRewards; // Tracks available reward tokens
    uint256 public totalStakedTokens; // Total tokens currently staked
    uint256 public rewardRatePerMonth; // Reward rate as a percentage per month
    uint256 public minimumStakingPeriodInDays; // Minimum staking duration in days
    uint256 public earlyUnstakePenalization; // Penalty applied for early unstaking

    // Addresses for key contract interactions
    address public whiteListerAddress; // Address authorized to manage whitelist
    address public w3MTokenAddress; // Address of the W3M token contract

    // Mappings to track investor whitelist status and staking data
    mapping(address => bool) public investorsWhiteList; // Whitelist for approved investors
    mapping(address => StakerData) public stakerData; // Staking data for each investor

    // Struct to hold individual investor's staking details
    struct StakerData {
        uint256 currentStakingByInvestor; // Current staked amount by the investor
        uint256 givenStakingRewardsToInvestor; // Total rewards given to the investor so far
        uint256 lastStakingRewardGivenToInvestor; // Amount of the last reward given
        uint256 lastStakedTimestamp; // Timestamp of the last staking action
        string bitcoinRewardAddresses; // Investor's Bitcoin address for rewards
    }

	/**
     * @dev Declaration of W3M token interface.
     */
    W3MTokenInterface public w3MToken;

    // Events to log contract activities for transparency
    event AddedToWhiteList (address investorAddress, address sender);
    event RemovedFromWhiteList (address investorAddress, address sender);
    event DepositedStaking (uint256 _amount, address investorAddress);
    event RetiredStaking (uint256 _amount, address investorAddress, uint256 secondsStaked);
    event ClaimedStakingRewards (uint256 _amount, address investorAddress);
    event FeededTokensForRewards (uint256 _amount);
    event RetiredTokensForRewards (uint256 _amount);
    event UpdatedW3MTokenAddress (address _newW3MTokenAddress);
    event UpdatedBitcoinRewardsAddress (string _newRewardsAddress);
    event UpdatedRewardRatePerMonth (uint256 _newRewardRate);
    event UpdatedMinimumStakingPeriod (uint256 _newMinimumStakingPeriod);
    event UpdatedWhitelisterAddress (address _newWhitelisterAddress); 

	///////////////SMART CONTRACT CONSTRUCTOR///////////////

    /**
     * @dev Constructor to initialize the StakingContract.
     */
	constructor() Ownable() {

		// Address of W3M token on the blockchain
        w3MTokenAddress = 0x19a09c6fd7f643b9515C4FfC0B234B5bFc0F2E0F;

		// Implementation of W3M token interface using the specified address
        w3MToken = W3MTokenInterface(w3MTokenAddress);

        // Number of tokens for reward for each staked token: 
        // 150M yearly rewards multiplied by 100**8 to have 8 decimals 
        // then divide it by 8800M the circulating supply, divided by 12 months in a year
        rewardRatePerMonth = SafeMath.div(SafeMath.div(SafeMath.mul(150000000,10000000000), 8800000000),12);

        // Minimum staking period required for investors in days
		minimumStakingPeriodInDays = 30;

        // Penalty percentage applied for early unstaking (5%)
		earlyUnstakePenalization = 5;
	}

    /**
     * @dev Calculate staking rewards based on the staking amount and duration.
     * @param _amount The amount staked.
     * @param _durationInSeconds The duration of staking in seconds.
     * @return The calculated staking rewards.
     */
	function calculateStakingRewards(uint256 _amount, uint256 _durationInSeconds) public view returns (uint256){

        // Convert staking duration to days
        uint256 durationOfStakingInDays = durationInDays(_durationInSeconds);

        //Ensure the minimum staking duration period is met to recieve rewards
        if(durationOfStakingInDays >= minimumStakingPeriodInDays) {

            // Calculate reward per month divding by 100**8 because the rewardRatePerMonth has 8 decimals 
            uint256 stakingRewardPerMonth = SafeMath.div(SafeMath.mul(_amount, rewardRatePerMonth), 10000000000);

            // Calculate duration in months for direct use
            uint256 durationOfStakingInMonths = SafeMath.div(durationOfStakingInDays, 30);

            // Calculate and return total staking reward
            return SafeMath.mul(stakingRewardPerMonth, durationOfStakingInMonths);
        }
        else {
            return 0; // No rewards if duration is below minimum
        }
	}

	/**
     * @dev Function to add an investor's address to the whitelist.
     * @param _investorAddress The address of the investor to be added to the whitelist.
     */
    function addToWhiteList(address _investorAddress) public onlyOwnerOrWhitelister {

        // Ensure that the investor address to add is not the zero address
        require(_investorAddress != address(0), "Investor address to add to the white list can not be the zero address");

        // Ensure that the investor address has not already been added to the white list
        require(investorsWhiteList[_investorAddress] != true, "That investor address has already been added to the white list");

        // Add the investor address to the white list
        investorsWhiteList[_investorAddress] = true;

        //Emit event of adding investor address to whitelist
        emit AddedToWhiteList( _investorAddress, msg.sender);
    }

    /**
     * @dev Function to remove an investor's address from the whitelist.
     * @param _investorAddress The address of the investor to be removed from the whitelist.
     */
    function removeFromWhiteList(address _investorAddress) public onlyOwnerOrWhitelister {

        // Ensure that the investor address to remove is not the zero address
        require(_investorAddress != address(0), "Investor address to remove from the white list can not be the zero address");

        // Ensure that the investor address is registered on the white list
        require(investorsWhiteList[_investorAddress] == true, "That investor address is not registered on the white list");

        // Remove the investor address from the white list
        investorsWhiteList[_investorAddress] = false;

        //Emit event of removing investor address from the whitelist
        emit RemovedFromWhiteList(_investorAddress, msg.sender);
    }

    modifier investorIsOnWhiteList {
        // Ensure that the sender's address is on the white list
        require(investorsWhiteList[msg.sender] == true, "Investor address has not been added to the white list");
        _;
    }

    modifier onlyOwnerOrWhitelister {
        // Ensure that the sender is the owner or the white lister address
        require(msg.sender == owner() || msg.sender == whiteListerAddress, "Function reserved only for the white lister address or the owner");
        _;
    }

    /**
     * @dev Deposit staking tokens into the contract.
     * @param _amount The amount of tokens to stake.
     * @return A boolean indicating the success of the deposit.
     */
	function depositStaking(uint256 _amount) public investorIsOnWhiteList returns (bool) {

        //Amount to stake must be greater than zero
        require(_amount != 0, "Amount must be greater than zero");
        
		//Transfer W3M token to this contract
        bool successReceivingW3M = w3MToken.transferFrom(msg.sender, address(this), _amount);

        // Ensure that the W3M token transfer was successful
        require(successReceivingW3M, "There was an error on receiving the W3M staking");

        // Update the staking time for the current investor
        stakerData[msg.sender].lastStakedTimestamp = block.timestamp;

        // Increase the current staking amount for the investor by the deposited amount
        stakerData[msg.sender].currentStakingByInvestor += _amount;

        // Update the amount of current staked tokes
        totalStakedTokens += _amount;

        //Emit event of investor depositing staking
        emit DepositedStaking(_amount, msg.sender);

        return successReceivingW3M;
	}

    /**
     * @dev Retire staking and receive rewards (if eligible).
     * @return A boolean indicating the success of the retire operation.
     */
    function retireStaking() public investorIsOnWhiteList nonReentrant returns (bool) {

        //Initialize the amount to retire
        uint256 amountToRetire = stakerData[msg.sender].currentStakingByInvestor;

        //Amount to unstake must be greater than zero
        require(amountToRetire != 0, "There is no balance to unstake");
    
        //Calculate the seconds staked to calculate the rewards
        uint256 secondsStaked = block.timestamp - stakerData[msg.sender].lastStakedTimestamp;

        //If the time of staking is less than the minimum staking period in days the investor gets a penalty of 5% 
        if(durationInDays(secondsStaked) < minimumStakingPeriodInDays) {

            uint256 penaltyFee = SafeMath.div(SafeMath.mul(amountToRetire, earlyUnstakePenalization), 100);

            // Update the amount to retire in the function to later transfer the value
            amountToRetire -= penaltyFee;

            // Directly deduct the penalty to later calculate the staking reward
            stakerData[msg.sender].currentStakingByInvestor -= penaltyFee;

            // The penalty charged goes to the token supply for rewards
            currentTokenSupplyForRewards += penaltyFee;

            // Decrease the same fee from the total staked tokens because the penalty charged goes to the token supply for rewards
            totalStakedTokens -= penaltyFee;
        }

        // Claim staking rewards for the investor
        require(claimStakingRewards() == true, "There was an error sending the W3M staking rewards");

        // Decrease the current staking amount for the investor by the amount to unstake
        stakerData[msg.sender].currentStakingByInvestor -= amountToRetire;

        // Decrease the total amount of staked tokens in the smart contract
        totalStakedTokens -= amountToRetire;

		// Send W3M tokens back
        bool successSendingW3MTokensBack = w3MToken.transfer(msg.sender, amountToRetire);

        // Ensure that the W3M token transfer was successful
        require(successSendingW3MTokensBack, "There was an error sending back the W3M staking");

        //Emit event of investor retiring staking
        emit RetiredStaking(amountToRetire, msg.sender, secondsStaked);

        return successSendingW3MTokensBack;
	}

     /**
     * @dev Notify the reward amount and the time until the next reward for a specific investor.
     * @param _investorAddress The address of the investor.
     * @return The calculated staking rewards and the number of days until the next reward.
     */

    function notifyRewardAmountAndNextReward(address _investorAddress) public view returns (uint256, uint256) {

        //Amount staked must be greater than zero
        require(stakerData[_investorAddress].currentStakingByInvestor > 0, "Amount staked must be greater than zero");
        
        // Retrieve the current staking amount for the investor
        uint256 currentStakedAmount = stakerData[_investorAddress].currentStakingByInvestor;

        // Calculate the total time staked in seconds
        uint256 secondsStaked = block.timestamp - stakerData[_investorAddress].lastStakedTimestamp;

         // Convert the total staking duration to days
        uint256 stakingDuration = durationInDays(secondsStaked);

        // Variable to store the number of days until the next reward
        uint256 nextRewards = 0;

        // Check if the duration of staking is greater than the minimum staking period in days  
        if(stakingDuration > minimumStakingPeriodInDays) {

             // Calculate the number of days passed within the current staking period
            uint256 daysPassed = stakingDuration % minimumStakingPeriodInDays;

            // Calculate the number of days until the next reward becomes available
            nextRewards = minimumStakingPeriodInDays - daysPassed;

        } else {
            // Calculate the number of days until the next reward becomes available
            nextRewards = minimumStakingPeriodInDays - stakingDuration;
        }

        // Calculate the staking rewards and return the results
        return (calculateStakingRewards(currentStakedAmount, stakingDuration), nextRewards);
    }

     /**
     * @dev Claim staking rewards for the investor.
     * @return A boolean indicating the success of the claim operation.
     */
    function claimStakingRewards() private investorIsOnWhiteList returns (bool) {

        //Amount staked must be greater than zero to get rewards
        require(stakerData[msg.sender].currentStakingByInvestor > 0, "Amount staked must be greater than zero");

        //Calculate the seconds staked to calculate the rewards
        uint256 secondsStaked = block.timestamp - stakerData[msg.sender].lastStakedTimestamp;

        // Determine rewards based on stake and duration
        uint256 stakingRewards = this.calculateStakingRewards(stakerData[msg.sender].currentStakingByInvestor,  secondsStaked);
 
        // Ensure there are sufficient reward tokens available
        require(stakingRewards <= currentTokenSupplyForRewards, "There are no tokens for rewards, please contact the company team");

        // Reset staking timestamp: Also works as a penalty for early unstaking attempts
        stakerData[msg.sender].lastStakedTimestamp = block.timestamp;

        // Update last staking reward data for the investor
        stakerData[msg.sender].lastStakingRewardGivenToInvestor = stakingRewards;

        // Update total staking reward data for the investor
        stakerData[msg.sender].givenStakingRewardsToInvestor += stakingRewards;

        // Decrease the current token supply for rewards
        currentTokenSupplyForRewards -= stakingRewards;

		//Send W3M reward tokens to investor
        bool successSendingW3MTokenRewards = w3MToken.transfer(msg.sender, stakingRewards);

        // Ensure that the W3M token transfer was successful
        require(successSendingW3MTokenRewards, "There was an error sending the W3M staking rewards");

        //Emit event of investor claiming staking
        emit ClaimedStakingRewards(stakingRewards, msg.sender);

        return successSendingW3MTokenRewards;
	}
    /**
     * @dev Convert seconds to days.
     * @param _durationInSeconds The duration in seconds to be converted.
     * @return The converted duration in days.
     */
    function durationInDays(uint256 _durationInSeconds) public pure returns (uint256) {

        return SafeMath.div(86400*_durationInSeconds, 86400);
    }


    ///////////////SMART CONTRACT OWNER FUNCTIONALITIES///////////////

    /**
     * @dev Feed tokens to increase the supply available for rewards.
     * @param _amount The amount of tokens to be fed.
     * @return A boolean indicating the success of the token feeding operation.
     */
    function feedTokensForRewards(uint256 _amount) public onlyOwner returns (bool) {

        //Amount to feed must be greater than zero
        require(_amount != 0, "Amount to feed must greater than zero");
        
		//Transfer W3M token to this contract
        bool successReceivingW3MTokens = w3MToken.transferFrom(msg.sender, address(this), _amount);

        // Ensure that the W3M token transfer was successful
        require(successReceivingW3MTokens, "There was an error on receiving the W3M tokens");

        // Increase the current tokens for rewards amount by the deposited amount
        currentTokenSupplyForRewards += _amount;

        //Emit event of feeded tokens for rewards
        emit FeededTokensForRewards(_amount);

        return successReceivingW3MTokens;
	}

    /**
     * @dev Retire tokens from the rewards supply.
     * @param _amount The amount of tokens to be retired.
     * @return A boolean indicating the success of the token retirement operation.
     */
    function retireTokensForRewards(uint256 _amount) public onlyOwner returns (bool) {

        //Amount to retire must be greater than zero
        require(_amount != 0, "Amount to retire must greater than zero");

        //Amount to retire must be equal or less than the current tokens amount
        require(_amount <= currentTokenSupplyForRewards, "Amount to retire must be equal or less than the current tokens amount");
        
		//Send back W3M reward tokens to owner
        bool successRetiringW3MTokens = w3MToken.transfer(owner(), _amount);

        // Ensure that the W3M token transfer was successful
        require(successRetiringW3MTokens, "There was an error sending the W3M staking rewards");

        // Decrease the current tokens for rewards amount by the retired amount
        currentTokenSupplyForRewards -= _amount;

        //Emit event of retired tokens for rewards
        emit RetiredTokensForRewards(_amount);

        return successRetiringW3MTokens;
	}

    //////////////UPDATE FUNCTIONALITIES//////////////

    /**
     * @dev Update the address of the W3M token.
     * @param _newTokenAddress The new address of the W3M token.
     * @return A boolean indicating the success of the token address update operation.
     */
    function updateW3MTokenAddress(address _newTokenAddress) public onlyOwner returns (bool) {

        // Validate new token address is not an empty address
        require(_newTokenAddress != address(0), "New token address can not be an empty address");

        // Address of W3M token on the blockchain
        w3MTokenAddress = _newTokenAddress;

		// Implementation of W3M token interface using the specified address
        w3MToken = W3MTokenInterface(w3MTokenAddress);

        // Emit event of updated tokens for rewards
        emit UpdatedW3MTokenAddress(_newTokenAddress);

        return true;
	}

   /**
     * @dev Update the Bitcoin rewards address for an investor.
     * @param _newBitcoinAddress The new Bitcoin address where rewards will be received.
     * @return A boolean indicating the success of the Bitcoin rewards address update operation.
     */
    function updateBitcoinRewardsAddress(string memory _newBitcoinAddress) public investorIsOnWhiteList returns (bool) {
        
        // Validate new bitcoin address is not an empty address
        require(bytes(_newBitcoinAddress).length != 0, "New token address can not be an empty address");

        // Update the bitcoin address of the sender where bitcoin rewards will be received
        stakerData[msg.sender].bitcoinRewardAddresses = _newBitcoinAddress;

        // Emit event of updated bitcoin rewards address
        emit UpdatedBitcoinRewardsAddress(_newBitcoinAddress);

        return true;
	}

    /**
     * @dev Update the reward rate per month for staking rewards.
     * @param _newRewardRatePerMonth The new reward rate per month in percentage (with 8 decimals).
     * @return A boolean indicating the success of the reward rate update operation.
     */
    function updateRewardRatePerMonth(uint256 _newRewardRatePerMonth) public onlyOwner returns (bool) {
        
        // Validate new reward rate per month is not zero
        require(_newRewardRatePerMonth != 0, "New reward rate per month can not be zero");

        // Validate new reward rate per month is less than 10% = 10*10**8 as safety check
        require(_newRewardRatePerMonth < 1000000000, "New reward rate per month must be less than 10 per cent");

        // Update the reward rate per month
        rewardRatePerMonth = _newRewardRatePerMonth;

        // Emit event of updated reward rate per month
        emit UpdatedRewardRatePerMonth(_newRewardRatePerMonth);

        return true;
	}

    /**
     * @dev Update the minimum staking period required for investors.
     * @param _newMinimumStakingPeriodInDays The new minimum staking period in days.
     * @return A boolean indicating the success of the minimum staking period update operation.
     */
    function updateMinimumStakingPeriod(uint256 _newMinimumStakingPeriodInDays) public onlyOwner returns (bool) {
        
        // Validate new mimimum staking period is not zero
        require(_newMinimumStakingPeriodInDays != 0, "New new mimimum staking period can not be zero");

        // Update the reward rate per month
        minimumStakingPeriodInDays = _newMinimumStakingPeriodInDays;

        // Emit event of updated minimum staking period
        emit UpdatedMinimumStakingPeriod(_newMinimumStakingPeriodInDays);

        return true;
	}
    /**
     * 
     * @dev Update the address of the whitelister responsible for investor validation.
     * @param _newWhitelisterAddress The new address of the whitelister.
     * @return A boolean indicating the success of the whitelister address update operation.
     */
    function updateWhitelisterAddress(address _newWhitelisterAddress) public onlyOwner returns (bool) {

        // Validate new whitelister address is not an empty address
        require(_newWhitelisterAddress != address(0), "New whitelister address can not be an empty address");

        // Address of W3M token on the blockchain
        whiteListerAddress = _newWhitelisterAddress;

        // Emit event of updated whiteliser address
        emit UpdatedWhitelisterAddress(_newWhitelisterAddress);

        return true;
	}


	/**
	 * Function that allows the contract to receive ETH
	 */
	receive() external payable {}
}
