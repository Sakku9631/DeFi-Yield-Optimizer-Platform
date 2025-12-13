
``solidity name=ERC20Mock.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// Simple ERC20 mintable token for testing in Remix.
/// Not intended for production.
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/access/Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Mint tokens to `to`. Only owner (for testing).
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Convenience to mint tokens to the caller in Remix.
    function mintToSelf(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
MakerDAO - DSR Strategy
Impermanent Loss (IL) Mitigation Optimizer

obinnafranklinduru/defi-yield-aggregator
Description: A sophisticated yield
