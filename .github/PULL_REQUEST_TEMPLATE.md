## Summary
What does this PR do? (1-3 bullet points)

## Test plan
- [ ] `pwsh test.ps1` passes (all 12 suites)
- [ ] `$PSNativeCommandUseErrorActionPreference = $false` in all new scripts
- [ ] No `ConvertTo-Json`/`ConvertFrom-Json` for critical data paths
- [ ] New features have corresponding tests
