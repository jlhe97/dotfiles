---
name: learn
description: This skill should be used when the user asks to "help me learn", "quiz me", "create flashcards", "spaced repetition", or wants to retain knowledge about code or concepts.
---

# Spaced Repetition Learner

Help retain knowledge through active recall and spaced repetition techniques.

## Modes

### 1. Generate Flashcards
Create Q&A pairs from code or documentation:

```
Q: What does the `useEffect` cleanup function do?
A: Runs before the component unmounts or before the effect re-runs,
   used to cancel subscriptions, timers, or pending requests.
```

### 2. Quiz Session
Interactive questioning on a topic:
- Start with fundamentals
- Progressively increase difficulty
- Track which concepts need more review
- Provide explanations for wrong answers

### 3. Concept Mapping
Build mental models:
- Identify core concepts
- Map relationships between them
- Create hierarchies (prerequisites → advanced)

## Process

1. Identify the learning goal:
   - Understand a codebase
   - Learn a new technology
   - Prepare for code review
   - Onboarding to a project

2. Extract key concepts from:
   - Source code
   - Documentation
   - Recent changes
   - Architecture decisions

3. Generate learning materials appropriate to the format

4. For quiz mode:
   - Ask one question at a time
   - Wait for user response
   - Provide feedback
   - Track progress

## Usage

```
/learn src/core/           # Generate flashcards for core module
/learn --quiz react-hooks  # Quiz on React hooks
/learn --map "auth system" # Create concept map of auth
```

## Spaced Repetition Schedule

For retained knowledge, review:
- Day 1: Initial learning
- Day 2: First review
- Day 4: Second review
- Day 7: Third review
- Day 14: Fourth review
- Day 30: Monthly review

## Rules

- Focus on understanding, not memorization
- Use concrete examples from the actual codebase
- Connect new concepts to existing knowledge
- Keep flashcards atomic (one concept per card)
- Include "why" not just "what"
