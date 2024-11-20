// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "aave/interfaces/IPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IStrategy.sol";

contract AaveStrategy is IStrategy {
    IPool public immutable aavePool;
    IERC20 public immutable token;

    constructor(address _aavePool, address _token) {
        require(_aavePool != address(0), "Invalid Aave Pool");
        require(_token != address(0), "Invalid Token");
        aavePool = IPool(_aavePool);
        token = IERC20(_token);
    }

    function execute(bytes calldata params) external {
        (uint256 amount, , address from) = abi.decode(
            params,
            (uint256, address, address)
        );
        require(amount > 0, "Invalid amount");

        // Transfer tokens from Vault to the strategy
        token.transferFrom(from, address(this), amount);

        _lendToAave(amount);
    }

    function withdraw(bytes calldata params) external {
        (uint256 amount, , ) = abi.decode(params, (uint256, address, address));

        require(amount > 0, "Invalid amount");

        // Withdraw from Aave to the Vault
        aavePool.withdraw(address(token), amount, address(this));
    }

    function getBalance() external view returns (uint256) {
        (uint256 totalCollateralBase, , , , , ) = aavePool.getUserAccountData(
            address(this)
        );
        return totalCollateralBase;
    }

    /**
     * @notice Internal function to handle supplying tokens to Aave.
     * @dev The function `lendToAave` performs the actual supply operation.
     *      It requires the token amount to be greater than zero and approves the Aave pool to use the tokens.
     * @param amount The amount of tokens to supply.
     */

    function _lendToAave(uint256 amount) private {
        require(amount > 0, "Vault: Amount must be greater than zero");
        token.approve(address(aavePool), amount);
        aavePool.supply(address(token), amount, address(this), 0);
    }

    /**
     * @notice Borrows a specified amount of tokens from Aave for leverage or other strategies.
     * @dev This function is restricted to the admin role.
     * @param asset The address of the asset to borrow.
     * @param amount The amount of tokens to borrow.
     * @param interestRateMode The interest rate mode: 1 for stable, 2 for variable.
     */
    function borrowFromAave(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external {
        require(amount > 0, "Vault: Amount must be greater than zero");
        aavePool.borrow(asset, amount, interestRateMode, 0, address(this));
    }
    /**
     * @notice Repays a specified amount of borrowed tokens to Aave.
     * @dev This function is restricted to the admin role.
     *      It approves the Aave pool to use the tokens before repayment.
     * @param asset The address of the asset being repaid.
     * @param amount The amount of tokens to repay.
     * @param interestRateMode The interest rate mode: 1 for stable, 2 for variable.
     */

    function repayToAave(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) public {
        require(amount > 0, "Vault: Amount must be greater than zero");
        IERC20(asset).approve(address(aavePool), amount);
        aavePool.repay(asset, amount, interestRateMode, address(this));
    }
    /**
     * @notice Fetches the current health factor of the vault's Aave position.
     * @return healthFactor The health factor, scaled to 18 decimals. A value below 1 indicates risk of liquidation.
     */

    function getHealthFactor() public view returns (uint256) {
        (, , , , , uint256 healthFactor) = aavePool.getUserAccountData(
            address(this)
        );
        return healthFactor;
    }
    /**
     * @notice Performs an emergency repayment to restore the health factor above the liquidation threshold.
     * @dev This function is restricted to the admin role and requires the current health factor to be below 1.
     *      It approves the Aave pool to use the tokens before repayment.
     * @param asset The address of the asset being repaid.
     * @param amount The amount of tokens to repay.
     * @param interestRateMode The interest rate mode: 1 for stable, 2 for variable.
     */

    function emergencyRepay(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external {
        uint256 healthFactor = getHealthFactor();
        require(healthFactor < 1e18, "Vault: Health factor is safe");

        repayToAave(asset, amount, interestRateMode);
    }

    /**
     * @notice Withdraws all tokens from Aave and returns the amount withdrawn.
     * @return The total amount withdrawn.
     */
    function withdrawAll() external override returns (uint256) {
        uint256 balanceBefore = token.balanceOf(address(this));

        // Withdraw maximum available from Aave
        aavePool.withdraw(address(token), type(uint256).max, address(this));

        uint256 balanceAfter = token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }
}
