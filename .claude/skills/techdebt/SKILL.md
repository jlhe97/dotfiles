---
name: techdebt
description: This skill should be used when the user asks to "find tech debt", "clean up code", "find duplicated code", "reduce duplication", or wants to run end-of-session cleanup.
---

# Tech Debt Hunter

Find and eliminate duplicated code, dead code, and technical debt in the codebase.

## Process

1. Scan the codebase for:
   - Duplicated code blocks (3+ lines appearing in multiple places)
   - Dead code (unused functions, variables, imports)
   - TODO/FIXME comments that have been lingering
   - Inconsistent patterns (same thing done different ways)
   - Overly complex functions that could be simplified

2. For each finding, report:
   - Location (file:line)
   - Type of debt (duplication, dead code, complexity, inconsistency)
   - Severity (high/medium/low)
   - Suggested fix

3. Prioritize by impact - focus on:
   - Code that's actively being worked on
   - Duplication that's causing bugs or confusion
   - Dead code that's cluttering the codebase

## Output Format

```
## Tech Debt Report

### High Priority
- [DUPLICATION] `src/utils/format.ts:45` and `src/helpers/string.ts:12` - identical date formatting logic
  → Extract to shared utility

### Medium Priority
- [DEAD CODE] `src/old/legacy.ts` - entire file unused since removal of feature X
  → Safe to delete

### Low Priority
- [TODO] `src/api/client.ts:89` - "TODO: add retry logic" (6 months old)
  → Implement or remove
```

## Rules

- Only report actionable items
- Verify code is actually unused before flagging as dead
- Group related duplications together
- Suggest specific refactoring approaches
- Ask before making changes
