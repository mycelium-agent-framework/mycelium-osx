---
name: systematic-debugging
description: >
  Framework for systematic root-cause debugging. Load when investigating
  failures, flaky tests, CI-only breakage, or production incidents. Prevents
  guess-and-check troubleshooting. Pairs with tdd-guardian for the fix phase.
---

# Systematic Debugging

**Core principle: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

Systematic debugging is faster than guess-and-check troubleshooting, even under
time pressure. Resist the urge to "just try something."

---

## Phase 1: Root Cause Investigation

Before touching any code, gather evidence:

1. **Read the error thoroughly** — full stack trace, not just the last line
2. **Reproduce reliably** — if you cannot reproduce it, you cannot verify a fix
3. **Review recent changes** — `git log --oneline -10`, `git diff HEAD~3`
4. **Gather diagnostic evidence** — logs, exit codes, environment state
5. **For multi-component systems** — instrument each boundary to isolate where
   the failure occurs (add temporary logging at port/adapter boundaries, check
   input/output at each layer)

**Do not proceed to Phase 2 until you can reliably reproduce the issue.**

---

## Phase 1.5: Verify the Test Itself

Before investigating production code, rule out the test as the source of the
problem:

- Is a mock returning data the real dependency wouldn't?
- Is test setup incomplete or stale?
- Is the test asserting on mock behavior rather than real behavior?
- Did a shared fixture mutate between tests?

Cross-reference the `testing-anti-patterns` skill. If the bug is in the test
setup, fix the test — do not "fix" production code to match a broken test.

---

## Phase 2: Pattern Analysis

Find a working reference point and compare:

1. **Locate working examples** — similar code that works, a previous commit
   where this worked, another environment where it passes
2. **Compare completely** — diff the working state against the broken state
3. **Identify differences** — focus on what changed, not what looks suspicious
4. **Understand dependencies** — trace imports, configs, environment variables

---

## Phase 3: Hypothesis and Testing

1. **Form a specific hypothesis** — "The failure occurs because X changed,
   which causes Y at this boundary"
2. **Test with ONE change** — change a single variable and observe
3. **Verify the result** — did the change confirm or refute the hypothesis?
4. **If refuted** — return to Phase 2 with new information, do not guess again

**One change at a time.** If you change two things and the bug disappears, you
do not know which change fixed it.

---

## Phase 4: Fix via TDD

Once root cause is identified, return to normal TDD:

1. Write a failing test that reproduces the bug
2. Watch it fail (confirms you captured the right behavior)
3. Implement the fix — minimum change to make the test pass
4. Verify all other tests still pass

Hand off to the tdd-guardian at this point. The debugging skill's job is done
once root cause is established and a reproducing test exists.

---

## Guardrails

- **No fixes before investigation** — typing code before understanding the
  problem creates new problems
- **One change at a time** — isolate variables or you learn nothing
- **3-strike rule** — if three fix attempts fail, stop. Return to Phase 1 and
  question your assumptions about root cause. If still stuck after a second
  round, pause and discuss architecture with the user.
- **Fresh evidence only** — "it worked before" is not evidence. Run the proving
  command now. (See: "No completion claims without fresh evidence" in CLAUDE.md.)

---

## Common Debugging Scenarios

**"Works locally, fails in CI":**
- Check environment differences (OS, Python version, dependency versions)
- Check for implicit ordering dependencies (filesystem order, dict order)
- Check for timing dependencies (async, network, file locks)
- Check for missing test isolation (shared state, temp files, ports)

**"Flaky test — passes sometimes":**
- Look for shared mutable state between tests
- Look for time-dependent logic (timestamps, timeouts)
- Look for ordering dependencies (`pytest -p no:randomly` to check)
- Look for resource contention (ports, files, database connections)

**"Regression — this used to work":**
- `git bisect` to find the breaking commit
- Read the breaking commit's diff carefully before hypothesizing
- The fix is usually a revert or a targeted correction to the breaking change
