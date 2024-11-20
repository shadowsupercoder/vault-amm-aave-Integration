// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "@chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import "aave/interfaces/IPool.sol";
import "./interfaces/IStrategy.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IStrategy public currentStrategy;

    IUniswapV2Router02 public immutable uniswapRouter;
    IPool public immutable aaveLendingPool;

    uint256 public maxSlippage; // Maximum allowed slippage in basis points (1% = 100, 0.5% = 50)
    uint256 public totalSupply; // Total Supply of shares

    mapping(address => uint256) public balanceOf;

    constructor(address _token, address _uniswapRouter, address _dataFeed, address _lendingPool) {
        require(_token != address(0), "Vault: Token address cannot be zero");
        require(_uniswapRouter != address(0), "Vault: Router address cannot be zero");
        require(_dataFeed != address(0), "Vault: DataFeed address cannot be zero");
        require(_lendingPool != address(0), "Vault: LendingPool address cannot be zero");

        token = IERC20(_token);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_dataFeed);
        aaveLendingPool = IPool(_lendingPool);
    }

    // Initialize function
    function initialize(address _admin, uint256 _initialSlippage) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Vault: Admin cannot be zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        setMaxSlippage(_initialSlippage);
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
     * @param _amount The amount of tokens to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Vault: Invalid deposit amount");

        token.transferFrom(msg.sender, address(this), amount);
        token.approve(address(currentStrategy), amount);
        currentStrategy.execute(amount, maxSlippage, path, msg.sender, deadline);

        // Mint shares proportional to amount
        uint256 shares = (totalSupply == 0) ? amount : (amount * totalSupply) / currentStrategy.getBalance();
        _mint(msg.sender, shares);
    }

    /**
     * @notice Withdraw tokens by burning vault shares.
     * @param _shares The number of shares to burn.
     */
    function withdraw(uint256 _shares) external {
        require(shares > 0, "Vault: Invalid share amount");
        require(balanceOf[msg.sender] >= shares, "Vault: Insufficient shares");

        uint256 amount = (shares * currentStrategy.getBalance()) / totalSupply;

        currentStrategy.withdraw(amount);
        token.transfer(msg.sender, amount);
        _burn(msg.sender, _shares);
    }


    /**
     * @notice Allows the admin to set the maximum slippage percentage.
     * @param _slippage The maximum slippage percentage (e.g., 50 for 5%).
     */
    function setMaxSlippage(uint256 _slippage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_slippage <= 100, "Slippage too high");
        maxSlippage = _slippage;
    }

    
    /**
     * @notice Rebalances the vault's assets by redistributing funds between Aave and Uniswap.
     * @dev This function is restricted to the admin role.
     *      It supplies a specified amount to Aave and performs liquidity or trade actions on Uniswap.
     * @param amountToAave The amount of tokens to supply to Aave.
     * @param amountToUniswap The amount of tokens to allocate for Uniswap operations.
     */

    function rebalance(uint256 amountToAave, uint256 amountToUniswap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amountToAave > 0) {
            _lendToAave(amountToAave);
        }

        if (amountToUniswap > 0) {
            // Add liquidity to Uniswap or execute a trade
        }
    }
   

    function getUserShareValue(address user) public view returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 userShares = balanceOf[user];
        uint256 vaultBalance = token.balanceOf(address(this));
        return (userShares * vaultBalance) / totalSupply;
    }
}
