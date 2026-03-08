# Phase 1 Learning Guide — ERC-20 Token + Factory

Your goal: understand every line well enough to explain it in an interview. Study this guide alongside the code.

---

## Week 1: Solidity Fundamentals (via Token.sol)

### Day 1-2: State Variables & Types

Open `src/Token.sol` and study the state variables at the top:

```solidity
string public name;
string public symbol;
uint8 public decimals;
uint256 public totalSupply;
address public owner;
mapping(address => uint256) public balanceOf;
mapping(address => mapping(address => uint256)) public allowance;
```

**What to understand:**
- `public` auto-generates a getter function. `token.name()` works because of `public`.
- `uint256` = unsigned 256-bit integer. Range: 0 to 2^256 - 1. This is the default number type in Solidity.
- `uint8` = 0 to 255. Used for decimals because 18 fits in 8 bits.
- `address` = 20 bytes. Every wallet and contract has one.
- `mapping` = hash table. O(1) lookup. Cannot be iterated (no `.length` or `.keys()`).
- Nested mapping for `allowance`: first key is token owner, second key is spender.

**Interview questions to practice:**
1. "Why is there no `string[] public allHolders`?" — Because arrays are expensive to iterate on-chain. You'd use events + a subgraph for that.
2. "What's the max value of uint256?" — 2^256 - 1, approximately 1.15 * 10^77. Enough for any token supply.
3. "Why 18 decimals?" — ETH uses 18. It became the standard. 1 token = 1e18 wei. No floating point in Solidity.

### Day 3-4: Events & Errors

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
error InsufficientBalance(address account, uint256 balance, uint256 needed);
```

**What to understand:**
- Events are stored in transaction logs, NOT in contract storage. They're cheap (~375 gas + 8 gas/byte).
- `indexed` parameters go into "topics" — you can filter/search by them. Max 3 indexed per event.
- Custom errors (`error X()`) cost less gas than `require(condition, "string")` because the string is stored as a 4-byte selector, not the full string.
- Events are how frontends and subgraphs know what happened. The Graph indexes events to build queryable databases.

**Interview questions:**
1. "How do frontends know when a transfer happens?" — They listen for Transfer events via `eth_subscribe` or poll with `eth_getLogs`.
2. "Why use custom errors instead of require?" — Gas savings. ~100+ gas saved per revert. The error selector is 4 bytes vs storing a full string.
3. "What are indexed parameters?" — They go into log topics (separate from data). You can filter events by indexed params. Non-indexed go into the data field.

### Day 5-7: Functions (transfer, approve, transferFrom)

Study the three core ERC-20 functions. This is the most important part.

**transfer(to, amount):**
```
User A calls transfer(B, 100)
→ A.balance -= 100
→ B.balance += 100
→ emit Transfer(A, B, 100)
```

**approve(spender, amount) + transferFrom(from, to, amount):**
```
Step 1: User A calls approve(DEX, 1000)
→ allowance[A][DEX] = 1000

Step 2: DEX contract calls transferFrom(A, DEX, 500)
→ Check: allowance[A][DEX] >= 500? Yes (1000)
→ allowance[A][DEX] -= 500 → now 500
→ A.balance -= 500
→ DEX.balance += 500
→ emit Transfer(A, DEX, 500)
```

**This is HOW every DEX works.** When you swap on Uniswap:
1. Your wallet calls `approve(uniswapRouter, amount)` on the token contract
2. Uniswap router calls `transferFrom(you, pool, amount)` to pull your tokens
3. Router calculates output amount using AMM math
4. Router sends output tokens to you

**Interview questions:**
1. "Why can't a contract just receive tokens like ETH?" — ETH transfers trigger `receive()`. Token transfers are just balance updates in the token contract's storage. The receiving contract has no way to know it received tokens unless you tell it (that's why we need approve+transferFrom or ERC-777 hooks).
2. "What's the infinite approval pattern?" — Setting allowance to `type(uint256).max`. The contract skips the subtraction, saving gas. Most DEX frontends do this by default.
3. "What happens if you approve 100, then approve 50?" — The allowance becomes 50 (overwrite). But there's a front-running risk: spender can spend 100 before your new tx confirms, then spend 50 after = 150 total.

---

## Week 2: Factory Pattern & CREATE2 (via TokenFactory.sol)

### Day 1-3: The Factory Pattern

Open `src/TokenFactory.sol`. The factory deploys new Token contracts.

**Why use a factory?**
- Standardization: every token has identical, verified code
- Registry: factory tracks all tokens it created
- Discoverability: anyone can query `allTokens` or `tokensByCreator`
- UX: users call one function instead of deploying bytecode

**How createToken works:**
```
1. Validate inputs (name not empty, fee paid)
2. Generate salt = keccak256(creator, name, symbol)
3. Deploy new Token contract using CREATE2 with that salt
4. Transfer token ownership from factory to creator
5. Register token in allTokens array and tokensByCreator mapping
6. Refund excess ETH if overpaid
```

### Day 4-5: CREATE vs CREATE2

This is a favorite interview topic.

**CREATE (regular deployment):**
```
address = keccak256(deployer_address, nonce)[12:]
```
- `nonce` increments with each deployment
- Address is unpredictable (depends on how many contracts deployer has created)

**CREATE2 (deterministic deployment):**
```
address = keccak256(0xFF, deployer_address, salt, keccak256(init_code))[12:]
```
- Address is predictable BEFORE deployment
- Same inputs = same address on any chain
- Used by: Uniswap (pair addresses), Safe wallets, cross-chain deployments

**Why does the duplicate test revert?**
When you CREATE2 with the same salt AND same init code (same constructor args), it tries to deploy to an address that already has code. EVM reverts because you can't overwrite an existing contract.

**Interview questions:**
1. "How can you know a contract's address before deploying it?" — CREATE2. The address is a function of the deployer, salt, and init code hash. All known before deployment.
2. "How does Uniswap know the pair address without querying?" — They use CREATE2 in the factory. Given tokenA and tokenB, you can compute the pair address off-chain.
3. "Can you redeploy to the same CREATE2 address?" — Only if the contract was previously `selfdestruct`ed (deprecated in newer EVM versions). Otherwise, no.

### Day 6-7: View Functions & Gas Optimization

**View functions are free to call (no gas) when called externally.** They only read state.

Study `getTokensPaginated`:
```solidity
function getTokensPaginated(uint256 offset, uint256 limit)
    external view returns (address[] memory tokens, uint256 total)
```
- Returns a subset of the array (pagination)
- `memory` keyword: array exists only during this call, not stored permanently
- This pattern is essential for frontends — you can't load 10,000 tokens at once

**Gas optimization patterns in the code:**
1. `unchecked { }` — skips overflow checks when we've already validated. Saves ~20 gas per operation.
2. Custom errors — 4-byte selector vs full string storage.
3. `calldata` vs `memory` for function params — calldata is cheaper (read-only, no copy).
4. Checking `type(uint256).max` before subtracting allowance — skips an SSTORE for infinite approvals.

---

## Week 3: Testing with Foundry (via test files)

### Day 1-3: Test Patterns

Open `test/Token.t.sol`. Every test follows this pattern:

```solidity
function test_WhatItTests_ExpectedBehavior() public {
    // 1. ARRANGE — set up the scenario
    // 2. ACT — call the function
    // 3. ASSERT — verify the result
}
```

**Key Foundry cheatcodes:**
- `vm.prank(addr)` — next call comes from `addr`
- `vm.startPrank(addr)` / `vm.stopPrank()` — multiple calls from `addr`
- `vm.expectRevert(selector)` — next call MUST revert with this error
- `vm.expectEmit(topic1, topic2, topic3, data)` — next event must match
- `vm.deal(addr, amount)` — give ETH to an address
- `makeAddr("label")` — create a labeled address for readable test output
- `bound(x, min, max)` — constrain fuzz input to a range

### Day 4-5: Fuzz Testing

```solidity
function testFuzz_Transfer_NeverExceedsBalance(uint256 amount) public {
    amount = bound(amount, 0, INITIAL_SUPPLY_WEI);
    vm.prank(deployer);
    token.transfer(alice, amount);
    assertEq(token.balanceOf(deployer) + token.balanceOf(alice), token.totalSupply());
}
```

Foundry generates 1000 random values for `amount` and checks the invariant holds for all of them. This catches edge cases you'd never think to test manually.

**Interview questions:**
1. "How do you test smart contracts?" — Foundry. Write Solidity tests, use cheatcodes for state manipulation, fuzz testing for edge cases, invariant testing for protocol-wide properties.
2. "What's the difference between unit tests and fuzz tests?" — Unit tests use specific values you choose. Fuzz tests let the framework generate random values to find edge cases you didn't think of.
3. "What's an invariant test?" — A property that must ALWAYS be true, checked across many random sequences of actions. Example: "sum of all balances == totalSupply" must hold after any combination of transfers/mints/burns.

### Day 6-7: Running & Reading Tests

Practice these commands until they're muscle memory:

```bash
# Run all tests
forge test -vvv

# Run one specific test
forge test --match-test test_Transfer_MovesTokens -vvv

# Run all tests in one file
forge test --match-path test/Token.t.sol -vvv

# Run with gas report
forge test --gas-report

# Run fuzz tests with more iterations (CI mode)
FOUNDRY_PROFILE=ci forge test
```

`-v` verbosity levels:
- `-v` = show test names + pass/fail
- `-vv` = also show logs (console2.log)
- `-vvv` = also show execution traces for failing tests
- `-vvvv` = show traces for ALL tests
- `-vvvvv` = show everything including setup

---

## Top 20 Interview Questions (with answers)

1. **What is ERC-20?** — A standard interface for fungible tokens. Any contract implementing transfer, approve, transferFrom, balanceOf, totalSupply, and allowance is ERC-20 compliant.

2. **How does a DEX move your tokens?** — You approve the DEX contract to spend your tokens. The DEX calls transferFrom to pull them during a swap.

3. **What's the approve front-running attack?** — If changing approval from 100→50, attacker can spend 100 before your tx, then 50 after = 150 total. Fix: set to 0 first, or use increaseAllowance.

4. **CREATE vs CREATE2?** — CREATE uses deployer+nonce (unpredictable). CREATE2 uses deployer+salt+bytecodeHash (deterministic, predictable before deployment).

5. **Why 18 decimals?** — Convention from ETH. Solidity has no floats, so 1 token = 1e18 smallest units.

6. **What are events used for?** — Logging. Cheap on-chain storage that frontends and indexers (The Graph) can subscribe to and query.

7. **What's a factory pattern?** — A contract that deploys other contracts. Ensures standardization, provides a registry, and simplifies UX.

8. **What does `unchecked` do?** — Disables overflow/underflow checks. Saves ~20 gas per operation. Only safe when you've already validated the math.

9. **What's a mapping?** — A hash table. O(1) read/write. Cannot be iterated. Keys that haven't been set return the default value (0, false, address(0)).

10. **How do you test Solidity?** — Foundry: write tests in Solidity, use vm cheatcodes, run fuzz tests with random inputs, check gas costs.

11. **What's msg.sender?** — The address that called the current function. For external calls, it's the user's wallet. For internal contract-to-contract calls, it's the calling contract.

12. **What's the difference between memory and storage?** — Storage is permanent (on-chain, expensive). Memory is temporary (exists during function call, cheap).

13. **What's calldata?** — Read-only function parameter location. Cheaper than memory because no copy is made.

14. **Why use custom errors over require strings?** — Gas savings. Error selectors are 4 bytes vs full string storage and return.

15. **What's type(uint256).max?** — The maximum value: 2^256 - 1. Used for infinite approvals to skip allowance updates.

16. **What's vm.prank in Foundry?** — Cheatcode that makes the next call come from a specified address. Essential for testing access control.

17. **What's fuzz testing?** — The framework generates random inputs and checks that invariants hold. Finds edge cases humans miss.

18. **How do you deploy to testnet?** — forge script with --rpc-url and --broadcast flags. Script files use vm.startBroadcast() to mark real transactions.

19. **What's contract verification?** — Publishing source code on a block explorer (Etherscan) so anyone can read and audit it. Use --verify flag with forge script.

20. **What's the difference between external and public?** — Both callable from outside. Public can also be called internally (costs more gas). External can use calldata directly (cheaper).

---

## Study Schedule

| Day | Topic | Time |
|-----|-------|------|
| 1 | Read Token.sol top to bottom. Annotate what you don't understand. | 1-2 hrs |
| 2 | Study state variables, mappings, events. Write them from memory. | 1-2 hrs |
| 3 | Study transfer/approve/transferFrom. Diagram the flow on paper. | 2 hrs |
| 4 | Study mint/burn/ownership. Understand access control. | 1 hr |
| 5 | Read TokenFactory.sol. Understand CREATE2 and the factory pattern. | 2 hrs |
| 6 | Study predictTokenAddress. Try computing an address on paper. | 1 hr |
| 7 | Read Token.t.sol. Understand each test and what it's checking. | 2 hrs |
| 8 | Read TokenFactory.t.sol. Understand factory-specific tests. | 1-2 hrs |
| 9 | Run all tests. Break a contract on purpose, see which tests catch it. | 2 hrs |
| 10 | Write 3 new tests yourself for edge cases you think of. | 2 hrs |
| 11 | Study the deployment script. Understand forge script workflow. | 1 hr |
| 12 | Deploy to Base Sepolia testnet. Verify on Basescan. | 1-2 hrs |
| 13 | Create a token via the factory on testnet. Interact via Basescan. | 1-2 hrs |
| 14 | Answer all 20 interview questions out loud without looking. | 1-2 hrs |

After 2 weeks, you should be able to explain every line of this code confidently.
