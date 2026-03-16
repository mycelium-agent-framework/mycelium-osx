# Development Guidelines for Claude

> **About this file (v3.0.0):** Lean version optimized for context efficiency. Core principles here; detailed patterns loaded on-demand via skills.
>
> **Architecture:**
> - **CLAUDE.md** (this file): Core philosophy + quick reference (~100 lines, always loaded)
> - **Skills**: Detailed patterns loaded on-demand (tdd, testing, mutation-testing, test-design-reviewer, typescript-strict, functional, refactoring, expectations, planning, front-end-testing, react-testing)
> - **Agents**: Specialized subprocesses for verification and analysis
>
> **Previous versions:**
> - v2.0.0: Modular with @docs/ imports (~3000+ lines always loaded)
> - v1.0.0: Single monolithic file (1,818 lines)

## Core Philosophy

**TEST-DRIVEN DEVELOPMENT IS NON-NEGOTIABLE.** Every single line of production code must be written in response to a failing test. No exceptions. This is not a suggestion or a preference - it is the fundamental practice that enables all other principles in this document.

I follow Test-Driven Development (TDD) with a strong emphasis on behavior-driven testing and functional programming principles. All work should be done in small, incremental changes that maintain a working state throughout development.

## Quick Reference

**Key Principles:**

- Write tests first (TDD)
- Test behavior, not implementation
- Strict type safety (no `any`, `typing.Any`, or `interface{}` without justification)
- Immutable data only
- Small, pure functions
- Use real schemas/types in tests, never redefine them

**Supported Languages:**

- **TypeScript**: Strict mode, Jest/Vitest, React Testing Library
- **Python**: Type hints with mypy, pytest, no mutable defaults
- **Go**: Strict compilation, table-driven tests, explicit errors

Choose the language that best fits the domain - TypeScript for web/frontend, Python for data/ML/scripting, Go for systems/performance.

## Testing Principles

**Core principle**: Test behavior, not implementation. 100% coverage through business behavior.

**Quick reference:**
- Write tests first (TDD non-negotiable)
- **Watch the test fail** — if you didn't see it fail, you don't know if it tests the right thing
- Test through public API exclusively
- Use factory functions for test data (no mutable setup in `beforeEach`/fixtures)
- Tests must document expected business behavior
- No 1:1 mapping between test files and implementation files

**Testing Tools by Language:**
- **TypeScript**: Jest, Vitest, React Testing Library
- **Python**: pytest (with fixtures for immutable setup), unittest
- **Go**: standard `testing` package, table-driven tests

For detailed testing patterns and examples, load the `testing` skill.
For verifying test effectiveness through mutation analysis, load the `mutation-testing` skill.

## Type Safety Guidelines

**Core principle**: Strict typing always. Schema-first at trust boundaries, types for internal logic.

**TypeScript:**
- No `any` types - use `unknown` if type truly unknown
- Prefer `type` over `interface` for data structures
- Define schemas first, derive types (Zod/Standard Schema)

**Python:**
- Always use type hints (PEP 484)
- No `typing.Any` - use `object` or `typing.Protocol` if needed
- Use Pydantic/dataclasses for schemas at boundaries
- Run mypy in strict mode

**Go:**
- No `interface{}` without clear justification - use generics (Go 1.18+)
- Explicit error handling (never ignore errors)
- Use struct tags for validation/serialization

For detailed TypeScript patterns, load the `typescript-strict` skill.
For Python type patterns, use built-in type system with runtime validation at boundaries.
For Go patterns, follow standard library conventions.

## Code Style

**Core principle**: Functional programming with immutable data. Self-documenting code.

**Quick reference:**
- No data mutation - immutable data structures only
- Pure functions wherever possible
- No nested if/else - use early returns or composition
- Prefer simple, self-documenting code. Comments explaining WHY (not WHAT) are welcome when needed. If WHAT needs explanation, the code may be too complex or clever.
- Prefer options objects/dicts over positional parameters
- Use functional patterns:
  - **TypeScript/Python**: `map`, `filter`, `reduce` over loops
  - **Go**: prefer explicit loops with clear intent, avoid mutation
  - **Python**: list comprehensions, generator expressions
  - **TypeScript**: avoid `for...in`, use `for...of` or array methods

For detailed patterns and examples, load the `functional` skill.

## Development Workflow

**Core principle**: RED-GREEN-REFACTOR in small, known-good increments. TDD is the fundamental practice.

**Quick reference:**
- RED: Write failing test first (NO production code without failing test)
- GREEN: Write MINIMUM code to pass test
- REFACTOR: Assess improvement opportunities (only refactor if adds value)
- **Wait for commit approval** before every commit
- Each increment leaves codebase in working state
- Capture learnings as they occur, merge at end
- **Bail on repeated failure**: If an approach fails twice, stop and reassess with the user before trying alternatives. Do not spin on a failing strategy.
- **No completion claims without fresh evidence**: Before asserting success, run the proving command, read complete output and exit code, confirm it supports the claim. Language like "should work" or "probably" without a fresh run is not acceptable. Confidence from a previous run does not count. Unverified claims are indistinguishable from hallucinations.

For detailed TDD workflow, load the `tdd` skill.
For refactoring methodology, load the `refactoring` skill.
For significant work, load the `planning` skill for three-document model (PLAN.md, WIP.md, LEARNINGS.md).

## External APIs

**Core principle**: Never guess or infer API endpoints, payload shapes, or field names. Always verify against a source of truth before writing any code.

**Required sources (in priority order):**
1. `docs/api/openapi.json` — check this first for any Cycode API work
2. Confirmed response samples from actually running a probe request
3. Official API documentation

**Rules:**
- If an endpoint or field name is not confirmed by one of the above, stop and ask — do not write code against it
- Do not write "likely follows this pattern" stubs — leave a TODO and get confirmation first
- For any new API integration: write a minimal probe script first, print the raw response, confirm field names before building logic on top of it
- Never trust field names inferred from other parts of the codebase or documentation that says "likely" or "expected"

## Working with Claude

**Core principle**: Think deeply, follow TDD strictly, capture learnings while context is fresh.

**Quick reference:**
- ALWAYS FOLLOW TDD - no production code without failing test
- Assess refactoring after every green (but only if adds value)
- Update CLAUDE.md when introducing meaningful changes
- Ask "What do I wish I'd known at the start?" after significant changes
- Document gotchas, patterns, decisions, edge cases while context is fresh

For detailed TDD workflow, load the `tdd` skill.
For refactoring methodology, load the `refactoring` skill.
For detailed guidance on expectations and documentation, load the `expectations` skill.

## Resources and References

**TypeScript:**
- [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/intro.html)
- [Testing Library Principles](https://testing-library.com/docs/guiding-principles)
- [Kent C. Dodds Testing JavaScript](https://testingjavascript.com/)

**Python:**
- [Python Type Hints (PEP 484)](https://peps.python.org/pep-0484/)
- [pytest Documentation](https://docs.pytest.org/)
- [Effective Python](https://effectivepython.com/)

**Go:**
- [Effective Go](https://go.dev/doc/effective_go)
- [Go Testing Package](https://pkg.go.dev/testing)
- [Go Code Review Comments](https://go.dev/wiki/CodeReviewComments)

## Summary

The key is to write clean, testable, functional code that evolves through small, safe increments. Every change should be driven by a test that describes the desired behavior, and the implementation should be the simplest thing that makes that test pass. When in doubt, favor simplicity and readability over cleverness.
