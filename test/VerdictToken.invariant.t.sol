// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @dev Restricts transfers to a closed set of holders so every balance can be accounted for.
contract VerdictTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    VerdictToken private immutable token;
    address[4] private actors;

    // An independent journal of requested movements, never copied from token getters.
    // The constructor allocation is the first credit. Self-transfers add equal entries.
    mapping(address => uint256) public credited;
    mapping(address => uint256) public debited;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(VerdictToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        credited[actors_[0]] = SUPPLY;
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return credited[actor] - debited[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = _transferAmount(amount, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : _transferAmount(amount, SUPPLY);
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance(owner);
        uint256 allowance = expectedAllowance[owner][spender];
        amount = _transferAmount(amount, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 extra) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance(from);
        uint256 amount = held + bound(extra, 1, type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // Rejected calls leave the journal unchanged; the invariants check rollback.
    }

    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 extra,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance(owner);
        uint256 amount = held + bound(extra, 1, type(uint256).max - held);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, SUPPLY - 1);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        operation %= 3;
        if (operation == 0) {
            amount = _transferAmount(amount, expectedBalance(owner));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (operation == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amount);
        } else {
            amount = _transferAmount(amount, expectedBalance(owner));
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        debited[from] += amount;
        credited[to] += amount;
    }

    // Keep zero, one base unit and full-balance operations frequent in long sequences.
    function _transferAmount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum;
        if (seed % 4 == 2) return maximum == 0 ? 0 : 1;
        return bound(seed, 0, maximum);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract VerdictTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    VerdictToken private token;
    VerdictTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new VerdictToken();
        actors = [makeAddr("holder0"), makeAddr("holder1"), makeAddr("holder2"), makeAddr("holder3")];
        handler = new VerdictTokenHandler(token, actors);
        token.transfer(actors[0], SUPPLY);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = VerdictTokenHandler.transfer.selector;
        selectors[1] = VerdictTokenHandler.approve.selector;
        selectors[2] = VerdictTokenHandler.transferFrom.selector;
        selectors[3] = VerdictTokenHandler.revoke.selector;
        selectors[4] = VerdictTokenHandler.transferOverBalance.selector;
        selectors[5] = VerdictTokenHandler.transferFromOverBalance.selector;
        selectors[6] = VerdictTokenHandler.transferFromOverAllowance.selector;
        selectors[7] = VerdictTokenHandler.rejectZeroAddress.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_TotalSupplyAndSumOfBalancesStayConstant() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_EachBalanceMatchesTransferHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "incorrect holder balance");
        }
    }

    function invariant_AllowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "incorrect owner/spender allowance"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    /// @dev Deterministically exercise every handler, including nonzero delegated spending,
    /// so those checks do not depend solely on the random selector distribution.
    function test_HandlerExercisesSpendingRevocationAndRollback() public {
        handler.transfer(0, 1, 2); // one base unit
        _checkAllInvariants();
        handler.approve(0, 2, 1, false); // whole supply, finite approval
        _checkAllInvariants();
        handler.transferFrom(0, 2, 3, 2); // spend one base unit
        assertEq(token.balanceOf(actors[3]), 1);
        assertEq(token.allowance(actors[0], actors[2]), SUPPLY - 1);
        _checkAllInvariants();
        handler.transferFrom(0, 2, 0, 1); // full-balance self-transfer
        _checkAllInvariants();
        handler.approve(1, 1, 0, true);
        handler.transferFrom(1, 1, 2, 1); // owner is spender, infinite approval
        assertEq(token.balanceOf(actors[2]), 1);
        assertEq(token.allowance(actors[1], actors[1]), type(uint256).max);
        _checkAllInvariants();
        handler.revoke(1, 1);
        _checkAllInvariants();
        handler.transferOverBalance(2, 2, type(uint256).max);
        _checkAllInvariants();
        handler.transferFromOverBalance(2, 0, 3, 1, false);
        _checkAllInvariants();
        handler.transferFromOverBalance(2, 0, 3, type(uint256).max, true);
        _checkAllInvariants();
        handler.transferFromOverAllowance(0, 2, 1, 0);
        _checkAllInvariants();
        for (uint8 operation; operation < 3; ++operation) {
            handler.rejectZeroAddress(0, 2, 1, operation);
            _checkAllInvariants();
        }
    }

    function _checkAllInvariants() private view {
        invariant_TotalSupplyAndSumOfBalancesStayConstant();
        invariant_EachBalanceMatchesTransferHistory();
        invariant_AllowancesMatchApprovalsAndSpending();
    }
}
