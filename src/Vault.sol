// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "forge-std/console.sol";

contract Vault is AccessControlUpgradeable {
    IERC20 public immutable token;

    uint256 public totalSupply; // Total Supply of shares
    mapping(address => uint256) public balanceOf;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function initialize(address _admin) external initializer {
        __AccessControl_init();
        require(_admin != address(0), "Vault: Admin can not be zero address");
        // Grant the `DEFAULT_ADMIN_ROLE` and `ADMIN_ROLE` to the deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
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

    function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 contractBalance = token.balanceOf(address(this));
    }
}
