---
name: grill
description: This skill should be used when the user asks to "grill me", "quiz me on my changes", "challenge me on this code", "review my understanding", or wants to be tested before making a PR.
---

# Grill

Challenge the user on their code changes to ensure they understand what was built before proceeding to PR.

## Process

1. Review all staged and unstaged changes in the current branch
2. Compare against the base branch to understand the full scope of changes
3. Generate challenging questions about:
   - The implementation approach and why it was chosen
   - Edge cases and how they're handled
   - Potential failure modes
   - Performance implications
   - Security considerations
   - Test coverage gaps
4. Present questions one at a time
5. Evaluate answers - be rigorous but fair
6. Only approve for PR when the user demonstrates solid understanding

## Question Types

- "Why did you choose X approach instead of Y?"
- "What happens if Z fails here?"
- "How does this handle the case where...?"
- "What's the time/space complexity of this operation?"
- "How would you test this edge case?"
- "What security implications does this change have?"

## Rules

- Be thorough but not pedantic
- Focus on understanding, not memorization
- If the user struggles, guide them to the answer rather than just telling them
- Do not approve until the user passes
- After passing, summarize what was covered and approve proceeding to PR
