// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error AddTokenError(string err);
error InvalidERC1155ArrayLengths();
error MissingRole(string role);
error InvalidERC1155RewardSize(address tokenAddress, uint256 tokenId);
error InvalidRewardType();

enum RewardType {
	ERC20,
	ERC721,
	ERC1155
}

struct Reward {
	address tokenAddress;
	RewardType rewardType;
	uint256 amount;
	uint256 tokenId; /// Defaults to 0 for ERC-20
}

enum FreeWithdrawType {
	OnePerAddress,
	TimeLock,
	Unlimited
}

enum OwnershipWithdrawType {
	ERC20,
	ERC721,
	ERC1155
}