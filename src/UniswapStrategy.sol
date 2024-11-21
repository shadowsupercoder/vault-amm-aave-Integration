// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "uniswap/v2-core/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IStrategy.sol";
import "@chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

contract UniswapStrategy is IStrategy {
    IUniswapV2Router02 public immutable uniswapRouter;
    AggregatorV3Interface internal immutable dataFeed;
    // Target percentage allocation for tokenIn (e.g., 60 means 60% for tokenIn and 40% for tokenOut)
    uint256 public targetInPercent = 50; // Default to 50% for a balanced portfolio
    address public immutable tokenIn;
    address public immutable tokenOut;
    address[] public swapPath;

    uint256 public maxSlippage; // Maximum allowed slippage in basis points (1% = 100, 0.5% = 50)

    event TokensSwapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    constructor(address _uniswapRouter, address _dataFeed, address _pair, uint256 _initialSlippage) {
        require(_uniswapRouter != address(0), "Invalid Uniswap Router");
        require(_dataFeed != address(0), "Vault: DataFeed address cannot be zero");
        require(_pair != address(0), "Invalid pair address");

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_dataFeed);

        // Derive the swap path from the pair
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        tokenIn = pair.token0();
        tokenOut = pair.token1();

        // Set the path based on the pair tokens
        swapPath = [tokenIn, tokenOut];
        setMaxSlippage(_initialSlippage);
    }

    function execute(bytes calldata params) external {
        (uint256 amount, address to,) = abi.decode(params, (uint256, address, address));
        require(amount > 0, "Invalid amount");

        _validatePriceImpact(amount);
        _swapTokens(amount, to, block.timestamp + 1 hours, swapPath);
    }

    function _swapTokens(uint256 amountIn, address to, uint256 deadline, address[] memory path) private {
        require(amountIn > 0, "Invalid input amount");
        require(to != address(0), "Invalid recipient address");
        require(path.length >= 2, "Invalid swap path");

        // Calculate the minimum output amount based on slippage tolerance
        uint256 expectedAmountOut = calculateAmountOutMin(amountIn, maxSlippage);

        // Approve tokens for Uniswap router
        _approveTokenIfNeeded(tokenIn, amountIn);

        // Perform the token swap
        uint256[] memory amounts = _executeSwap(amountIn, expectedAmountOut, path, to, deadline);

        // Validate the swap output
        require(amounts[amounts.length - 1] >= expectedAmountOut, "Insufficient output amount");
    }

    function _approveTokenIfNeeded(address token, uint256 amount) private {
        uint256 currentAllowance = IERC20(token).allowance(address(this), address(uniswapRouter));
        if (currentAllowance < amount) {
            IERC20(token).approve(address(uniswapRouter), amount);
        }
    }

    function _executeSwap(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline)
        private
        returns (uint256[] memory)
    {
        return uniswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, to, deadline);
    }

    function calculateAmountOutMin(uint256 amountIn, uint256 _maxSlippage) public view returns (uint256) {
        // Fetch current price from Chainlink
        uint256 price = uint256(getValidatedPrice());
        uint256 amountOut = (amountIn * price) / 1e18;

        // Apply slippage tolerance
        uint256 slippageAmount = (amountOut * _maxSlippage) / 10_000;
        return amountOut - slippageAmount;
    }

    function getValidatedPrice() public view returns (int256) {
        int256 price = getChainlinkDataFeedLatestAnswer();
        require(_isPriceValid(price), "Vault: Invalid Chainlink price");
        return price;
    }

    /**
     * @notice Fetches the latest price from the Chainlink price feed.
     * @return The latest price with 18 decimals.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (
            ,
            /* uint80 roundID */
            int256 answer, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,
        ) = dataFeed.latestRoundData();
        return answer;
    }

    function _validatePriceImpact(uint256 amountIn) internal view {
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amountIn, swapPath);
        uint256 priceImpact = ((amountsOut[0] - amountsOut[amountsOut.length - 1]) * 10_000) / amountsOut[0];
        require(priceImpact <= maxSlippage, "Price impact too high");
    }

    function _isPriceValid(int256 price) internal view returns (bool) {
        require(price > 0, "Invalid price value");
        (,, uint256 startedAt, uint256 updatedAt,) = dataFeed.latestRoundData();
        require(updatedAt >= startedAt, "Stale price data");
        require(block.timestamp - updatedAt <= 1 hours, "Price data outdated");
        return true;
    }

    /**
     * @notice Withdraws all of the `tokenIn` balance from the contract.
     * @return The total amount of `tokenIn` withdrawn.
     */
    function withdrawAll() external returns (uint256) {
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        // Transfer the entire balance of tokenIn to the owner
        IERC20(tokenIn).transfer(msg.sender, balance);

        return balance;
    }

    /**
     * @notice Withdraws a specific amount of `tokenIn` from the contract.
     * @param params Encoded parameters containing the withdrawal amount.
     */
    function withdraw(bytes calldata params) external {
        // Decode the `params` to extract the withdrawal amount
        (uint256 amount,,,) = abi.decode(params, (uint256, uint256, address, address));
        require(amount > 0, "Invalid withdrawal amount");

        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        require(balance >= amount, "Insufficient balance");

        // Transfer the specified amount of tokenIn to the owner
        IERC20(tokenIn).transfer(msg.sender, amount);
    }

    function getBalance() external view returns (uint256) {
        return IERC20(tokenOut).balanceOf(address(this));
    }

    function rebalance() external {
        // Define the automatic deadline (e.g., 15 minutes from now)
        uint256 deadline = block.timestamp + 15 minutes;
        // Get current balances of tokenIn and tokenOut
        uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOut = IERC20(tokenOut).balanceOf(address(this));
        uint256 totalBalance = balanceIn + balanceOut;

        // Calculate target balances
        uint256 targetBalanceIn = (totalBalance * targetInPercent) / 100;
        uint256 targetBalanceOut = totalBalance - targetBalanceIn;
        address[] memory path = new address[](2);
        // Perform rebalancing if necessary
        if (balanceIn > targetBalanceIn) {
            uint256 excessIn = balanceIn - targetBalanceIn;

            // Define the forward swap path (tokenIn -> tokenOut)
            path[0] = tokenIn;
            path[1] = tokenOut;

            _swapTokens(excessIn, address(this), deadline, path);
        } else if (balanceOut > targetBalanceOut) {
            uint256 excessOut = balanceOut - targetBalanceOut;

            // Define the reverse swap path (tokenOut -> tokenIn)
            path[0] = tokenOut;
            path[1] = tokenIn;

            _swapTokens(excessOut, address(this), deadline, path);
        }
    }

    function setTargetInPercent(uint256 _targetInPercent) external {
        require(_targetInPercent <= 100, "Invalid target percentage");
        targetInPercent = _targetInPercent;
    }

    /**
     * @notice Allows the admin to set the maximum slippage percentage.
     * @param _slippage The maximum slippage percentage (e.g., 50 for 5%).
     */
    function setMaxSlippage(uint256 _slippage) public {
        require(_slippage <= 100, "Slippage too high");
        maxSlippage = _slippage;
    }
}
