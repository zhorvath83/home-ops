# Validation

Use this reference after editing Renovate config or inline annotations.

## Read-Back Checklist

Read together:

1. `.github/renovate.json5`
2. any touched file in `.github/renovate/`
3. the manifest or config file whose dependency tracking changed

## Consistency Checks

- verify the updated policy still matches the intended datasource, grouping, and auto-merge behavior
- verify inline annotations still sit on the correct field or resource
- verify imported fragment names in `.github/renovate.json5` still match the files on disk
- verify allowed-version and package-rule changes do not accidentally broaden scope beyond the intended packages

## Lightweight Validation

- read back the effective config path rather than editing one fragment in isolation
- if local tooling is available, use the smallest JSON or pre-commit validation already present in the repo

If validation cannot run, say whether the blocker is missing Renovate tooling, pre-commit, or network access.
