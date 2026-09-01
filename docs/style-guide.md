# Style guide

This guide states the writing rules for `README.md`, `AGENT.md`, and every
file under `docs/`. The automated check is `bun tools/doc-style/check.ts`;
run it before submitting document changes.

## Vocabulary

Use plain professional vocabulary and direct verbs. Prefer `fix`, `write`,
`read`, `hold`, and `check` in their literal senses. When a sentence needs
a technical term, use the established term for that domain.

The checker bans five word categories; the full lists with category
comments live in `tools/doc-style/check.ts`:

- Metaphor verbs used as technical terms. A verb that pictures code as a
  physical object being forced into place states no fact about the code.
  Replace it with the plain verb that names the operation.
- Internet jargon and business-speak vocabulary.
- Coined compression compounds. State the scope with a preposition or a
  full phrase when the compound word has no established meaning.
- Putdown wording that talks down to the reader without adding information.
- Decorative adjectives and vague quantifiers. Numbers and measurements
  replace them.

## Sentence patterns

- No negate-first contrast constructions. State the fact that holds, then
  stop. When two facts differ, give each its own sentence with its own
  verb.
- No em-dashes. Use a period, a comma, or parentheses.
- No filler transitions that restate the previous sentence. Every sentence
  adds information or gets deleted.

## Word list growth

When a review corrects a wording problem, add the new word or pattern to
the checker in the same change. The list is incomplete by design; it grows
with each correction.

## Manual judgment

Every hit from the checker is a candidate for manual judgment:

1. A hit that violates the rules gets rewritten.
2. A fixed phrase that is correct in context, including established
   technical terms, gets an allowlist entry after explicit permission from
   the repository owner.
3. The allowlist is locked: expanding it without permission is forbidden.

The checker is an automated checklist. Reading the final text before
submitting remains required.
