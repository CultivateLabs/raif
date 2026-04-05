Review the latest CI results for this branch and fix any failures.

1. Run `gh run list --branch $(git branch --show-current) --limit 1` to find the latest run
2. Run `gh run view <run-id> --log-failed` to get the failure logs
3. Analyze the failures and fix them
4. Run the relevant tests locally to verify the fix