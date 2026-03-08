// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Token} from "../src/Token.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract TokenFactoryTest is Test {
    TokenFactory public factory;
    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant CREATION_FEE = 0.01 ether;

    event TokenCreated(address indexed tokenAddress, address indexed creator, string name, string symbol, uint256 initialSupply);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        factory = new TokenFactory(CREATION_FEE);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // ============ DEPLOYMENT TESTS ============
    function test_Factory_Deployment() public view {
        assertEq(factory.owner(), deployer);
        assertEq(factory.creationFee(), CREATION_FEE);
        assertEq(factory.totalTokens(), 0);
    }

    // ============ TOKEN CREATION TESTS ============
    function test_CreateToken_DeploysNewToken() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
        assertTrue(tokenAddr != address(0));
        assertTrue(factory.isFactoryToken(tokenAddr));
    }

    function test_CreateToken_SetsTokenPropertiesCorrectly() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
        Token token = Token(tokenAddr);
        assertEq(token.name(), "Alice Token");
        assertEq(token.symbol(), "ALICE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000 * 1e18);
    }

    function test_CreateToken_TransfersOwnershipToCreator() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
        Token token = Token(tokenAddr);
        assertEq(token.owner(), alice);
    }

    function test_CreateToken_MintsSupplyToFactory_ThenOwnedByCreator() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
        Token token = Token(tokenAddr);
        assertEq(token.balanceOf(address(factory)), 1_000_000 * 1e18);
        assertEq(token.owner(), alice);
    }

    function test_CreateToken_EmitsEvent() public {
        vm.expectEmit(false, true, false, true);
        emit TokenCreated(address(0), alice, "Alice Token", "ALICE", 1_000_000);
        vm.prank(alice);
        factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
    }

    function test_CreateToken_RegistersInAllTokens() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Alice Token", "ALICE", 18, 1_000_000);
        assertEq(factory.totalTokens(), 1);
        assertEq(factory.allTokens(0), tokenAddr);
    }

    function test_CreateToken_RegistersInTokensByCreator() public {
        vm.startPrank(alice);
        address token1 = factory.createToken{value: CREATION_FEE}("Token One", "ONE", 18, 1_000_000);
        address token2 = factory.createToken{value: CREATION_FEE}("Token Two", "TWO", 18, 500_000);
        vm.stopPrank();
        address[] memory aliceTokens = factory.getTokensByCreator(alice);
        assertEq(aliceTokens.length, 2);
        assertEq(aliceTokens[0], token1);
        assertEq(aliceTokens[1], token2);
    }

    function test_CreateToken_ZeroInitialSupply() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Zero Token", "ZERO", 18, 0);
        Token token = Token(tokenAddr);
        assertEq(token.totalSupply(), 0);
    }

    // ============ FEE TESTS ============
    function test_CreateToken_RevertsOnInsufficientFee() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TokenFactory.InsufficientFee.selector, 0.005 ether, CREATION_FEE));
        factory.createToken{value: 0.005 ether}("Cheap Token", "CHEAP", 18, 1_000_000);
    }

    function test_CreateToken_AcceptsExactFee() public {
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Exact Fee", "EXACT", 18, 1_000_000);
        assertTrue(tokenAddr != address(0));
    }

    function test_CreateToken_RefundsExcessFee() public {
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        factory.createToken{value: 1 ether}("Overpaid Token", "OVER", 18, 1_000_000);
        uint256 balanceAfter = alice.balance;
        assertEq(balanceBefore - balanceAfter, CREATION_FEE);
    }

    function test_CreateToken_FeeCollectedByFactory() public {
        vm.prank(alice);
        factory.createToken{value: CREATION_FEE}("Fee Token", "FEE", 18, 1_000_000);
        assertEq(address(factory).balance, CREATION_FEE);
    }

    function test_CreateToken_ZeroFeeFactory() public {
        vm.prank(deployer);
        TokenFactory freeFactory = new TokenFactory(0);
        vm.prank(alice);
        address tokenAddr = freeFactory.createToken("Free Token", "FREE", 18, 1_000_000);
        assertTrue(tokenAddr != address(0));
    }

    // ============ VALIDATION TESTS ============
    function test_CreateToken_RevertsOnEmptyName() public {
        vm.prank(alice);
        vm.expectRevert(TokenFactory.EmptyName.selector);
        factory.createToken{value: CREATION_FEE}("", "SYM", 18, 1_000_000);
    }

    function test_CreateToken_RevertsOnEmptySymbol() public {
        vm.prank(alice);
        vm.expectRevert(TokenFactory.EmptySymbol.selector);
        factory.createToken{value: CREATION_FEE}("Name", "", 18, 1_000_000);
    }

    // ============ CREATE2 DETERMINISTIC ADDRESS TESTS ============
    function test_PredictTokenAddress_MatchesActualDeployment() public {
        address predicted = factory.predictTokenAddress(alice, "Predicted Token", "PRED", 18, 1_000_000);
        vm.prank(alice);
        address actual = factory.createToken{value: CREATION_FEE}("Predicted Token", "PRED", 18, 1_000_000);
        assertEq(predicted, actual);
    }

    function test_CREATE2_DifferentCreators_DifferentAddresses() public {
        vm.prank(alice);
        address aliceToken = factory.createToken{value: CREATION_FEE}("Same Name", "SAME", 18, 1_000_000);
        vm.prank(bob);
        address bobToken = factory.createToken{value: CREATION_FEE}("Same Name", "SAME", 18, 1_000_000);
        assertTrue(aliceToken != bobToken);
    }

    function test_CREATE2_DuplicateTokenReverts() public {
        // Same creator + same name + same symbol + same params = same CREATE2 salt + same init code = revert
        vm.startPrank(alice);
        factory.createToken{value: CREATION_FEE}("Unique Token", "UNI", 18, 1_000_000);
        vm.expectRevert();
        factory.createToken{value: CREATION_FEE}("Unique Token", "UNI", 18, 1_000_000);
        vm.stopPrank();
    }

    // ============ PAGINATION TESTS ============
    function test_GetTokensPaginated_ReturnsCorrectPage() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            factory.createToken{value: CREATION_FEE}(
                string(abi.encodePacked("Token ", vm.toString(i))),
                string(abi.encodePacked("T", vm.toString(i))),
                18, 1_000_000
            );
        }
        vm.stopPrank();
        (address[] memory tokens, uint256 total) = factory.getTokensPaginated(1, 3);
        assertEq(total, 5);
        assertEq(tokens.length, 3);
        assertEq(tokens[0], factory.allTokens(1));
        assertEq(tokens[2], factory.allTokens(3));
    }

    function test_GetTokensPaginated_OffsetBeyondTotal() public {
        vm.prank(alice);
        factory.createToken{value: CREATION_FEE}("Only Token", "ONLY", 18, 1_000_000);
        (address[] memory tokens, uint256 total) = factory.getTokensPaginated(10, 5);
        assertEq(total, 1);
        assertEq(tokens.length, 0);
    }

    function test_GetTokensPaginated_LimitExceedsRemaining() public {
        vm.startPrank(alice);
        for (uint256 i = 0; i < 3; i++) {
            factory.createToken{value: CREATION_FEE}(
                string(abi.encodePacked("Tok", vm.toString(i))),
                string(abi.encodePacked("T", vm.toString(i))),
                18, 1_000
            );
        }
        vm.stopPrank();
        (address[] memory tokens, uint256 total) = factory.getTokensPaginated(1, 100);
        assertEq(total, 3);
        assertEq(tokens.length, 2);
    }

    // ============ ADMIN TESTS ============
    function test_UpdateFee_ChangesCreationFee() public {
        vm.prank(deployer);
        factory.updateFee(0.05 ether);
        assertEq(factory.creationFee(), 0.05 ether);
    }

    function test_UpdateFee_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit FeeUpdated(CREATION_FEE, 0.05 ether);
        vm.prank(deployer);
        factory.updateFee(0.05 ether);
    }

    function test_UpdateFee_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(TokenFactory.NotOwner.selector);
        factory.updateFee(0.05 ether);
    }

    function test_WithdrawFees_SendsBalanceToRecipient() public {
        vm.prank(alice);
        factory.createToken{value: CREATION_FEE}("Fee Token", "FEE", 18, 1_000_000);
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(deployer);
        factory.withdrawFees(bob);
        assertEq(bob.balance, bobBalanceBefore + CREATION_FEE);
        assertEq(address(factory).balance, 0);
    }

    function test_WithdrawFees_EmitsEvent() public {
        vm.prank(alice);
        factory.createToken{value: CREATION_FEE}("Fee Token", "FEE", 18, 1_000_000);
        vm.expectEmit(true, false, false, true);
        emit FeesWithdrawn(bob, CREATION_FEE);
        vm.prank(deployer);
        factory.withdrawFees(bob);
    }

    function test_WithdrawFees_RevertsOnZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(TokenFactory.ZeroAddress.selector);
        factory.withdrawFees(address(0));
    }

    function test_WithdrawFees_RevertsForNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(TokenFactory.NotOwner.selector);
        factory.withdrawFees(alice);
    }

    function test_TransferOwnership_ChangesOwner() public {
        vm.prank(deployer);
        factory.transferOwnership(alice);
        assertEq(factory.owner(), alice);
    }

    function test_TransferOwnership_NewOwnerCanUpdateFee() public {
        vm.prank(deployer);
        factory.transferOwnership(alice);
        vm.prank(alice);
        factory.updateFee(0.1 ether);
        assertEq(factory.creationFee(), 0.1 ether);
    }

    // ============ FUZZ TESTS ============
    function testFuzz_CreateToken_AnyValidSupply(uint256 supply) public {
        supply = bound(supply, 0, 1e12);
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Fuzz Token", "FUZZ", 18, supply);
        Token token = Token(tokenAddr);
        assertEq(token.totalSupply(), supply * 1e18);
    }

    function testFuzz_CreateToken_AnyFeeAboveMinimum(uint256 fee) public {
        fee = bound(fee, CREATION_FEE, 10 ether);
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        factory.createToken{value: fee}("Fee Fuzz", "FFUZ", 18, 1_000);
        assertEq(balanceBefore - alice.balance, CREATION_FEE);
    }

    // ============ INTEGRATION TEST ============
    function test_FullWorkflow_CreateAndUseToken() public {
        // 1. Alice creates a token
        vm.prank(alice);
        address tokenAddr = factory.createToken{value: CREATION_FEE}("Workflow Token", "WORK", 18, 1_000_000);
        Token token = Token(tokenAddr);

        // 2. Alice mints more tokens (she's the owner)
        vm.prank(alice);
        token.mint(alice, 500_000e18);

        // 3. Verify balances
        assertEq(token.balanceOf(alice), 500_000e18);
        assertEq(token.balanceOf(address(factory)), 1_000_000e18);

        // 4. Alice transfers some to bob
        vm.prank(alice);
        token.transfer(bob, 100_000e18);
        assertEq(token.balanceOf(bob), 100_000e18);
        assertEq(token.balanceOf(alice), 400_000e18);

        // 5. Bob approves and charlie uses transferFrom
        address charlie = makeAddr("charlie");
        vm.prank(bob);
        token.approve(charlie, 50_000e18);

        vm.prank(charlie);
        token.transferFrom(bob, charlie, 25_000e18);

        assertEq(token.balanceOf(charlie), 25_000e18);
        assertEq(token.balanceOf(bob), 75_000e18);
        assertEq(token.allowance(bob, charlie), 25_000e18);
    }
}
