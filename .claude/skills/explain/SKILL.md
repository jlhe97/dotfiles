---
name: explain
description: This skill should be used when the user asks to "explain this code", "help me understand", "create a diagram", "visualize the architecture", or needs to learn how unfamiliar code works.
---

# Code Explainer

Generate clear visual explanations of code, architecture, and systems.

## Available Formats

### 1. ASCII Diagrams
For terminal-friendly architecture visualization:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│   Server    │────▶│  Database   │
└─────────────┘     └─────────────┘     └─────────────┘
```

### 2. HTML Presentation
Generate a standalone HTML file with:
- Syntax-highlighted code snippets
- Step-by-step walkthrough
- Interactive navigation
- Dark mode support

### 3. Markdown Documentation
Structured explanation with:
- Overview section
- Key concepts
- Code flow diagrams (mermaid)
- Examples

## Process

1. Identify what needs explaining:
   - Single function/class
   - Module or feature
   - System architecture
   - Data flow

2. Determine the audience level:
   - New to codebase
   - Familiar but need refresher
   - Deep dive for debugging

3. Choose appropriate format based on complexity

4. Generate explanation with:
   - High-level overview first
   - Progressive detail
   - Concrete examples
   - Common pitfalls

## Usage

```
/explain src/auth/oauth.ts
/explain "how does the payment flow work"
/explain --format=html src/core/
/explain --format=ascii "database schema"
```

## Rules

- Start with the "why" before the "how"
- Use analogies for complex concepts
- Include relevant code snippets
- Highlight non-obvious behavior
- Note any gotchas or edge cases
