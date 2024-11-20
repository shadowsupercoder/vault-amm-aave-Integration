// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "@chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
import "aave/interfaces/IPool.sol";

// import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;
    IUniswapV2Router02 public uniswapRouter;
    AggregatorV3Interface internal dataFeed;
    IPool public aaveLendingPool;

    uint256 public maxSlippage; // Maximum allowed slippage in basis points (1% = 100, 0.5% = 50)

    uint256 public totalSupply; // Total Supply of shares
    mapping(address => uint256) public balanceOf;

    constructor(
        address _token,
        address _uniswapRouter,
        address _dataFeed,
        address _lendingPool
    ) {
        require(_token != address(0), "Vault: Admin can not be zero address");
        require(
            _uniswapRouter != address(0),
            "Vault: Router can not be zero address"
        );
        require(
            _dataFeed != address(0),
            "Vault: DataFeed can not be zero address"
        );
        require(
            _lendingPool != address(0),
            "Vault: LendingPool can not be zero address"
        );

        token = IERC20(_token);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_dataFeed);
        aaveLendingPool = IPool(_lendingPool);
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
        address to,
        uint256 deadline
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(path.length >= 2, "Invalid path");
        require(amountIn > 0, "Vault: Invalid amount");
        require(path[0] == address(token), "Vault: Invalid path");

        // Approve the router to spend the input tokens
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);

        // Perform the token swap on Uniswap
        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
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
    function calculateAmountOutMinChainLink(
        uint256 amountIn,
        uint256 currentPrice
    ) public view returns (uint256) {
        uint256 usedPrice = (currentPrice > 0)
            ? currentPrice
            : uint256(getChainlinkDataFeedLatestAnswer());
        uint256 amountOut = (amountIn * usedPrice) / 1e18; // Adjust for decimals
        uint256 slippageAmount = (amountOut * maxSlippage) / 10_000; // Slippage in basis points
        return amountOut - slippageAmount;
    }

    /**
     * @notice Get the minimum output amount based on Uniswap's price data.
     * @param amountIn The amount of input tokens.
     * @param path The swap path (e.g., [tokenA, tokenB]).
     * @return amountOutMin The minimum output amount after applying slippage.
     */
    function calculateAmountOutMinUniswap(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256 amountOutMin) {
        // Get the expected output amount from Uniswap
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(
            amountIn,
            path
        );
        uint256 amountOut = amountsOut[amountsOut.length - 1]; // The last element is the output amount

        // Apply slippage
        uint256 slippageAmount = (amountOut * maxSlippage) / 10_000; // Basis points calculation
        amountOutMin = amountOut - slippageAmount;
    }

    /**
     * @notice Fetches the latest price from the Chainlink price feed.
     * @return The latest price with 18 decimals.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (
            ,
            /* uint80 roundID */
            int256 answer,
            ,
            ,

        ) = dataFeed /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
                .latestRoundData();
        return answer;
    }

    function lendToAave(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _lendToAave(amount);
    }

    function _lendToAave(uint256 amount) private {
        require(amount > 0, "Vault: Amount must be greater than zero");
        token.approve(address(aaveLendingPool), amount);
        aaveLendingPool.supply(address(token), amount, address(this), 0);
    }

    function withdrawFromAave(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aaveLendingPool.withdraw(address(token), amount, address(this));
    }

    function rebalance(
        uint256 amountToAave,
        uint256 amountToUniswap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amountToAave > 0) {
            _lendToAave(amountToAave);
        }

        if (amountToUniswap > 0) {
            // Add liquidity to Uniswap or execute a trade
        }
    }

    function borrowFromAave(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Vault: Amount must be greater than zero");
        aaveLendingPool.borrow(
            asset,
            amount,
            interestRateMode,
            0,
            address(this)
        );
    }

    function repayToAave(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "Vault: Amount must be greater than zero");
        IERC20(asset).approve(address(aaveLendingPool), amount);
        aaveLendingPool.repay(asset, amount, interestRateMode, address(this));
    }

    function getHealthFactor() public view returns (uint256) {
        (, , , uint256 healthFactor) = aaveLendingPool.getUserAccountData(
            address(this)
        );
        return healthFactor;
    }

    function emergencyRepay(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 healthFactor = getHealthFactor();
        require(healthFactor < 1e18, "Vault: Health factor is safe");
        IERC20(asset).approve(address(aaveLendingPool), amount);
        aaveLendingPool.repay(asset, amount, interestRateMode, address(this));
    }

    function emergencyWithdrawAll() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.transfer(msg.sender, balance);
        }
        uint256 aaveBalance = aaveLendingPool.withdraw(
            address(token),
            type(uint256).max,
            address(this)
        );
        if (aaveBalance > 0) {
            token.transfer(msg.sender, aaveBalance);
        }
    }
}
