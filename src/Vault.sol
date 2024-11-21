// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "aave/interfaces/IPool.sol";
import "./interfaces/IStrategy.sol";
import "./libs/DiamondStorage.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IUniswapV2Router02 public immutable uniswapRouter;

    uint256 public totalSupply; // Total Supply of shares
    mapping(address => uint256) public balanceOf;

    event StrategySwitched(address oldStrategy, address newStrategy);
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event Rebalanced(address[] strategies);
    event AllocationsUpdated(address[] strategies);

    constructor(address _token) {
        require(_token != address(0), "Vault: Token address cannot be zero");
        token = IERC20(_token);
    }

    // Initialize function
    function initialize(address _admin) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Vault: Admin cannot be zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    modifier onlyStrategy(address strategy) {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        require(ds.strategies[strategy], "Strategy not found");
        _;
    }

    modifier hasCurrentStrategy() {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        require(ds.currentStrategy != address(0), "Vault: No strategy set");
        _;
    }

    // Add a strategy
    function addStrategy(
        address strategy,
        uint256 allocation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addStrategy(strategy, allocation);
    }

    function switchStrategy(
        address newStrategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyStrategy(newStrategy) {
        _switchStrategy(newStrategy);
    }

    function updateAllocations(
        address[] calldata strategies,
        uint256[] calldata allocations
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategies.length == allocations.length, "Mismatched inputs");
        require(strategies.length > 0, "No strategies provided");
        _updateAllocations(strategies, allocations);
    }

    function removeStrategy(
        address strategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyStrategy(strategy) {
        _removeStrategy(strategy);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Vault: Invalid deposit amount");
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();

        // Transfer tokens to the vault
        token.transferFrom(msg.sender, address(this), amount);

        // Forward funds to the current strategy
        if (ds.currentStrategy != address(0)) {
            _executeStrategy(amount, msg.sender, ds.currentStrategy);
        }

        // Mint shares to the depositor
        uint256 shares = _calculateShares(amount);
        _mint(msg.sender, shares);

        emit Deposited(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external hasCurrentStrategy {
        require(shares > 0, "Vault: Invalid share amount");
        require(balanceOf[msg.sender] >= shares, "Vault: Insufficient shares");

        // Calculate proportional withdrawal
        uint256 amount = _calculateWithdrawAmount(shares);

        // Withdraw funds from the strategy
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        _executeStrategyWithdraw(amount, msg.sender, ds.currentStrategy);

        // Transfer tokens and burn shares
        token.transfer(msg.sender, amount);
        _burn(msg.sender, shares);

        emit Withdrawn(msg.sender, shares, amount);
    }

    function rebalance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _rebalance();
    }

    function getCurrentStrategy() external view returns (address) {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        return ds.currentStrategy;
    }

    function getUserShareValue(address user) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 userShares = balanceOf[user];
        uint256 vaultBalance = _getVaultBalance();
        return (userShares * vaultBalance) / totalSupply;
    }

    function _executeStrategy(
        uint256 amount,
        address user,
        address strategy
    ) internal {
        bytes memory params = abi.encode(amount, user);
        token.approve(strategy, amount);
        IStrategy(strategy).execute(params);
    }

    function _executeStrategyWithdraw(
        uint256 amount,
        address user,
        address strategy
    ) internal {
        bytes memory params = abi.encode(
            amount,
            user,
            address(this),
            address(this)
        );
        IStrategy(strategy).withdraw(params);
    }
    function _removeStrategy(address strategy) internal {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        ds.strategies[strategy] = false;

        uint256 length = ds.strategyList.length;
        for (uint256 i = 0; i < length; i++) {
            if (ds.strategyList[i] == strategy) {
                ds.strategyList[i] = ds.strategyList[length - 1];
                ds.strategyList.pop();
                break;
            }
        }

        ds.allocations[strategy] = 0;
        _validateTotalAllocation();
    }
    function _switchStrategy(address newStrategy) internal {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        address oldStrategy = ds.currentStrategy;

        if (oldStrategy != address(0)) {
            uint256 balance = IStrategy(oldStrategy).getBalance();
            if (balance > 0) {
                _executeStrategyWithdraw(balance, address(this), oldStrategy);
            }
        }

        ds.currentStrategy = newStrategy;
        emit StrategySwitched(oldStrategy, newStrategy);
    }

    function _addStrategy(address strategy, uint256 allocation) internal {
        require(strategy != address(0), "Invalid strategy address");
        require(allocation > 0, "Allocation must be greater than zero");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        require(!ds.strategies[strategy], "Strategy already exists");

        ds.strategies[strategy] = true;
        ds.strategyList.push(strategy);
        ds.allocations[strategy] = allocation;

        _validateTotalAllocation();
    }

    function _updateAllocations(
        address[] calldata strategies,
        uint256[] calldata allocations
    ) internal {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();

        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            ds.allocations[strategies[i]] = allocations[i];
            totalAllocation += allocations[i];
        }

        require(totalAllocation == 10_000, "Allocations must sum to 100%");
        emit AllocationsUpdated(strategies);
    }

    function _validateTotalAllocation() internal view {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        uint256 totalAllocation = 0;

        for (uint256 i = 0; i < ds.strategyList.length; i++) {
            totalAllocation += ds.allocations[ds.strategyList[i]];
        }

        require(totalAllocation <= 10_000, "Total allocations exceed 100%");
    }

    function _calculateShares(uint256 amount) internal view returns (uint256) {
        uint256 vaultBalance = _getVaultBalance();
        return
            (totalSupply == 0) ? amount : (amount * totalSupply) / vaultBalance;
    }

    function _calculateWithdrawAmount(
        uint256 shares
    ) internal view returns (uint256) {
        uint256 vaultBalance = _getVaultBalance();
        return (shares * vaultBalance) / totalSupply;
    }

    function _getVaultBalance() internal view returns (uint256) {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        return
            (ds.currentStrategy != address(0))
                ? IStrategy(ds.currentStrategy).getBalance()
                : token.balanceOf(address(this));
    }

    function _rebalance() internal {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        address[] memory strategies = ds.strategyList;

        if (ds.currentStrategy != address(0)) {
            uint256 withdrawn = IStrategy(ds.currentStrategy).withdrawAll();
            require(withdrawn > 0, "Failed to withdraw from active strategy");
        }

        uint256 remainingBalance = token.balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            uint256 allocation = (remainingBalance *
                ds.allocations[strategies[i]]) / 10_000;
            if (allocation > 0) {
                _executeStrategy(allocation, address(this), strategies[i]);
            }
        }

        emit Rebalanced(strategies);
    }

    function _mint(address _to, uint256 _shares) private {
        totalSupply += _shares;
        balanceOf[_to] += _shares;
    }

    function _burn(address _from, uint256 _shares) private {
        totalSupply -= _shares;
        balanceOf[_from] -= _shares;
    }
}
