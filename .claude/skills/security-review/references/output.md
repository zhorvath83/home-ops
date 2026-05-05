# Output

Use this structure for security review responses:

1. Finding Title
2. Severity
3. Evidence
4. Impact
5. Detection Gap
6. Affected Components
7. Remediation

## Rules

- avoid generic "could be insecure" language when the repo evidence is weak
- say explicitly when no concrete finding is present
- when multiple findings exist, rank them by practical impact
- prefer one clear remediation path per finding unless there is a meaningful tradeoff
