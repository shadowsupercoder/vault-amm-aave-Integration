// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";
import "./IStrategy.sol";
import "@chainlink/v0.8/interfaces/AggregatorV3Interface.sol";

contract StatelessUniswapStrategy is IStrategy {
    IUniswapV2Router02 public immutable uniswapRouter;
    AggregatorV3Interface internal immutable dataFeed;

    constructor(address _uniswapRouter, address _dataFeed) {
        require(_uniswapRouter != address(0), "Invalid Uniswap Router");
        require(
            _dataFeed != address(0),
            "Vault: DataFeed address cannot be zero"
        );

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        dataFeed = AggregatorV3Interface(_dataFeed);
    }

    /**
     * @notice Executes a token swap on Uniswap.
     * @param amountIn The amount of input tokens to swap.
     * @param from The address transferring tokens (Vault).
     * @param to The address receiving tokens (Vault).
     * @param path The swap path (e.g., [tokenA, tokenB]).
     * @param deadline The deadline for the transaction.
     */
    function execute(
        uint256 amountIn,
        uint256 maxSlippage,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        _validatePriceImpact(amountIn, path);
        _swapTokens(amountIn, maxSlippage, path, to, deadline);
    }

    /**
     * @notice Allows the admin to swap tokens on Uniswap.
     * @param amountIn Amount of input tokens to swap.
     * @param amountOutMin Minimum amount of output tokens required.
     * @param path Array of token addresses representing the swap path.
     * @param to Receiver.
     * @param deadline Unix timestamp after which the swap will expire.
     */
    function _swapTokens(
        uint256 amountIn,
        uint256 maxSlippage,
        address[] calldata path,
        address to,
        uint256 deadline
    ) private {
        require(path.length >= 2, "Invalid path");
        require(amountIn > 0, "Vault: Invalid amount");
        require(path[0] == address(token), "Vault: Invalid path");

        // Fetch the latest price from Chainlink to calculate the expected output
        int256 latestPrice = getValidatedPrice(); // Uses Chainlink oracle for price validation
        require(latestPrice > 0, "Vault: Invalid price feed");

        // Calculate the minimum amountOut based on the oracle price
        uint256 expectedAmountOut = calculateAmountOutMinChainLink(
            amountIn,
            uint256(latestPrice)
        );

        // Approve Uniswap Router to spend the tokens
        IERC20(path[0]).approve(address(uniswapRouter), amountIn);

        // Perform the swap on Uniswap
        uint256[] memory amountsOut = uniswapRouter.swapExactTokensForTokens(
            amountIn,
            expectedAmountOut, // Use calculated minimum output with slippage
            path,
            to,
            deadline
        );

        // Ensure the swap result meets expectations
        uint256 finalOutput = amountsOut[amountsOut.length - 1];
        require(
            finalOutput >= expectedAmountOut,
            "Vault: Swap output below acceptable slippage"
        );
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
            : uint256(getValidatedPrice());
        uint256 amountOut = (amountIn * usedPrice) / 1e18;
        uint256 slippageAmount = (amountOut * maxSlippage) / 10_000; // Slippage in basis points
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
            int256 answer /*uint startedAt*/,
            ,
            ,

        ) = /*uint timeStamp*/
            /*uint80 answeredInRound*/
            dataFeed.latestRoundData();
        return answer;
    }

    function _validatePriceImpact(
        uint256 amountIn,
        address[] calldata path
    ) internal view {
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(
            amountIn,
            path
        );
        uint256 initialPrice = amountsOut[0];
        uint256 finalPrice = amountsOut[amountsOut.length - 1];

        // Calculate price impact percentage
        uint256 priceImpact = ((initialPrice - finalPrice) * 10_000) /
            initialPrice; // Basis points (BPS)

        require(priceImpact <= maxSlippage, "Vault: Price impact too high");
    }

    /**
        The withdrawal of all tokens must be implemented in the Vault without performing
        swaps to proactively prevent any potential issues with faulty swaps
    */
    function withdrawAll() external override returns (uint256) {
        return 0;
    }

    /**
     * @notice Validates the price retrieved from the Chainlink oracle.
     * @param price The price value to validate.
     * @return True if the price is valid, otherwise it reverts.
     */
    function _isPriceValid(int256 price) internal view returns (bool) {
        require(price > 0, "Vault: Invalid price"); // Ensure the price is positive and non-zero

        // Retrieve timestamp data from the Chainlink oracle
        (, , uint256 startedAt, uint256 updatedAt, ) = dataFeed
            .latestRoundData();

        // Ensure the price data is fresh and within an acceptable timeframe
        uint256 currentTime = block.timestamp;
        require(updatedAt >= startedAt, "Vault: Price feed data is stale");
        require(
            currentTime - updatedAt <= 1 hours,
            "Vault: Price data is outdated"
        );

        return true;
    }
}
