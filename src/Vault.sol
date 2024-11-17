// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IUniswapV2Router02 public uniswapRouter;
    AggregatorV3Interface public priceFeed;
    uint256 public maxSlippage; // Maximum allowed slippage in basis points (1% = 100, 0.5% = 50)

    uint256 public totalSupply; // Total Supply of shares
    mapping(address => uint256) public balanceOf;

    constructor(address _token, address _uniswapRouter, address _priceFeed) {
        require(_token != address(0), "Vault: Admin can not be zero address");
        require(
            _uniswapRouter != address(0),
            "Vault: Router can not be zero address"
        );
        require(
            _priceFeed != address(0),
            "Vault: PriceFeed can not be zero address"
        );

        token = IERC20(_token);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function initialize(
        address _admin,
        uint256 _initialSlippage
    ) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Vault: Admin can not be zero address");
        // Grant the `DEFAULT_ADMIN_ROLE` to the _admin
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        setMaxSlippage(_initialSlippage);
    }

    function _mint(address _to, uint256 _shares) private {
        totalSupply += _shares;
        balanceOf[_to] += _shares;
    }

    function _burn(address _from, uint256 _shares) private {
        totalSupply -= _shares;
        balanceOf[_from] -= _shares;
    }

    function deposit(uint256 _amount) external {
        /*
        a = amount
        B = balance of token before deposit
        T = total supply
        s = shares to mint

        (s + T) / T = (a + B) / B 

        s = aT / B
        */
        require(_amount > 0, "Invalid amount"); // Add this line to prevent zero deposits

        uint256 shares;
        if (totalSupply == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply) / token.balanceOf(address(this));
        }

        token.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, shares);
    }

    function withdraw(uint256 _shares) external {
        /*
        a = amount
        B = balance of token before withdraw
        T = total supply
        s = shares to burn

        (T - s) / T = (B - a) / B 

        a = sB / T
        */

        require(_shares > 0, "Invalid share amount");
        require(balanceOf[msg.sender] >= _shares, "Insufficient shares");

        uint256 amount = (_shares * token.balanceOf(address(this))) /
            totalSupply;
        _burn(msg.sender, _shares);
        token.transfer(msg.sender, amount);
    }

    /**
     * @notice Allows the admin to swap tokens on Uniswap for better returns.
     * @param amountIn Amount of input tokens to swap.
     * @param amountOutMin Minimum amount of output tokens required.
     * @param path Array of token addresses representing the swap path.
     * @param deadline Unix timestamp after which the swap will expire.
     */
    function swapTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amountIn > 0, "Vault: Invalid amount");
        require(path[0] == address(token), "Vault: Invalid path");

        token.approve(address(uniswapRouter), amountIn);

        // Perform the token swap on Uniswap
        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
    }

    /**
     * @notice Allows the admin to set the maximum slippage percentage.
     * @param _slippage The maximum slippage percentage (e.g., 50 for 5%).
     */
    function setMaxSlippage(
        uint256 _slippage
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_slippage <= 100, "Slippage too high");
        maxSlippage = _slippage;
    }

    /**
     * @notice Calculates the minimum output amount with slippage protection.
     * @param amountIn Amount of input tokens.
     * @param currentPrice Current Chainlink price of the output token.
     * @return Minimum output amount after accounting for slippage.
     */
    function calculateAmountOutMin(
        uint256 amountIn,
        uint256 currentPrice
    ) public view returns (uint256) {
        uint256 usedPrice = currentPrice ? currentPrice : getLatestPrice();
        uint256 amountOut = (amountIn * usedPrice) / 1e18; // Adjust for decimals
        uint256 slippageAmount = (amountOut * maxSlippage) / 10_000; // Slippage in basis points
        return amountOut - slippageAmount;
    }

    /**
     * @notice Fetches the latest price from the Chainlink price feed.
     * @return The latest price with 18 decimals.
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }
}
