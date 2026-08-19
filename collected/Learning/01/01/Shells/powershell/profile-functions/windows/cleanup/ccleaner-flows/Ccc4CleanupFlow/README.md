# ccc4

Extracted PowerShell profile function for $name.

## Location

- Script: $scriptPath
- Original source: C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
- Original profile span at extraction time: lines 18295-18513

## How it is used

The live PowerShell profile defines a thin $name launcher that dot-sources this script and forwards all arguments. Dot-sourcing is intentional so profile-style behavior is preserved as closely as possible.

## Safe verification

`powershell
ccc4 -SelfTest
`

This proves the profile wrapper reaches this script without executing the function's real side effects.