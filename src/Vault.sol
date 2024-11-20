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

    constructor(address _token, address _uniswapRouter) {
        require(_token != address(0), "Vault: Token address cannot be zero");
        require(_uniswapRouter != address(0), "Vault: Router address cannot be zero");

        token = IERC20(_token);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    // Initialize function
    function initialize(address _admin) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Vault: Admin cannot be zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        
    }

    function setStrategy(address strategy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(strategy != address(0), "Vault: Invalid strategy address");
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
        token.approve(address(currentStrategy), amount);

        bytes memory params = abi.encode(amount, msg.sender, address(this));

        currentStrategy.execute(params);

        // Mint shares proportional to amount
        uint256 shares = (totalSupply == 0) ? amount : (amount * totalSupply) / currentStrategy.getBalance();
        _mint(msg.sender, shares);
    }

    /**
     * @notice Withdraw tokens by burning vault shares.
     * @param _shares The number of shares to burn.
     */
    function withdraw(uint256 _shares) external {
        require(_shares > 0, "Vault: Invalid share amount");
        require(balanceOf[msg.sender] >= _shares, "Vault: Insufficient shares");

        uint256 amount = (_shares * currentStrategy.getBalance()) / totalSupply;
        bytes memory params = abi.encode(amount, msg.sender);
        currentStrategy.withdraw(params);
        token.transfer(msg.sender, amount);
        _burn(msg.sender, _shares);
    }

    /**
     * @notice Rebalances the vault's assets by redistributing funds between Aave and Uniswap.
     * @dev This function is restricted to the admin role.
     *      It supplies a specified amount to Aave and performs liquidity or trade actions on Uniswap.
     * @param amountToAave The amount of tokens to supply to Aave.
     * @param amountToUniswap The amount of tokens to allocate for Uniswap operations.
     */

    function rebalance(uint256 amountToAave, uint256 amountToUniswap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        
    }
   

    function getUserShareValue(address user) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 userShares = balanceOf[user];
        uint256 vaultBalance = token.balanceOf(address(this));
        return (userShares * vaultBalance) / totalSupply;
    }
}
