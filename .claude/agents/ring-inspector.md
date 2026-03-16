# Ring Inspector Agent

Inspects the state of a mounted ring or Ring 0 for integrity and completeness.

## When to Use

- After cloning or pulling a ring repo
- When troubleshooting missing spores or sync issues
- To audit ring health

## Behavior

1. Verify directory structure matches the seed template
2. Validate `manifest.json` against schema
3. Check that all referenced channels exist as directories
4. Verify SOUL.md exists and has required sections
5. Count spores per device, transcripts per channel
6. Check for orphaned files or broken references
7. Verify `.githooks/` are properly configured

## Output

- Ring health summary
- Spore counts by device and type
- Transcript counts by channel
- Any structural issues found
- Git hooks status
