``slidity name=DeFiYieldVault.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title DeFi Yield Vault (simplified)
/// @notice A simple vault pattern for a DeFi yield optimizer platform. This vault:
///  - accepts deposits of a single underlying ERC20
///  - mints "shares" representing a pro-rata claim on underlying
///  - sends funds to a strategy which produces yield
///  - collects performance and withdrawal fees
///  - supports emergency withdraw (panic) and strategy migration
///
/// NOT FOR PRODUCTION: this is a concise, readable starting point for experimentation in Remix.
/// Add audits, timelocks, multi-sig, and thorough tests before using real funds.
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/token/ERC20/IERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/access/Ownable.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.3/contracts/security/Pausable.sol";
import "./IStrategy.sol";

contract DeFiYieldVault is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    IStrategy public strategy;

    // Share accounting
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    // fees in basis points (bps). e.g., 200 = 2%
    uint16 public performanceFeeBps = 200; // fee on harvested profit
    uint16 public withdrawalFeeBps = 10;   // fee on withdrawals (0.1%)
    uint16 public constant BPS_MAX = 10_000;

    address public feeRecipient;

    event Deposited(address indexed user, uint256 amount, uint256 sharesMinted);
    event Withdrawn(address indexed user, uint256 amount, uint256 sharesBurned);
    event Harvested(address indexed caller, uint256 profit, uint256 fee);
    event StrategyChanged(address indexed oldStrategy, address indexed newStrategy);
    event PanicCalled(address indexed caller);

    constructor(address _underlying, address _strategy) {
        require(_underlying != address(0), "zero underlying");
        underlying = IERC20(_underlying);
        strategy = IStrategy(_strategy);
        feeRecipient = msg.sender;
    }

    /// @notice Total underlying assets under management (vault balance + strategy balance)
    function totalAssets() public view returns (uint256) {
        return underlying.balanceOf(address(this)) + strategy.balanceOf();
    }

    /// @notice Deposit underlying tokens into the vault and receive shares.
    /// @param amount amount of underlying to deposit
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "zero amount");
        uint256 _totalAssets = totalAssets();
        // Transfer underlying into vault
        underlying.safeTransferFrom(msg.sender, address(this), amount);

        // Compute shares to mint
        uint256 sharesToMint;
        if (totalShares == 0 || _totalAssets == 0) {
            // first depositor gets 1:1 shares -> underlying
            sharesToMint = amount;
        } else {
            // maintain proportional ownership: shares = amount * totalShares / totalAssets
            sharesToMint = (amount * totalShares) / _totalAssets;
        }

        // update accounting
        totalShares += sharesToMint;
        sharesOf[msg.sender] += sharesToMint;

        emit Deposited(msg.sender, amount, sharesToMint);

        // Send available funds to strategy to earn yield
        _earn();
    }

    /// @notice Withdraw by burning `shares` and receiving underlying (minus fee).
    /// @param shares amount of vault shares to redeem
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "zero shares");
        require(sharesOf[msg.sender] >= shares, "insufficient shares");

        uint256 _totalAssets = totalAssets();
        require(_totalAssets > 0 && totalShares > 0, "no assets");

        // Calculate amount of underlying owed
        uint256 amount = (shares * _totalAssets) / totalShares;

        // Burn shares
        totalShares -= shares;
        sharesOf[msg.sender] -= shares;

        // If vault lacks enough underlying balance, withdraw from strategy
        uint256 vaultBal = underlying.balanceOf(address(this));
        if (amount > vaultBal) {
            uint256 needed = amount - vaultBal;
            strategy.withdraw(needed);
        }

        // Compute withdrawal fee and transfer net
        uint256 fee = (amount * withdrawalFeeBps) / BPS_MAX;
        uint256 net = amount - fee;

        if (fee > 0) {
            underlying.safeTransfer(feeRecipient, fee);
        }

        underlying.safeTransfer(msg.sender, net);

        emit Withdrawn(msg.sender, net, shares);
    }

    /// @notice Internal helper: move available underlying in vault to strategy and call strategy.deposit()
    function _earn() internal {
        uint256 bal = underlying.balanceOf(address(this));
        if (bal > 0) {
            // Transfer to strategy and call deposit
            underlying.safeTransfer(address(strategy), bal);
            try strategy.deposit() {
                // ok
            } catch {
                // if strategy.deposit reverts, send tokens back (best-effort)
                underlying.safeTransfer(address(this), bal);
            }
        }
    }

    /// @notice Harvest strategy profits and take performance fee. Only owner may call.
    function harvest() external onlyOwner whenNotPaused nonReentrant {
        uint256 before = totalAssets();
        // Ask strategy to harvest and realize profit to the vault
        strategy.harvest();
        uint256 after = totalAssets();

        if (after <= before) {
            emit Harvested(msg.sender, 0, 0);
            // Nothing to do
            return;
        }

        uint256 profit = after - before;
        uint256 fee = (profit * performanceFeeBps) / BPS_MAX;

        if (fee > 0) {
            // transfer fee to recipient
            // fee is taken from vault balance
            underlying.safeTransfer(feeRecipient, fee);
        }

        // Re-deploy remaining funds
        _earn();

        emit Harvested(msg.sender, profit, fee);
    }

    /// @notice Replace the strategy. Owner only. Safe migration: pull funds back from old strategy first.
    /// @param newStrategy address of the new strategy
    function setStrategy(address newStrategy) external onlyOwner whenNotPaused {
        require(newStrategy != address(0), "zero strategy");
        address old = address(strategy);

        // Withdraw all from current strategy to vault
        strategy.withdrawAll();

        // Switch
        strategy = IStrategy(newStrategy);

        // Send assets to new strategy
        _earn();

        emit StrategyChanged(old, newStrategy);
    }

    /// @notice Emergency: pull funds back from strategy and pause the vault.
    function panic() external onlyOwner {
        strategy.withdrawAll();
        _pause();
        emit PanicCalled(msg.sender);
    }

    /// @notice Unpause after emergency (owner only)
    function resume() external onlyOwner {
        _unpause();
        // redeploy funds
        _earn();
    }

    /// @notice Set fee recipient
    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "zero addr");
        feeRecipient = recipient;
    }

    /// @notice Set performance fee (bps)
    function setPerformanceFeeBps(uint16 bps) external onlyOwner {
        require(bps <= BPS_MAX, "bps overflow");
        performanceFeeBps = bps;
    }

    /// @notice Set withdrawal fee (bps)
    function setWithdrawalFeeBps(uint16 bps) external onlyOwner {
        require(bps <= BPS_MAX, "bps overflow");
        withdrawalFeeBps = bps;
    }
}
tokenizes the future yield
low-latency execution
Agentic DeFi
dfh
