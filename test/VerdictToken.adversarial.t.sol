// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

contract RejectingTokenRecipient {
    fallback() external {
        revert("ERC20 transfers must not require recipient callbacks");
    }
}

/// @notice Boundary and authorization cases that complement the original token tests.
/// forge-config: default.fuzz.runs = 1000
contract VerdictTokenAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    VerdictToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new VerdictToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_OneBaseUnitRoundTripPreservesSupplyAndEmitsEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        _assertBalances(1, 0, 0);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(0, 0, 0);
    }

    function test_DelegatedTransferOfWholeSupplyExhaustsFiniteApproval() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        _assertBalances(SUPPLY, 0, 0);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_MaximumFiniteApprovalDecreasesByOneBaseUnit() public {
        uint256 finite = type(uint256).max - 1;
        assertTrue(token.approve(spender, finite));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), finite - 1);
        _assertBalances(1, 0, 0);
    }

    function test_UnlimitedApprovalCanBeReplacedWithFiniteApprovalAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(2, 0, 0);
    }

    function test_ZeroAmountDoesNotMakeZeroRecipientOrSpenderValid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(0, 0, 0);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesExistingApproval() public {
        token.approve(spender, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(0, 0, 0);
    }

    function test_SelfTransferCannotBypassBalanceCheck() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);

        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(1, 0, 0);
    }

    function test_UnlimitedApprovalDoesNotPermitUint256MaxOverdraft() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0, 0);
    }

    function test_ApprovalSurvivesDirectSpendingAndCanBeUsedAfterRefill() public {
        token.transfer(alice, 5);
        vm.prank(alice);
        token.approve(spender, 7);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 5));
        assertEq(token.allowance(alice, spender), 7);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5));
        vm.prank(spender);
        token.transferFrom(alice, bob, 5);
        assertEq(token.allowance(alice, spender), 7);
        _assertBalances(0, 5, 0);

        vm.prank(bob);
        token.transfer(alice, 5);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 5));
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(0, 5, 0);
    }

    function test_TransferUsesCallerBalanceInsteadOfTransactionOrigin() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob, alice);
        token.transfer(spender, 1);
        _assertBalances(1, 0, 0);

        vm.prank(alice, bob);
        assertTrue(token.transfer(spender, 1));
        _assertBalances(0, 0, 1);
    }

    function test_DelegatedTransferUsesCallerApprovalInsteadOfTransactionOrigin() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(0, 0, 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(1, 0, 0);
    }

    function test_TransfersToContractsDoNotRequireRecipientCallbacks() public {
        RejectingTokenRecipient receiver = new RejectingTokenRecipient();
        assertTrue(token.transfer(address(receiver), 1));
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(receiver), 1));
        assertEq(token.balanceOf(address(receiver)), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NativeValueCannotBeAcceptedThroughTransferOrFallback() public {
        vm.deal(address(this), 2);
        (bool transferred,) =
            address(token).call{value: 1}(abi.encodeWithSignature("transfer(address,uint256)", alice, 1));
        assertFalse(transferred);
        (bool received,) = address(token).call{value: 1}("");
        assertFalse(received);
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 2);
        _assertBalances(0, 0, 0);
    }

    function test_TransferFromZeroAddressCannotManufactureTokensEvenForZeroAmount() public {
        // Multiple preconditions fail; rejection matters, not which validation runs first.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.allowance(address(0), spender), 0);
        _assertBalances(0, 0, 0);
    }

    function testFuzz_ApprovalReplacesRatherThanAddsAndIsIdempotent(uint256 first, uint256 replacement) public {
        // An empty holder may approve any uint256, independently of its current balance.
        vm.prank(alice);
        assertTrue(token.approve(spender, first));
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(alice, spender, replacement);
            vm.prank(alice);
            assertTrue(token.approve(spender, replacement));
            assertEq(token.allowance(alice, spender), replacement);
        }
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, 0, 0);
    }

    function testFuzz_FailedDelegatedTransferPreservesBalancesAndApproval(
        uint256 held,
        uint256 requested,
        uint256 approved,
        bool invalidRecipient
    ) public {
        held = bound(held, 0, SUPPLY);
        token.transfer(alice, held);
        requested = invalidRecipient ? bound(requested, 0, held) : bound(requested, held + 1, type(uint256).max);
        approved = bound(approved, requested, type(uint256).max);
        vm.prank(alice);
        token.approve(spender, approved);
        bytes memory expectedError = invalidRecipient
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested);

        vm.expectRevert(expectedError);
        vm.prank(spender);
        token.transferFrom(alice, invalidRecipient ? address(0) : bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(held, 0, 0);

        // A rejection must not freeze later valid spending or corrupt the restored approval.
        uint256 valid = held < approved ? held : approved;
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, valid));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - valid);
        _assertBalances(held - valid, valid, 0);
    }

    function testFuzz_InsufficientApprovalRejectsOtherwiseAffordableTransfer(
        uint256 held,
        uint256 approved,
        uint256 requested
    ) public {
        held = bound(held, 1, SUPPLY);
        approved = bound(approved, 0, held - 1);
        requested = bound(requested, approved + 1, held);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(held, 0, 0);
    }

    function testFuzz_DelegatedTransferHandlesEveryActorAlias(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        // All five equality partitions of owner / spender / recipient, on fresh instances.
        for (uint256 mode; mode < 5; ++mode) {
            VerdictToken fresh = new VerdictToken();
            fresh.transfer(alice, SUPPLY);
            address caller = mode == 1 || mode == 4 ? alice : spender;
            address recipient = mode == 2 || mode == 4 ? alice : mode == 3 ? spender : bob;
            vm.prank(alice);
            fresh.approve(caller, approved);
            vm.expectEmit(true, true, false, true, address(fresh));
            emit Transfer(alice, recipient, amount);
            vm.prank(caller);
            assertTrue(fresh.transferFrom(alice, recipient, amount));
            assertEq(fresh.balanceOf(alice), recipient == alice ? SUPPLY : SUPPLY - amount);
            assertEq(fresh.balanceOf(bob), recipient == bob ? amount : 0);
            assertEq(fresh.balanceOf(spender), recipient == spender ? amount : 0);
            assertEq(fresh.balanceOf(address(this)), 0);
            assertEq(fresh.allowance(alice, caller), approved == type(uint256).max ? approved : approved - amount);
            assertEq(fresh.totalSupply(), SUPPLY);
        }
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance, uint256 spenderBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), spenderBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance - spenderBalance);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
