// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "aave/interfaces/IPool.sol";
import "./interfaces/IStrategy.sol";
import "./DiamondStorage.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IStrategy public currentStrategy;

    IUniswapV2Router02 public immutable uniswapRouter;

    uint256 public totalSupply; // Total Supply of shares

    mapping(address => uint256) public balanceOf;

    event StrategySwitched(address oldStrategy, address newStrategy);
    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 shares, uint256 amount);
    event Rebalanced(address[] strategies);

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

    function addStrategy(
        address strategy,
        uint256 allocation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategy != address(0), "Invalid strategy address");
        require(allocation > 0, "Allocation must be greater than zero");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();

        // Ensure the strategy is not already added
        require(!ds.strategies[strategy], "Strategy already exists");

        // Add the strategy
        ds.strategies[strategy] = true;
        ds.strategyList.push(strategy);

        // Set the allocation for the strategy
        ds.allocations[strategy] = allocation;

        // Validate total allocations
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < ds.strategyList.length; i++) {
            totalAllocation += ds.allocations[ds.strategyList[i]];
        }
        require(totalAllocation <= 10_000, "Total allocations exceed 100%");
    }

    function removeStrategy(
        address strategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategy != address(0), "Invalid strategy address");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        require(ds.strategies[strategy], "Strategy does not exist");

        // Remove from the mapping
        ds.strategies[strategy] = false;

        // Remove from the array
        uint256 length = ds.strategyList.length;
        for (uint256 i = 0; i < length; i++) {
            if (ds.strategyList[i] == strategy) {
                ds.strategyList[i] = ds.strategyList[length - 1];
                ds.strategyList.pop();
                break;
            }
        }

        // Reset the allocation
        ds.allocations[strategy] = 0;

        // Validate total allocations
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < ds.strategyList.length; i++) {
            totalAllocation += ds.allocations[ds.strategyList[i]];
        }
        require(totalAllocation <= 10_000, "Total allocations exceed 100%");
    }

    function switchStrategy(
        address newStrategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newStrategy != address(0), "Invalid strategy address");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();

        require(ds.strategies[newStrategy], "Strategy not allowed");
        address oldStrategy = ds.currentStrategy;

        if (oldStrategy != address(0)) {
            uint256 balance = IStrategy(oldStrategy).getBalance();
            if (balance > 0) {
                bytes memory params = abi.encode(
                    balance,
                    address(this),
                    msg.sender
                );
                IStrategy(oldStrategy).withdraw(params);
            }
        }

        ds.currentStrategy = newStrategy;

        emit StrategySwitched(oldStrategy, newStrategy);
    }

    function _mint(address _to, uint256 _shares) private {
        totalSupply += _shares;
        balanceOf[_to] += _shares;
    }

    function _burn(address _from, uint256 _shares) private {
        totalSupply -= _shares;
        balanceOf[_from] -= _shares;
    }

    function getCurrentStrategy() external view returns (address) {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        return ds.currentStrategy;
    }

    /**
     * @notice Deposit tokens to receive vault shares.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Vault: Invalid deposit amount");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();

        require(ds.currentStrategy != address(0), "Vault: No strategy set");

        // Transfer tokens to the vault
        token.transferFrom(msg.sender, address(this), amount);

        // Forward funds to the current strategy if one exists
        if (ds.currentStrategy != address(0)) {
            token.approve(ds.currentStrategy, amount);

            // Assuming the strategy requires specific parameters encoded for execution
            bytes memory params = abi.encode(amount, msg.sender, address(this));
            IStrategy(ds.currentStrategy).execute(params); // Ensure `execute` is implemented in the strategy
        }

        // Calculate shares based on the current vault or strategy balance
        uint256 vaultBalance = _getVaultBalance();
        require(vaultBalance > 0, "Vault: Balance must be greater than zero");

        uint256 shares = (totalSupply == 0)
            ? amount
            : (amount * totalSupply) / vaultBalance;
        _mint(msg.sender, shares); // Mint shares proportional to deposit
    }

    /**
     * @notice Withdraw tokens by burning vault shares.
     * @param _shares The number of shares to burn.
     */
    function withdraw(uint256 _shares) external {
        require(_shares > 0, "Vault: Invalid share amount");
        require(balanceOf[msg.sender] >= _shares, "Vault: Insufficient shares");

        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        require(ds.currentStrategy != address(0), "Vault: No strategy set");

        // Calculate the user's proportional amount of the vault's balance
        uint256 vaultBalance = _getVaultBalance();
        require(vaultBalance > 0, "Vault: Insufficient vault balance");

        uint256 amount = (_shares * vaultBalance) / totalSupply;

        // Withdraw from the current strategy if applicable
        if (ds.currentStrategy != address(0)) {
            bytes memory params = abi.encode(amount, msg.sender);
            IStrategy(ds.currentStrategy).withdraw(params); // Strategy handles encoded parameters
        }

        // Transfer tokens to the user
        token.transfer(msg.sender, amount);

        // Burn the user's shares
        _burn(msg.sender, _shares);
    }

    /**
     * @notice Get the vault's total balance, including funds in strategy or in the vault.
     * @return The total balance of the vault.
     */
    function _getVaultBalance() internal view returns (uint256) {
        if (address(currentStrategy) != address(0)) {
            return currentStrategy.getBalance();
        }
        return token.balanceOf(address(this));
    }

    /**
     * @notice Returns the value of a user's shares in the vault.
     * @param user The address of the user.
     * @return The value of the user's shares.
     */
    function getUserShareValue(address user) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 userShares = balanceOf[user];
        uint256 vaultBalance = _getVaultBalance();
        return (userShares * vaultBalance) / totalSupply;
    }

    function rebalance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        DiamondStorage.StrategyData storage ds = DiamondStorage
            .strategyStorage();
        uint256 totalVaultBalance = _getVaultBalance();
        require(totalVaultBalance > 0, "No funds to rebalance");

        address[] memory strategies = ds.strategyList;
        require(strategies.length > 0, "No strategies available");

        uint256 totalAllocation = 0;

        // Validate total allocation
        for (uint256 i = 0; i < strategies.length; i++) {
            totalAllocation += ds.allocations[strategies[i]];
        }
        require(totalAllocation == 10_000, "Allocations must sum to 100%");

        // Withdraw all funds from the current active strategy, if any
        if (ds.currentStrategy != address(0)) {
            uint256 withdrawn = IStrategy(ds.currentStrategy).withdrawAll();
            require(withdrawn > 0, "Failed to withdraw from active strategy");
        }

        // Allocate funds to each stored strategy
        uint256 remainingBalance = token.balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            address strategy = strategies[i];
            require(ds.strategies[strategy], "Invalid strategy address");

            uint256 allocation = (remainingBalance * ds.allocations[strategy]) /
                10_000;
            if (allocation > 0) {
                token.approve(strategy, allocation);

                // Execute the allocation in the strategy
                bytes memory params = abi.encode(
                    allocation,
                    address(this),
                    address(this)
                );
                IStrategy(strategy).execute(params);
            }
        }

        // Update the current strategy if only one strategy is used
        if (strategies.length == 1) {
            ds.currentStrategy = strategies[0];
        } else {
            ds.currentStrategy = address(0); // No single active strategy
        }

        emit Rebalanced(strategies);
    }
}
