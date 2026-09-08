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
$gmenuCommandRoot=Join-Path $env:USERPROFILE '.gmenu\Commands'
if(-not (Test-Path -LiteralPath $gmenuCommandRoot -PathType Container)) {
    [void][IO.Directory]::CreateDirectory($gmenuCommandRoot)
}
if(Test-Path -LiteralPath $gmenuCommandRoot) {
    foreach($gmenuCommand in Get-ChildItem -LiteralPath $gmenuCommandRoot -Filter 'g*.ps1' -File) {
        if($gmenuCommand.BaseName -notmatch '^g[a-zA-Z0-9]+$' -or $gmenuCommand.BaseName -eq 'gmenu') {continue}
        $gmenuDefinition=[scriptblock]::Create("& '"+$gmenuCommand.FullName.Replace("'","''")+"' @args")
        Set-Item -LiteralPath ('Function:\global:'+$gmenuCommand.BaseName) -Value $gmenuDefinition -Force
    }
}
