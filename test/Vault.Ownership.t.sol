// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract VaultOwnershipTest is Test {
    Vault vault;
    MockERC20 token;
    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);

    function setUp() public {
        // Deploy the mock ERC20 token
        token = new MockERC20();

        // Deploy and initialize the vault contract with the admin
        vm.startPrank(admin);
        vault = new Vault(address(token));
        vault.initialize(admin);
        vm.stopPrank();
    }

    /*
        Ensure only the admin can grant and revoke roles.
    */
    function testAdminCanGrantAndRevokeRoles() public {
        // Admin grants DEFAULT_ADMIN_ROLE to user1
        vm.startPrank(admin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user1);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user2);
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user2));

        // Admin revokes DEFAULT_ADMIN_ROLE from user1
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), user2);
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user2));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));

        vm.stopPrank();
    }

    /*
       Ensure only the admin can call the emergencyWithdraw function.
    */
    function testOnlyAdminCanCallEmergencyWithdraw() public {
        // Non-admin tries to call emergencyWithdraw
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(user1),
                vault.DEFAULT_ADMIN_ROLE()
            )
        );
        vault.emergencyWithdraw();
       vm.stopPrank();

        // Admin calls emergencyWithdraw successfully
        vm.prank(admin);
        vault.emergencyWithdraw();
    }

    /*
         Ensure non-admins cannot grant or revoke roles. FIXME
    */
    // function testNonAdminCannotGrantOrRevokeRoles() public {
    //     assertFalse(vault.hasRole(vault.ADMIN_ROLE(), user1));
    //     assertFalse(vault.hasRole(vault.ADMIN_ROLE(), user2));
    //     // Non-admin (user1) tries to grant ADMIN_ROLE to user2
    //     vm.startPrank(user1);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );
     
    //     vault.grantRole(vault.ADMIN_ROLE(), user2);

    //     // Non-admin (user1) tries to revoke ADMIN_ROLE from admin
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );
    //     vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), admin);
    //     vm.stopPrank();
    // }

    /*
       Attempt to grant roles with a non-admin account and expect failure. FIXME
    */
    // function testNonAdminCannotGrantRole() public {
    //     // User1 tries to grant ADMIN_ROLE to themselves
    //     vm.startPrank(user1);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );
       
    //     vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user1);


    //     // Ensure user1 still doesn't have the role
    //     assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));
    //     vm.stopPrank();
    // }
}
