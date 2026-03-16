---
name: skill-hygiene
description: >
  Style guide and refactoring discipline for the instruction set itself — skills,
  agents, CLAUDE.md, and commands. Load when creating new skills, incorporating
  external ideas, or when the instruction set feels bloated, duplicated, or
  inconsistent. Also load after config-scout comparisons to ensure adopted
  content integrates cleanly.
---

# Skill Hygiene

Principles for maintaining a coherent, lean instruction set. Skills and agent
definitions are a codebase of natural language — they accumulate debt, duplicate
ideas, and drift just like code. This skill applies the same discipline we use
for code to the instructions themselves.

**Core principle: The context window is a public good.** Every token in a skill
competes with conversation history, other skills, and the user's actual request.
Earn each token's place.

---

## When to Trigger

Load this skill when any of these conditions are met:

- **Creating a new skill or agent** — before writing, check for overlap
- **After a config-scout comparison** — before adopting external ideas, verify
  they don't duplicate what exists
- **After 3+ skills have been added or modified** — periodic hygiene check
- **When a skill exceeds 300 lines** — assess whether it should split
- **When you notice the same principle stated in multiple places** — deduplicate
- **When an agent or skill feels "off"** — vague, verbose, or hard to follow
- **During refactoring of the instruction set itself**

---

## Token Budgeting

Guidelines adapted from [Anthropic's skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):

- **CLAUDE.md**: Under 200 lines. Always loaded — every token costs on every
  conversation. Only principles that apply universally belong here.
- **Skills**: Under 500 lines per SKILL.md. Split to reference files if larger.
- **Agents**: Under 400 lines. Agents carry their full definition in context
  when active.
- **Commands**: No hard limit, but the command runs once — front-load the
  critical instructions.

**Challenge each piece**: "Does Claude really need this explanation? Can I assume
Claude already knows this? Does this paragraph justify its token cost?"

**Default assumption**: Claude is already very smart. Only add context Claude
does not already have. Do not explain what TDD is — state the rules for how we
practice it.

---

## Deduplication Rules

The same principle should be stated **once**, in the most authoritative location,
and referenced everywhere else.

### Authority hierarchy

1. **CLAUDE.md** — universal principles (TDD is non-negotiable, type safety, etc.)
2. **Skills** — detailed patterns for a specific domain (testing-anti-patterns,
   systematic-debugging)
3. **Agents** — operational behavior for a specific role (tdd-guardian enforcement
   process, pr-reviewer categories)
4. **Commands** — workflow steps for a specific action (/pr, /config-scout)

### Deduplication protocol

When the same idea appears in multiple files:

1. Identify which level in the hierarchy is the **authoritative source**
2. Keep the full statement there
3. Replace other occurrences with a cross-reference:
   "See CLAUDE.md Development Workflow" or "See testing-anti-patterns skill"
4. Exception: agents may restate a principle in operational terms if the
   restatement adds enforcement-specific value (e.g., tdd-guardian's
   rationalizations list adds agent-specific coaching responses)

### Smell test

If you grep for a phrase and find it in 3+ files, it's duplicated. Either
consolidate or add explicit cross-references.

---

## When to Split vs Merge

### Split when:

- A skill covers two unrelated domains (split by domain)
- A skill exceeds 500 lines (split to reference files)
- Users would invoke one half without the other
- Different agents need different subsets of the content

### Merge when:

- Two skills are always loaded together
- One skill is a "leaf" that only makes sense in the context of another
- Two skills overlap by more than 50% of their content

### Never split:

- To match a 1:1 mapping with external sources ("they had 5 skills so we need 5")
- Prematurely — wait until the skill is actually too large or serves two audiences

---

## TDD for Skills

Adapted from obra/superpowers' `writing-skills` pattern and
[Anthropic's evaluation-driven development](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):

### RED: Establish the baseline failure

Before writing a new skill, observe how the agent fails without it:

1. Run Claude on a representative task in the skill's domain
2. Document specific failures, missed context, or wrong approaches
3. These failures are your "failing tests" — the skill must address them

### GREEN: Write the minimum skill

Write only enough instruction to fix the observed failures:

- Do not anticipate problems you haven't seen
- Do not add explanations Claude doesn't need
- Do not add sections "for completeness"

### REFACTOR: Observe and tighten

Use the skill in real work, then refine:

1. **Observe** — where does Claude ignore, misapply, or over-apply the skill?
2. **Tighten** — add guardrails for observed misapplication
3. **Trim** — remove instructions Claude consistently handles without guidance
4. **Repeat** — each cycle should make the skill shorter and sharper

### The two-Claude pattern

- **Claude A** (skill author): helps you design and refine the skill
- **Claude B** (skill user): tests the skill on real tasks in a fresh session
- Observations from Claude B feed back to Claude A for refinement

---

## Incorporating External Ideas

When config-scout identifies something worth adopting:

1. **Check for existing coverage** — grep the instruction set for related terms.
   The idea may already be partially covered.
2. **Find the right home** — use the authority hierarchy to place it at the
   correct level (CLAUDE.md, skill, agent, or command).
3. **Adapt the phrasing** — external configs have their own voice. Rewrite to
   match our tone: strict but constructive, concise, principle-first.
4. **Add provenance** — in the commit message, include `Source: <url>` so
   git blame traces the idea's origin.
5. **Check for contradiction** — does the new idea conflict with existing
   principles? If so, make an explicit choice and document why in DECISIONS.md.
6. **Verify token budget** — after adding, check the file's line count. Did it
   push past the budget? If so, split or trim.

---

## Consistency Checklist

Run this when the instruction set has been modified:

- [ ] **No orphan principles** — every principle in a skill/agent traces back
      to a CLAUDE.md core value (TDD, types, functional, immutable)
- [ ] **No contradictions** — skills don't disagree with each other or CLAUDE.md
- [ ] **No stale references** — cross-references point to files that exist
- [ ] **No bloated files** — CLAUDE.md under 200 lines, skills under 500,
      agents under 400
- [ ] **No unearned tokens** — each section justifies its presence
- [ ] **Consistent terminology** — same concept uses same term everywhere
      (e.g., always "skill" not sometimes "plugin" or "module")
- [ ] **Descriptions are discoverable** — skill/agent descriptions say what
      it does AND when to trigger it, in third person
- [ ] **Naming convention** — skills use gerund or noun form, kebab-case

---

## Refactoring the Instruction Set

Same triggers as code refactoring. After any "green" change (new skill works,
adopted idea integrates cleanly), assess:

- **Extract**: A principle repeated in 3 agents → move to CLAUDE.md, reference from agents
- **Inline**: A skill that's only 20 lines and always loaded with another → merge
- **Rename**: A skill name that doesn't match what it actually does → rename
- **Delete**: A skill that hasn't been triggered in months → remove or archive
- **Reorganize**: Authority hierarchy violated (detailed pattern in CLAUDE.md,
  summary in skill) → swap levels

Apply the same "commit separately, explain why" discipline as code refactoring.
