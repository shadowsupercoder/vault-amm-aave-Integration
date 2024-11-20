// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "aave/interfaces/IPool.sol";
import "./interfaces/IStrategy.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IStrategy public currentStrategy;

    IUniswapV2Router02 public immutable uniswapRouter;

    uint256 public totalSupply; // Total Supply of shares

    mapping(address => uint256) public balanceOf;

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

    function setStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // strategy can be empty
        currentStrategy = IStrategy(strategy);
    }

    function _mint(address _to, uint256 _shares) private {
        totalSupply += _shares;
        balanceOf[_to] += _shares;
    }

    function _burn(address _from, uint256 _shares) private {
        totalSupply -= _shares;
        balanceOf[_from] -= _shares;
    }

    /**
     * @notice Deposit tokens to receive vault shares.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Vault: Invalid deposit amount");

        token.transferFrom(msg.sender, address(this), amount);
        
        if (address(currentStrategy) != address(0)) {
            // Forward funds to the strategy
            token.approve(address(currentStrategy), amount);
            bytes memory params = abi.encode(amount, msg.sender, address(this));
            currentStrategy.execute(params);
        }

        // Calculate shares based on the current vault or strategy balance
        uint256 vaultBalance = _getVaultBalance();
        uint256 shares = (totalSupply == 0) ? amount : (amount * totalSupply) / vaultBalance;
        _mint(msg.sender, shares);
    }

    /**
     * @notice Withdraw tokens by burning vault shares.
     * @param _shares The number of shares to burn.
     */
    function withdraw(uint256 _shares) external {
        require(_shares > 0, "Vault: Invalid share amount");
        require(balanceOf[msg.sender] >= _shares, "Vault: Insufficient shares");

        // Calculate the user's proportional amount of the vault's balance
        uint256 vaultBalance = _getVaultBalance();
        uint256 amount = (_shares * vaultBalance) / totalSupply;

        if (address(currentStrategy) != address(0)) {
            // Withdraw from strategy
            bytes memory params = abi.encode(amount, msg.sender);
            currentStrategy.withdraw(params);
        }

        // Transfer tokens to the user
        token.transfer(msg.sender, amount);
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
}
