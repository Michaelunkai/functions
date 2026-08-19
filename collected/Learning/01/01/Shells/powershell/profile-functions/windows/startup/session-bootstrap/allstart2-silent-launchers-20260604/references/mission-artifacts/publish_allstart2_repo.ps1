$ErrorActionPreference = 'Stop'
$RepoWin = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\startup\session-bootstrap\allstart2-silent-launchers-20260604'
$Git = 'C:\Program Files\Git\cmd\git.exe'
$Gh = 'C:\Program Files\GitHub CLI\gh.exe'
Set-Location -LiteralPath $RepoWin
& $Git init
& $Git branch -M main
& $Git config user.name 'Hermes Agent'
& $Git config user.email 'hermes-agent@users.noreply.github.com'
& $Git add --all
& $Git commit -m 'Create allstart2 silent launcher repair project'
$repoName = Split-Path -Leaf $RepoWin
# Create public repo using Windows gh if missing.
$ErrorActionPreference = 'Continue'
$view = & $Gh repo view $repoName --json name,url,visibility 2>$null
$viewCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if($viewCode -ne 0){
  & $Gh repo create $repoName --public --source $RepoWin --remote origin --push
} else {
  if(-not (& $Git remote get-url origin 2>$null)) { & $Git remote add origin ((& $Gh repo view $repoName --json url --jq .url) + '.git') }
  & $Git push -u origin main
}
$info = & $Gh repo view $repoName --json name,url,visibility | ConvertFrom-Json
# Ensure public
if($info.visibility -ne 'PUBLIC'){
  & $Gh repo edit $info.name --visibility public --accept-visibility-change-consequences
  $info = & $Gh repo view $repoName --json name,url,visibility | ConvertFrom-Json
}
# Update README with repo URL if not present.
$readme = Join-Path $RepoWin 'README.md'
$text = Get-Content -LiteralPath $readme -Raw
if($text -notmatch [regex]::Escape($info.url)){
  $text = $text.TrimEnd() + "`r`n`r`n## Repository`r`n`r`n$($info.url)`r`n"
  Set-Content -LiteralPath $readme -Value $text -Encoding UTF8
  & $Git add README.md
  & $Git commit -m 'Document GitHub repository URL'
  & $Git push origin main
}
$local = (& $Git rev-parse main).Trim()
& $Git fetch origin main | Out-Null
$remote = (& $Git rev-parse origin/main).Trim()
$status = & $Git status --short --branch
[pscustomobject]@{RepoName=$repoName; Url=$info.url; Visibility=$info.visibility; LocalHead=$local; RemoteHead=$remote; HeadsMatch=($local -eq $remote); Status=($status -join "`n")} | ConvertTo-Json -Depth 4
