// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";

contract TokenTest is Test {
    Token public token;
    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    string constant NAME = "Test Token";
    string constant SYMBOL = "TEST";
    uint8 constant DECIMALS = 18;
    uint256 constant INITIAL_SUPPLY = 1_000_000;
    uint256 constant INITIAL_SUPPLY_WEI = INITIAL_SUPPLY * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        vm.prank(deployer);
        token = new Token(NAME, SYMBOL, DECIMALS, INITIAL_SUPPLY);
    }

    // ============ DEPLOYMENT TESTS ============
    function test_Deployment_SetsNameCorrectly() public view { assertEq(token.name(), NAME); }
    function test_Deployment_SetsSymbolCorrectly() public view { assertEq(token.symbol(), SYMBOL); }
    function test_Deployment_SetsDecimalsCorrectly() public view { assertEq(token.decimals(), DECIMALS); }
    function test_Deployment_SetsOwnerToDeployer() public view { assertEq(token.owner(), deployer); }
    function test_Deployment_MintsInitialSupplyToDeployer() public view { assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI); }
    function test_Deployment_SetsTotalSupply() public view { assertEq(token.totalSupply(), INITIAL_SUPPLY_WEI); }

    function test_Deployment_ZeroInitialSupply() public {
        vm.prank(alice);
        Token zeroToken = new Token("Zero", "ZERO", 18, 0);
        assertEq(zeroToken.totalSupply(), 0);
        assertEq(zeroToken.balanceOf(alice), 0);
    }

    // ============ TRANSFER TESTS ============
    function test_Transfer_MovesTokens() public {
        uint256 amount = 100e18;
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI - amount);
    }

    function test_Transfer_EmitsEvent() public {
        uint256 amount = 100e18;
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        token.transfer(alice, amount);
    }

    function test_Transfer_ReturnsTrue() public {
        vm.prank(deployer);
        bool success = token.transfer(alice, 100e18);
        assertTrue(success);
    }

    function test_Transfer_EntireBalance() public {
        vm.prank(deployer);
        token.transfer(alice, INITIAL_SUPPLY_WEI);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY_WEI);
    }

    function test_Transfer_ZeroAmount() public {
        vm.prank(deployer);
        token.transfer(alice, 0);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Transfer_RevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Token.InsufficientBalance.selector, alice, 0, 100e18));
        token.transfer(bob, 100e18);
    }

    function test_Transfer_RevertsOnZeroAddressRecipient() public {
        vm.prank(deployer);
        vm.expectRevert(Token.ZeroAddress.selector);
        token.transfer(address(0), 100e18);
    }

    // ============ APPROVE TESTS ============
    function test_Approve_SetsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 500e18);
        assertEq(token.allowance(deployer, alice), 500e18);
    }

    function test_Approve_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(deployer, alice, 500e18);
        vm.prank(deployer);
        token.approve(alice, 500e18);
    }

    function test_Approve_OverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 500e18);
        token.approve(alice, 200e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 200e18);
    }

    function test_Approve_RevertsOnZeroAddressSpender() public {
        vm.prank(deployer);
        vm.expectRevert(Token.ZeroAddress.selector);
        token.approve(address(0), 500e18);
    }

    // ============ TRANSFERFROM TESTS ============
    function test_TransferFrom_MovesTokensWithApproval() public {
        uint256 amount = 100e18;
        vm.prank(deployer);
        token.approve(alice, amount);
        vm.prank(alice);
        token.transferFrom(deployer, bob, amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI - amount);
    }

    function test_TransferFrom_DecreasesAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 500e18);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 200e18);
        assertEq(token.allowance(deployer, alice), 300e18);
    }

    function test_TransferFrom_InfiniteApprovalDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 100e18);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_TransferFrom_RevertsOnInsufficientAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 50e18);
        vm.expectRevert(abi.encodeWithSelector(Token.InsufficientAllowance.selector, alice, 50e18, 100e18));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 100e18);
    }

    function test_TransferFrom_RevertsWithNoApproval() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Token.InsufficientAllowance.selector, alice, 0, 100e18));
        token.transferFrom(deployer, bob, 100e18);
    }

    // ============ MINT TESTS ============
    function test_Mint_IncreasesBalance() public {
        vm.prank(deployer);
        token.mint(alice, 500e18);
        assertEq(token.balanceOf(alice), 500e18);
    }

    function test_Mint_IncreasesTotalSupply() public {
        vm.prank(deployer);
        token.mint(alice, 500e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY_WEI + 500e18);
    }

    function test_Mint_EmitsTransferFromZeroAddress() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, 500e18);
        vm.prank(deployer);
        token.mint(alice, 500e18);
    }

    function test_Mint_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(Token.NotOwner.selector);
        token.mint(alice, 500e18);
    }

    function test_Mint_RevertsOnZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(Token.ZeroAddress.selector);
        token.mint(address(0), 500e18);
    }

    // ============ BURN TESTS ============
    function test_Burn_DecreasesBalance() public {
        vm.prank(deployer);
        token.burn(100e18);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI - 100e18);
    }

    function test_Burn_DecreasesTotalSupply() public {
        vm.prank(deployer);
        token.burn(100e18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY_WEI - 100e18);
    }

    function test_Burn_EmitsTransferToZeroAddress() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, address(0), 100e18);
        vm.prank(deployer);
        token.burn(100e18);
    }

    function test_Burn_RevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Token.InsufficientBalance.selector, alice, 0, 100e18));
        token.burn(100e18);
    }

    // ============ OWNERSHIP TESTS ============
    function test_TransferOwnership_ChangesOwner() public {
        vm.prank(deployer);
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);
    }

    function test_TransferOwnership_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(deployer, alice);
        vm.prank(deployer);
        token.transferOwnership(alice);
    }

    function test_TransferOwnership_NewOwnerCanMint() public {
        vm.prank(deployer);
        token.transferOwnership(alice);
        vm.prank(alice);
        token.mint(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_TransferOwnership_OldOwnerCannotMint() public {
        vm.prank(deployer);
        token.transferOwnership(alice);
        vm.prank(deployer);
        vm.expectRevert(Token.NotOwner.selector);
        token.mint(bob, 100e18);
    }

    function test_TransferOwnership_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(Token.NotOwner.selector);
        token.transferOwnership(alice);
    }

    function test_TransferOwnership_RevertsOnZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(Token.ZeroAddress.selector);
        token.transferOwnership(address(0));
    }

    // ============ INCREASE/DECREASE ALLOWANCE TESTS ============
    function test_IncreaseAllowance_AddsToExisting() public {
        vm.startPrank(deployer);
        token.approve(alice, 100e18);
        token.increaseAllowance(alice, 50e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 150e18);
    }

    function test_DecreaseAllowance_SubtractsFromExisting() public {
        vm.startPrank(deployer);
        token.approve(alice, 100e18);
        token.decreaseAllowance(alice, 30e18);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 70e18);
    }

    function test_DecreaseAllowance_RevertsOnUnderflow() public {
        vm.startPrank(deployer);
        token.approve(alice, 50e18);
        vm.expectRevert(abi.encodeWithSelector(Token.InsufficientAllowance.selector, deployer, 50e18, 100e18));
        token.decreaseAllowance(alice, 100e18);
        vm.stopPrank();
    }

    // ============ FUZZ TESTS ============
    function testFuzz_Transfer_NeverExceedsBalance(uint256 transferAmount) public {
        transferAmount = bound(transferAmount, 0, INITIAL_SUPPLY_WEI);
        vm.prank(deployer);
        token.transfer(alice, transferAmount);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice), token.totalSupply());
    }

    function testFuzz_Approve_SetsExactAmount(uint256 amount) public {
        vm.prank(deployer);
        token.approve(alice, amount);
        assertEq(token.allowance(deployer, alice), amount);
    }

    function testFuzz_TransferFrom_DecreasesAllowanceCorrectly(uint256 approveAmount, uint256 transferAmount) public {
        approveAmount = bound(approveAmount, 1, INITIAL_SUPPLY_WEI);
        transferAmount = bound(transferAmount, 1, approveAmount);
        vm.prank(deployer);
        token.approve(alice, approveAmount);
        vm.prank(alice);
        token.transferFrom(deployer, bob, transferAmount);
        assertEq(token.allowance(deployer, alice), approveAmount - transferAmount);
    }

    function testFuzz_MintAndBurn_MaintainsTotalSupply(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 0, 1e30);
        burnAmount = bound(burnAmount, 0, mintAmount);
        vm.startPrank(deployer);
        token.mint(alice, mintAmount);
        vm.stopPrank();
        vm.prank(alice);
        token.burn(burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY_WEI + mintAmount - burnAmount);
    }

    // ============ EDGE CASE TESTS ============
    function test_Transfer_ToSelf() public {
        vm.prank(deployer);
        token.transfer(deployer, 100e18);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI);
    }

    function test_MultipleTransfers_ChainedCorrectly() public {
        vm.prank(deployer);
        token.transfer(alice, 300e18);
        vm.prank(alice);
        token.transfer(bob, 200e18);
        vm.prank(bob);
        token.transfer(charlie, 100e18);
        assertEq(token.balanceOf(deployer), INITIAL_SUPPLY_WEI - 300e18);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(charlie), 100e18);
    }

    function test_Approve_DoesNotRequireBalance() public {
        vm.prank(alice);
        token.approve(bob, 1000e18);
        assertEq(token.allowance(alice, bob), 1000e18);
    }
}
