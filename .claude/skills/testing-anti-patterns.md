---
name: testing-anti-patterns
description: >
  Reference for testing anti-patterns and how to fix them. Load when writing or
  changing tests, adding mocks, or tempted to add test-only methods to production
  code. Covers mock misuse, test pollution, incomplete test doubles, and the gate
  functions for each. Pairs with the tdd-guardian agent.
---

# Testing Anti-Patterns

Tests must verify real behavior, not mock behavior. Mocks are a means to isolate, not the thing being tested.

**Core principle:** Test what the code does, not what the mocks do.

**Following strict TDD prevents most of these anti-patterns.** If you wrote the test first and watched it fail against real code, you wouldn't end up asserting on mock elements.

## The Iron Laws

1. NEVER test mock behavior
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding the dependencies

---

## Anti-Pattern 1: Testing Mock Behavior

**The violation:**
```python
# BAD: asserting the mock exists, not that the component works
def test_sends_notification():
    with mock.patch("notifications.send") as mock_send:
        process_order(order)
        mock_send.assert_called_once()  # proves mock was hit, nothing else
```

**Why this is wrong:**
- You're verifying the mock was invoked, not that the behavior is correct
- The test passes even if the call arguments are wrong
- Tells you nothing about what the user actually experiences

**The fix:**
```python
# GOOD: test the observable outcome
def test_sends_notification_to_correct_email():
    """Order processing notifies the customer's email address."""
    order = make_order(customer_email="alice@example.com")
    sent = []

    with mock.patch("notifications.send", side_effect=lambda **kw: sent.append(kw)):
        process_order(order)

    assert len(sent) == 1
    assert sent[0]["to"] == "alice@example.com"
```

### Gate Function

```
BEFORE asserting on a mock:
  Ask: "Am I testing real behavior or just that the mock was invoked?"

  IF testing mock invocation only:
    STOP — assert on the observable outcome instead
    (return value, state change, side effect on a real object)
```

---

## Anti-Pattern 2: Test-Only Methods in Production Classes

**The violation:**
```python
# BAD: reset() is only ever called from tests
class NodeCache:
    def reset(self) -> None:
        """Clear internal state."""  # looks like production API — it isn't
        self._cache.clear()
        self._index = {}

# in tests
@pytest.fixture(autouse=True)
def clean_cache(cache):
    yield
    cache.reset()
```

**Why this is wrong:**
- Production class polluted with test-only code
- Creates confusion about the real API surface
- Dangerous if accidentally called in production
- Violates YAGNI

**The fix:**
```python
# GOOD: test utilities handle test cleanup; cache has no reset()
# in tests/helpers.py
def make_fresh_cache() -> NodeCache:
    """Return a new, empty NodeCache for test isolation."""
    return NodeCache()

# in tests
def test_cache_miss_returns_none():
    cache = make_fresh_cache()
    assert cache.get("missing_id") is None
```

### Gate Function

```
BEFORE adding any method to a production class:
  Ask: "Is this method only called from test files?"

  IF yes:
    STOP — don't add it to the production class
    Create a factory function or helper in tests/helpers.py instead

  Ask: "Does this class own this resource's lifecycle?"

  IF no:
    STOP — wrong class for this method
```

---

## Anti-Pattern 3: Mocking Without Understanding

**The violation:**
```python
# BAD: mock kills the side effect the test depends on
def test_rejects_duplicate_node():
    with mock.patch("alph.core.validate_pool") as mock_validate:
        # validate_pool also writes the lock file the duplicate check reads!
        add_node(pool, node_a)
        add_node(pool, node_a)  # should raise — but won't
```

**Why this is wrong:**
- The mocked method had a side effect the test silently depended on
- Test passes for the wrong reason, or fails with a confusing error
- "Mock everything that might be slow" is how you end up here

**The fix:**
```python
# GOOD: mock the genuinely external operation, preserve behavior under test
def test_rejects_duplicate_node(tmp_path):
    """Adding the same node twice raises DuplicateNodeError."""
    pool = init_pool(tmp_path)  # real pool, no mocking of core logic
    node = make_node(context="duplicate context")

    add_node(pool, node)

    with pytest.raises(DuplicateNodeError):
        add_node(pool, node)
```

### Gate Function

```
BEFORE mocking any method:
  STOP — don't mock yet.

  1. Ask: "What side effects does the real method have?"
  2. Ask: "Does this test depend on any of those side effects?"
  3. Run the test with the real implementation first.
     Observe what actually needs to happen.

  IF the test depends on a side effect of the method you want to mock:
    Mock at a lower level (the slow or external operation only)
    Preserve the side effect the test needs

  Red flags:
    "I'll mock this to be safe"
    "This might be slow, better mock it"
    Mocking without being able to explain the full dependency chain
```

---

## Anti-Pattern 4: Incomplete Mock Data

**The violation:**
```python
# BAD: partial mock — only the fields you think you need right now
mock_response = {
    "status": "ok",
    "node_id": "abc123def456"
    # missing: schema_version, creator, created_at — downstream code uses these
}
```

**Why this is wrong:**
- Partial mocks hide structural assumptions
- Downstream code may depend on fields you didn't include
- Tests pass but integration fails
- Gives false confidence about real behavior

**The fix:**
```python
# GOOD: mirror the real structure completely
# Use the actual dataclass/schema to build the mock, not a hand-rolled dict
def make_node_response(**overrides: Any) -> dict[str, Any]:
    """Build a complete node API response matching the real schema."""
    base = {
        "node_id": "abc123def456",
        "status": "ok",
        "schema_version": "1",
        "creator": "test@example.com",
        "created_at": "2026-01-01T00:00:00Z",
        "context": "test context",
        "type": "snapshot",
    }
    return {**base, **overrides}
```

**Our rule:** Use real schemas and types in tests, never redefine them. If the project has a dataclass or TypedDict, use it to construct test data — don't hand-roll parallel dicts.

### Gate Function

```
BEFORE creating a mock response dict:
  Ask: "What is the complete structure of the real response?"

  Actions:
    1. Find the actual dataclass, TypedDict, or Pydantic model
    2. Use it to construct the test value — don't hand-roll
    3. Include ALL fields, not just the ones the current test touches

  IF no schema exists:
    That's a type safety gap — fix the schema first, then write the test
```

---

## Anti-Pattern 5: Over-Complex Mocks

**Warning signs:**
- Mock setup is longer than the test logic
- You're mocking everything to make the test pass
- Mocks are missing methods the real component has
- Test breaks when the mock changes, not when behavior changes

**The diagnosis:** Over-complex mocks usually mean the test is at the wrong level. Integration tests with real components (in-memory fakes, tmp_path, real objects) are often simpler than elaborate mock setups and test more real behavior.

**Ask:** "Would a real in-memory implementation of this dependency be simpler than this mock?"

For persistence: use `tmp_path` with a real filesystem pool rather than mocking file I/O.
For external APIs: use a fake/stub server or recorded responses rather than mocking at the method level.

---

## How TDD Prevents These Anti-Patterns

| Anti-pattern | Why TDD prevents it |
|---|---|
| Testing mock behavior | Writing test first against real code forces you to test real behavior |
| Test-only methods in production | RED phase reveals the design; cleanup belongs in test helpers |
| Mocking without understanding | You run against real implementation first, so you see what the test needs |
| Incomplete mocks | You use real schemas from the start; the type system catches gaps |
| Over-complex mocks | Minimal implementation pressure keeps mocking scoped |

**If you're testing mock behavior, you violated TDD** — you added mocks before watching the test fail against real code.

---

## Quick Reference

| Violation | Fix |
|---|---|
| `mock_x.assert_called_once()` with no behavior check | Assert on the observable outcome |
| Method on production class only used in tests | Move to `tests/helpers.py` |
| Mocking a method whose side effect the test needs | Mock at a lower level, preserve the side effect |
| Hand-rolled partial response dicts | Use the real schema/dataclass to construct test data |
| Mock setup > test logic | Consider real in-memory objects or `tmp_path` |

## Red Flags

- Assertion checks for mock invocation with no outcome assertion
- Methods only called from test files
- Mock setup is >50% of test code
- You can't explain why a mock is needed
- Mocking "just to be safe"
- Test fails when mock changes, not when behavior changes
