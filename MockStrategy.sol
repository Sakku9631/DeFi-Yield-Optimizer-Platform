IERC20 public immutable underlying;
address public immutable vault;

// internal accounting for the mocked deposited amount
uint256 private _deployed;

event DepositedToStrategy(uint256 amount);
event WithdrawnFromStrategy(uint256 amount);
event Harvested(uint256 rewardAmount);

constructor(address _underlying, address _vault) {
    require(_underlying != address(0) && _vault != address(0), "zero addr");
    underlying = IERC20(_underlying);
    vault = _vault;
}

/// @notice In a real strategy this would move funds into yield protocols.
/// Here we just account for the balance that exists in the strategy contract.
function deposit() external override {
    uint256 bal = underlying.balanceOf(address(this));
    if (bal > 0) {
        _deployed += bal;
        emit DepositedToStrategy(bal);
    }
}

/// @notice Withdraw amount back to the vault.
function withdraw(uint256 amount) external override {
    require(msg.sender == vault, "only vault");
    uint256 bal = underlying.balanceOf(address(this));
    if (amount > bal) {
        amount = bal;
    }
    if (amount > _deployed) {
        // withdraw at most deployed amount
        amount = _deployed;
    }
    if (amount > 0) {
        _deployed -= amount;
        underlying.safeTransfer(vault, amount);
        emit WithdrawnFromStrategy(amount);
    }
}

/// @notice Withdraw all funds back to the vault.
function withdrawAll() external override {
    require(msg.sender == vault, "only vault");
    uint256 bal = underlying.balanceOf(address(this));
    if (bal > 0) {
        _deployed = 0;
        underlying.safeTransfer(vault, bal);
        emit WithdrawnFromStrategy(bal);
    }
}

/// @notice Simulate harvesting yield by minting some underlying tokens to the strategy and transferring them to vault.
/// Only the owner (test harness) can call this so tests are deterministic.
function harvest() external override onlyOwner {
    // Only works if underlying is ERC20Mock
    // Mint 1% of deployed amount as "yield" (rounded)
    if (_deployed == 0) {
        emit Harvested(0);
        return;
    }
    uint256 reward = (_deployed * 1) / 100; // 1%
    // Mint reward to this strategy contract
    ERC20Mock(address(underlying)).mint(address(this), reward);
    // Then send the reward to the vault (so Vault can take performance fee on profit)
    underlying.safeTransfer(vault, reward);
    emit Harvested(reward);
}

/// @notice Return total underlying currently "deployed" by the strategy + any idle balance.
function balanceOf() external view override returns (uint256) {
    uint256 idle = underlying.balanceOf(address(this));
    return _deployed + idle;
}
Gas-Efficient-Compounding-Protocol
Rebalancing Logic (Python) 
Cross-Chain Yield Optimizers
Dyslex7c / DefiYieldOptimizer
Auto-Compounding
Gas Fee Optimization
doinel1a / lhedger-ai
lifinance / contracts (LI.FI)
ibrahimjspy / yield-farming-dashboard
