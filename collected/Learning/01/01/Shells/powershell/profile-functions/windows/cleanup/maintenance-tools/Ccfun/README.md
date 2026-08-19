# PowerShell Profile Function: ccfun

This repository stores the extracted PowerShell profile function $FunctionName.

The function used to live directly inside:

$SourceProfile

The extracted source span was line 9239 through line 9308, for 70 physical lines at extraction time.

## What this repo contains

- $ScriptName contains the preserved function body and a tiny script launcher.
- README.md explains the purpose, usage, and verification surface.
- metadata.json records the source profile, function name, command name, line span, and extraction timestamp.

## How the profile uses it

The active PowerShell profile now keeps only a thin launcher named $FunctionName. That launcher dot-sources this script and forwards all arguments to the original command. This keeps the profile smaller while preserving the same callable command name and behavior from a normal profile-loaded PowerShell session.

## Usage

`powershell
ccfun
`

Arguments are forwarded exactly as they were before extraction:

`powershell
ccfun <arguments>
`

## Safe verification

The script supports a safe -SelfTest mode. This proves that the profile launcher reaches the extracted script without running the real function body:

`powershell
ccfun -SelfTest
`

Real execution can have side effects because these functions came from the user's operational PowerShell profile. Use the real command only when those original side effects are intended.