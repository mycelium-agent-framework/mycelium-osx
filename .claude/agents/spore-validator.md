# Spore Validator Agent

Validates mycelium spore and transcript JSONL files against the canonical JSON Schema.

## When to Use

- Before committing memory or transcript files
- After importing spores from another PoP
- When debugging memory integrity issues

## Behavior

1. Locate all `memory-*.jsonl` files in `.mycelium/`
2. Locate all `transcript-*.jsonl` files in `channels/*/`
3. Parse each line as JSON
4. Validate against the corresponding schema in `schemas/`
5. Report any validation errors with file path and line number

## Output

- List of validated files with line counts
- Any validation errors with details
- Summary: total files, total records, errors found
