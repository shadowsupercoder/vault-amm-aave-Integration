// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20, SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Vault is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);

    constructor(IERC20 _token) {
        token = _token;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");

        uint256 newShares = totalShares == 0 ? amount : (amount * totalShares) / token.balanceOf(address(this));
        shares[msg.sender] += newShares;
        totalShares += newShares;

        emit Deposited(msg.sender, amount, newShares);

        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        require(shareAmount > 0 && shareAmount <= shares[msg.sender], "Invalid share amount");

        uint256 amount = (shareAmount * token.balanceOf(address(this))) / totalShares;
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;

        emit Withdrawn(msg.sender, amount, shareAmount);

        token.safeTransfer(msg.sender, amount);
    }
}
