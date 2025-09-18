// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {PirateNFTL1} from "../PirateNFTL1.sol";

// Manager Role - Can adjust how contract functions (limits, paused, etc)
bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

// @notice Emitted when the inputs are invalid
error InvalidInputs();

// @notice Emitted when the token amount is zero
error ZeroTokenAmount();

// @notice Emitted when the caller is not the owner of the pirate
error NotPirateOwner();

// @notice Emitted when the founders pirate contract is not set
error NoFoundersPirateContractSet();

/**
 * The PirateBurn contract allows users to burn Gen0 Pirate NFTs in exchange for $PIRATE tokens.
 */
contract PirateBurn is
    Initializable,
    ContextUpgradeable,
    ReentrancyGuard,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // @notice The ERC20 token used
    IERC20 public token;

    // @notice Founders Pirate token contract address
    address public foundersPirateContract;

    // @notice The mapping of pirate id to the amount of tokens granted
    mapping(uint256 => uint256) public pirateIdToTokenAmount;

    /**
     * @notice Initialize the contract with the ERC20 token and the claim contract
     * @param _token The address of the ERC20 token
     * @param _foundersPirateContract The address of the founders pirate contract
     */
    function initialize(
        address _token,
        address _foundersPirateContract
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        token = IERC20(_token);
        foundersPirateContract = address(_foundersPirateContract);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setRoleAdmin(MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

        _pause();
    }

    /**
     * @dev Update the address of the token contract
     * @param _token The address of the ERC20 token
     */
    function updateTokenContract(
        address _token
    ) external onlyRole(MANAGER_ROLE) {
        token = IERC20(_token);
    }

    /**
     * @dev Update the founders pirate contract address
     * @param _foundersPirateContract the address of the founders pirate contract
     */
    function updateFoundersPirateContract(
        address _foundersPirateContract
    ) external onlyRole(MANAGER_ROLE) {
        foundersPirateContract = _foundersPirateContract;
    }

    /**
     * @dev Set the pirate id to burn amount
     * @param pirateIds The array of pirate ids
     * @param tokenAmounts The array of token amounts
     */
    function setPirateIdToBurnAmount(
        uint256[] calldata pirateIds,
        uint256[] calldata tokenAmounts
    ) external onlyRole(MANAGER_ROLE) {
        if (pirateIds.length != tokenAmounts.length) {
            revert InvalidInputs();
        }

        for (uint256 i = 0; i < pirateIds.length; i++) {
            if (tokenAmounts[i] == 0 || pirateIds[i] == 0) {
                revert ZeroTokenAmount();
            }
            pirateIdToTokenAmount[pirateIds[i]] = tokenAmounts[i];
        }
    }

    /**
     * @dev Pause or unpause the contract
     * @param paused The boolean to pause or unpause the contract
     * @notice The contract can be paused to prevent purchases
     */
    function setPaused(bool paused) external onlyRole(MANAGER_ROLE) {
        if (paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @dev Withdraw the tokens from the contract
     * @param amount The amount of tokens to withdraw
     */
    function withdrawToken(uint256 amount) external onlyRole(MANAGER_ROLE) {
        token.transfer(msg.sender, amount);
    }

    /**
     * @dev Get the current token balance of the contract
     * @return The current token balance of the contract
     */
    function currentTokenBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /** USER FUNCTIONS */

    /**
     * @dev Burn pirates
     * @param pirateIds The array of pirate ids
     * @notice This function is called by the user to burn pirates
     */
    function burnPirates(
        uint256[] calldata pirateIds
    ) external whenNotPaused nonReentrant {
        address caller = _msgSender();
        if (pirateIds.length == 0) {
            revert InvalidInputs();
        }
        if (foundersPirateContract == address(0)) {
            revert NoFoundersPirateContractSet();
        }
        // Local var to avoid storage reads - save gas
        address piratesContract = foundersPirateContract;
        // Track the total amount of tokens to be granted
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < pirateIds.length; i++) {
            if (PirateNFTL1(piratesContract).ownerOf(pirateIds[i]) != caller) {
                revert NotPirateOwner();
            }
            if (pirateIdToTokenAmount[pirateIds[i]] == 0) {
                revert ZeroTokenAmount();
            }
            totalAmount += pirateIdToTokenAmount[pirateIds[i]];
            PirateNFTL1(piratesContract).burn(pirateIds[i]);
        }
        // Grant tokens to the user
        if (totalAmount > 0) {
            token.transfer(caller, totalAmount);
        }
    }
}
