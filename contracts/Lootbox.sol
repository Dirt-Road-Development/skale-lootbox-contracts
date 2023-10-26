// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * RNG
 */
import { RNG } from "@dirtroad/skale-rng/contracts/RNG.sol";

/**
 * Token Interfaces
 */
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * Contracts to Allow Lootbox to hold assets
 */
// import { IERC721Reciever } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { ERC1155Holder, ERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * ERC-20 Utils
 */
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * Access Interfaces
 */
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import "./Utilities.sol";

error IndexOutOfBounds();

abstract contract Lootbox is RNG, ERC721Holder, ERC1155Holder, AccessControl {

	using SafeERC20 for IERC20;

	// @notice Admin Role to withdraw assets
	bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

	// @notice ASSET_ADDER_ROLE to add assets
	bytes32 public constant ASSET_ADDER_ROLE = keccak256("ASSET_ADDER_ROLE");

	// @notice Manager of Lootbox
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

	// @notice Whitelisted Contracts
	mapping(address => bool) public whitelistedTokens;

	// @notice contract address -> type -> total rewards
	// @dev Should be used to allow for checks on whether an award is activley available
	mapping(address => uint256) public availableRewards;

	// @notice The array of available rewards
	Reward[] public rewards;

	modifier onlyValidAsset(address tokenAddress) {
		if (!whitelistedTokens[tokenAddress]) {
			if (!hasRole(ASSET_ADDER_ROLE, msg.sender)) revert MissingRole({
				role: "ASSET_ADDER_ROLE"
			});
		}
		_;
	}

	modifier onlyAdmin {
		if (!hasRole(ADMIN_ROLE, msg.sender)) revert MissingRole({
			role: "ADMIN_ROLE"
		});
		_;
	}

	modifier onlyManager {
		if (!hasRole(MANAGER_ROLE, msg.sender)) revert MissingRole({
			role: "MANAGER_ROLE"
		});
		_;
	}

	event AddReward(address indexed tokenAddress, RewardType indexed rewardType, uint256 indexed tokenId, uint256 amount);
	event WithdrawReward();
	event WithdrawAllRewards();

	constructor() {
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_grantRole(ADMIN_ROLE, msg.sender);
		_grantRole(ASSET_ADDER_ROLE, msg.sender);
		_grantRole(MANAGER_ROLE, msg.sender);
	}

	/** 
	 * Functions to add:
	 * ERC20
	 * ERC721
	 * ERC1155
	 */
	function addERC20Rewards(IERC20 token, uint256 amount, uint256 rewardSize) external onlyValidAsset(address(token)) {
		if (amount % rewardSize != 0) revert AddTokenError("Amount % Reward != 0");

		/** safeTransferFrom should check this **/
		// if (token.balanceOf(msg.sender) < amount) revert InsufficentBalance({
		// 	token: address(token),
		// 	expected: amount,
		// 	available: token.balanceOf(msg.sender)
		// });

		uint256 i = 0;
		uint256 totalIterations = amount / rewardSize;
		
		address tokenAddress = address(token);

		token.safeTransferFrom(msg.sender, address(this), amount);

		for (i; i < totalIterations; i++) {
			_addReward(tokenAddress, RewardType.ERC20, rewardSize, 0);
		}
	}

	function addERC721Rewards(IERC721 token, uint256[] memory tokenIds) external onlyValidAsset(address(token)) {
		
		address tokenAddress = address(token);

		/** Transfer Each NFT */
		uint256 i = 0;
		for (i; i < tokenIds.length; i++) {
			token.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
			_addReward(tokenAddress, RewardType.ERC721, 1, tokenIds[i]);
		}
	}

	/**
	 * @dev
	 * tokenIds = [ 5, 7, 10 ]
	 * amounts = [ 1, 25, 50 ]
	 * rewardSizes = [ 1, 5, 10 ]
	 * 
	 * for (uint256 i = 0; i < rewardSizes.length; i++) {
	 *   if (amounts % rewardSizes != 0) revert InvalidRewardSize();
	 *   uint256 size = amounts / rewardSizes;
	 *   
	 * }
	 */
	function addERC1155Rewards(IERC1155 token, uint256[] memory tokenIds, uint256[] memory amounts, uint256[] memory rewardSizes) external onlyValidAsset(address(token)) {

		if (tokenIds.length != rewardSizes.length) revert InvalidERC1155ArrayLengths();
		
		uint256 i = 0;
		address tokenAddress = address(token);
		
		uint256[] memory rewardSizesArr = new uint256[](rewardSizes.length);

		for (i; i < rewardSizes.length; i++) {
			if (amounts[i] % rewardSizes[i] != 0) revert InvalidERC1155RewardSize({
				tokenAddress: tokenAddress,
				tokenId: tokenIds[i]
			});
			rewardSizesArr[i] = amounts[i] / rewardSizes[i];
		}

		
		token.safeBatchTransferFrom(msg.sender, address(this), tokenIds, amounts, "");

		uint256 j = 0;
		for (j; j < rewardSizesArr.length; j++) {
			_addReward(tokenAddress, RewardType.ERC1155, rewardSizesArr[j], tokenIds[j]);
		}
	}

	/**
	 * Admin Functions
	 */
	function withdrawReward(uint256 index) external onlyAdmin {
		if (rewards.length - 1 < index) revert IndexOutOfBounds();
		_dynamicTransfer(index, msg.sender);

		emit WithdrawReward();

	}

	function withdrawAllRewards(uint256[] memory indexes) external onlyAdmin {
		while (rewards.length > 0) {
			_dynamicTransfer(rewards.length - 1, msg.sender);
		}

		emit WithdrawAllRewards();
	}

	function _drawFromLootbox(address to) internal {
		uint256 randomIndex = getRandomRange(rewards.length);
		_dynamicTransfer(randomIndex, to);
	}

	function _dynamicTransfer(uint256 index, address to) internal {
		Reward memory reward = rewards[index];

		if (reward.rewardType == RewardType.ERC20) {
			IERC20(reward.tokenAddress).safeTransferFrom(address(this), to, reward.amount);
		} else if (reward.rewardType == RewardType.ERC721) {
			IERC721(reward.tokenAddress).safeTransferFrom(address(this), to, reward.tokenId, "");
		} else if (reward.rewardType == RewardType.ERC1155) {
			IERC1155(reward.tokenAddress).safeTransferFrom(address(this), to, reward.tokenId, reward.amount, "");
		} else {
			revert InvalidRewardType();
		}

		rewards[index] = rewards[rewards.length - 1];
		rewards.pop();
	}

	/**
	 * Internal Functions
	 */
	function _addReward(address tokenAddress, RewardType rewardType, uint256 rewardSize, uint256 tokenId) internal {
		
		rewards.push(Reward(tokenAddress, rewardType, rewardSize, tokenId));

		emit AddReward(tokenAddress, rewardType, tokenId, rewardSize);
	}

	function _getAvailableRewardsLength() internal view returns (uint256) {
		return rewards.length;
	}

	function supportsInterface(bytes4 interfaceId)
	    public
	    view
	    virtual
	    override(AccessControl, ERC1155Receiver)
	    returns (bool)
	  {
	    return 
	    	AccessControl.supportsInterface(interfaceId) ||
	      	ERC1155Receiver.supportsInterface(interfaceId);
	  }
}