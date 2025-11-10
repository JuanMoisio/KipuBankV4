// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Kipu Gold (KGLD)
 * @notice Educational ERC-20 with burn, pause and EIP-2612 permit.
 * @dev OpenZeppelin v5, 18 decimals.
 */
contract KipuGLD is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, Ownable {
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("Kipu Gold", "KGLD")
        ERC20Permit("Kipu Gold")
        Ownable(initialOwner)
    {
        _mint(initialOwner, initialSupply);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
