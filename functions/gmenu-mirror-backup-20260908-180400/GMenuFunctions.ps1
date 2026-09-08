# Keep the command available even when a new shell starts before the F: drive is
# mounted.  The fallback is a byte-for-byte local copy refreshed with the
# canonical sources; the first existing candidate always wins.
$gmenuEntryCandidates=@(
    'F:\study\Platforms\windows\functions\gmenu.ps1',
    (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\GMenuFallback\gmenu.ps1'),
    (Join-Path $env:USERPROFILE 'bin\gmenu.ps1')
)
$gmenuEntry=$gmenuEntryCandidates | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -First 1
if(-not (Get-Command gmenu -CommandType Function -ErrorAction SilentlyContinue) -and $gmenuEntry) {
    $gmenuDefinition=[scriptblock]::Create("& '"+$gmenuEntry.Replace("'","''")+"' @args")
    Set-Item -LiteralPath 'Function:\global:gmenu' -Value $gmenuDefinition -Force
}

function Get-GMenuSavedCommandRoot {
    if([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {throw 'GMenu cannot resolve USERPROFILE.'}
    return (Join-Path $env:USERPROFILE '.gmenu\Commands')
}

function Test-GMenuGeneratedCommand([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)) {return $false}
    try {
        $reader=New-Object IO.StreamReader($Path,$false)
        try {$firstLine=$reader.ReadLine()}finally {$reader.Dispose()}
        return $firstLine -eq '# GMENU GENERATED RESTORE COMMAND - PRIVATE RECOVERY KEY INCLUDED. Do not publish this script.'
    } catch {return $false}
}

function Restore-GMenuSavedCommand([string]$Name,[string]$Destination) {
    $commandRoot=Get-GMenuSavedCommandRoot
    $stateRoot=Split-Path -Parent $commandRoot
    $backupRoot=Join-Path $stateRoot 'CommandBackups'
    $historyRoot=Join-Path $stateRoot ('CommandHistory\'+$Name)
    $candidates=New-Object 'Collections.Generic.List[string]'
    $backup=Join-Path $backupRoot ($Name+'.ps1')
    if(Test-GMenuGeneratedCommand $backup){$candidates.Add($backup)}
    if(Test-Path -LiteralPath $historyRoot -PathType Container) {
        foreach($history in Get-ChildItem -LiteralPath $historyRoot -Filter '*.ps1' -File -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
            if(Test-GMenuGeneratedCommand $history.FullName){$candidates.Add($history.FullName)}
        }
    }
    if(-not $candidates.Count){return $false}
    [void][IO.Directory]::CreateDirectory($commandRoot)
    foreach($candidate in $candidates) {
        $temporary=$Destination+'.repair-'+[guid]::NewGuid().ToString('N')+'.tmp'
        try {
            [IO.File]::Copy($candidate,$temporary,$true)
            Move-Item -LiteralPath $temporary -Destination $Destination -Force -ErrorAction Stop
            return $true
        } catch {
            if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
        }
    }
    return $false
}

function Invoke-GMenuSavedCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Position=1)][object[]]$Arguments=@()
    )
    if($Name -notmatch '^g[a-zA-Z0-9]+$' -or $Name -eq 'gmenu') {throw "Invalid GMenu command name: $Name"}
    $commandRoot=Get-GMenuSavedCommandRoot
    $stateRoot=Split-Path -Parent $commandRoot
    $commandPath=Join-Path $commandRoot ($Name+'.ps1')
    $valid=Test-GMenuGeneratedCommand $commandPath
    if(-not $valid) {$valid=Restore-GMenuSavedCommand $Name $commandPath}
    if(-not $valid) {
        $receipt=Join-Path $commandRoot ($Name+'.receipt.json')
        $sourceHint=$null
        if(Test-Path -LiteralPath $receipt -PathType Leaf) {
            try {$sourceHint=[string]((Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json).Source)}catch{}
        }
        $hint=if($sourceHint){" Re-run gmenu for the recorded source '$sourceHint' to recreate the protected command."}else{' Re-run gmenu for the application to recreate the protected command.'}
        if(Test-Path -LiteralPath $commandPath -PathType Leaf) {
            throw ("GMenu command '{0}' failed its generated-command integrity check and no protected backup is available under '{1}'.{2}" -f $Name,$stateRoot,$hint)
        }
        throw ("GMenu command '{0}' is registered but its restore script is missing and no protected backup is available under '{1}'.{2}" -f $Name,$stateRoot,$hint)
    }
    & $commandPath @Arguments
    $exitCode=$LASTEXITCODE
    if($null -ne $exitCode){$global:LASTEXITCODE=$exitCode}
}

function Set-GMenuSavedCommandFunction([string]$Name,[string]$CommandPath) {
    if($Name -notmatch '^g[a-zA-Z0-9]+$' -or $Name -eq 'gmenu'){return}
    $gmenuDefinition=[scriptblock]::Create(("Invoke-GMenuSavedCommand -Name '{0}' -Arguments `$args" -f $Name))
    Set-Item -LiteralPath ('Function:\global:'+$Name) -Value $gmenuDefinition -Force
}

$gmenuCommandRoot=Get-GMenuSavedCommandRoot
# Importing the profile helper must be read-only.  In particular, `uni gmenu`
# is allowed to remove this exact state tree; a later PowerShell startup must
# not recreate an empty recovery directory before the next cleanup can verify
# that it stayed gone.  Writers create the state root at the point they publish
# or restore a command.
$gmenuStateRoot=Split-Path -Parent $gmenuCommandRoot
$gmenuCommandRoots=@($gmenuCommandRoot,(Join-Path $gmenuStateRoot 'CommandBackups'))
foreach($gmenuRoot in $gmenuCommandRoots) {
    if(-not (Test-Path -LiteralPath $gmenuRoot -PathType Container)){continue}
    foreach($gmenuCommand in Get-ChildItem -LiteralPath $gmenuRoot -Filter 'g*.ps1' -File -Force -ErrorAction SilentlyContinue) {
        if($gmenuCommand.BaseName -notmatch '^g[a-zA-Z0-9]+$' -or $gmenuCommand.BaseName -eq 'gmenu'){continue}
        Set-GMenuSavedCommandFunction $gmenuCommand.BaseName $gmenuCommand.FullName
    }
}
