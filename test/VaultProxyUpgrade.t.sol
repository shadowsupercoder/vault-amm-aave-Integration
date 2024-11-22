// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "forge-std/Test.sol";
// import "../src/Vault.sol";
// import "../src/mock/VaultV2.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

// contract UUPSCounterTest is Test {
//     address public v1;
//     address public v2;
//     address public proxy;
//     address public admin = address(2);
//     address public token = address(3);
//     Vault vaultProxy;

//     function setUp() public {
//         Vault v = new Vault();
//         v1 = address(v);
//         bytes memory data = abi.encodeCall(v.initialize, (token, admin));
//         proxy = address(new ERC1967Proxy(v1, data));
//         vaultProxy = Vault(proxy);
//     }

//     function testSetNumber() public {
//         VaultV2 v = new VaultV2();
//         v2 = address(v);

//          vm.startPrank(admin);

//         // Upgrade proxy to Vault V2 without additional initialization
//         UUPSUpgradeable(proxy).upgradeProxy(v2);

//         // Verify new logic is active
//         assertEq(VaultV2(proxy).newLogic(), "Vault V2 logic is active!");

//         vm.stopPrank();
//     }
//     // function testCheckMainVault() public view {
//     //     address _token = address(vaultProxy.token());
//     //     assertEq(_token, token);
//     //     assertTrue(
//     //         vaultProxy.hasRole(vaultProxy.DEFAULT_ADMIN_ROLE(), admin),
//     //         "Admin role not assigned"
//     //     );
//     // }

// }

import "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../src/Vault.sol";
import "../src/mock/VaultV2.sol";

contract VaultProxyTest is Test {
    address public admin = address(2);
    address public token = address(3);

    address vaultProxy;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy proxy with Vault V1 implementation
        vaultProxy = Upgrades.deployUUPSProxy(
            "Vault.sol",
            abi.encodeCall(Vault.initialize, (token, admin))
        );
        vm.stopPrank();
    }

    function testUpgradeToV2() public {
        vm.startPrank(admin);

        // Upgrade proxy to Vault V2
        Upgrades.upgradeProxy(vaultProxy, "VaultV2.sol", "");
        // Verify new logic
        VaultV2 upgradedProxy = VaultV2(address(vaultProxy));
        assertEq(
            upgradedProxy.newLogic(),
            "Vault V2 logic is active!",
            "Upgrade failed"
        );

        vm.stopPrank();
    }

    // todo: add more tests
}
