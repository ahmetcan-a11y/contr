// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title ProjectToken
 * @dev ERC20 token with minting capability and access control
 * @notice This token is used in the token sale platform where 1 token = 0.2 USDT
 */
contract ProjectToken is ERC20, AccessControl, Pausable, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens

    event TokensMinted(address indexed to, uint256 amount);
    event MaxSupplyReached();

    /**
     * @dev Constructor that gives DEFAULT_ADMIN_ROLE, MINTER_ROLE and PAUSER_ROLE to the deployer
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param initialSupply The initial supply to mint to the deployer
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(initialSupply <= MAX_SUPPLY, "ProjectToken: Initial supply exceeds max supply");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply);
            emit TokensMinted(msg.sender, initialSupply);
        }
    }

    /**
     * @dev Mints tokens to a specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     * @notice Only addresses with MINTER_ROLE can call this function
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) whenNotPaused {
        require(to != address(0), "ProjectToken: Cannot mint to zero address");
        require(amount > 0, "ProjectToken: Amount must be greater than zero");
        require(totalSupply() + amount <= MAX_SUPPLY, "ProjectToken: Minting would exceed max supply");

        _mint(to, amount);
        emit TokensMinted(to, amount);

        if (totalSupply() == MAX_SUPPLY) {
            emit MaxSupplyReached();
        }
    }

    /**
     * @dev Pauses all token transfers
     * @notice Only addresses with PAUSER_ROLE can call this function
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
     * @notice Only addresses with PAUSER_ROLE can call this function
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Returns the remaining tokens that can be minted
     */
    function remainingSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @param from The address tokens are transferred from
     * @param to The address tokens are transferred to
     * @param amount The amount of tokens being transferred
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._update(from, to, amount);
    }

    /**
     * @dev See {IERC165-supportsInterface}
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}