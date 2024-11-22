// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../Vault.sol";

contract VaultV2 is Vault {
    function newLogic() external pure returns (string memory) {
        return "Vault V2 logic is active!";
    }
}
