// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Utilities.sol";
import "./Lootbox.sol";

error CannotClaimDuringCooldown();
error MaximumClaimsExceeded();
error ProofOfWorkRequiresEOA();
error ProofOfWorkRequiresNoBalance();

contract FreeLootbox is Lootbox {

	bool public timelockCooldown;
	bool public requireProofOfWork;
	uint64 public cooldownPeriod;
	uint256 public maximumMintsPerAddress;

	// @notice One & Unlimited Management
	mapping(address => uint256) public mintsByAddress;

	// @notice Timelock Management
	mapping(address => uint64) public lastClaimByAddress;

	modifier onlyProoOfWork(address addr) {
		if (requireProofOfWork) {
			if (!_isContract(addr)) revert ProofOfWorkRequiresEOA();
			if (address(addr).balance != 0) revert ProofOfWorkRequiresNoBalance();
		}
		_;
	}
	
	modifier onlyValidClaims(address addr) {
		if (mintsByAddress[addr] >= maximumMintsPerAddress) revert MaximumClaimsExceeded();
		_;
	}

	modifier onlyValidTime(address addr) {
		if (timelockCooldown) {
			if (uint64(block.timestamp + cooldownPeriod) < lastClaimByAddress[addr]) revert CannotClaimDuringCooldown();
		}
		_;
	}

	event Draw();
	event ToggleCooldown();
	event ToggleProofOfWork();
	event SetCooldownPeriod();
	event SetMaxmimumMintsPerAddress();

	function draw() external onlyProoOfWork(msg.sender) onlyValidClaims(msg.sender) onlyValidTime(msg.sender) {
		_draw(msg.sender);
	}

	function draw(address to) external onlyProoOfWork(msg.sender) onlyValidClaims(msg.sender) onlyValidClaims(to) onlyValidTime(msg.sender) onlyValidTime(to) {
		_draw(to);
	}


	/**
	 * Admin Functions
	 */
	function toggleCooldown() external onlyManager {
		timelockCooldown = !timelockCooldown;
		emit ToggleCooldown();
	}

	function toggleProofOfWork() external onlyManager {
		requireProofOfWork = !requireProofOfWork;
		emit ToggleProofOfWork();
	}

	function setCooldownPeriod(uint64 newCooldownPeriod) external onlyManager {
		cooldownPeriod = newCooldownPeriod;
		emit SetCooldownPeriod();
	}

	function setMaxmimumMintsPerAddress(uint256 newMaxmimum) external onlyManager {
		maximumMintsPerAddress = newMaxmimum;
		emit SetMaxmimumMintsPerAddress();
	}


	/**
	 * Internal Functions
	 */
	function _draw(address to) internal {
		_drawFromLootbox(to);

		if (timelockCooldown) lastClaimByAddress[msg.sender] = uint64(block.timestamp);
		mintsByAddress[msg.sender] += 1;

		emit Draw();
	}

	function _isContract(address _address) internal returns (bool) {
	  	uint32 size;
	  	assembly {
	    	size := extcodesize(_address)
	 	}
	 	return (size > 0);
	}
}