$ErrorActionPreference = 'Stop'
$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$BackupPath = (Get-ChildItem -LiteralPath 'C:\Users\micha\Documents\WindowsPowerShell' -Filter 'Microsoft.PowerShell_profile.ps1.allstart2-silent-launchers-*.bak' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
function Get-ProfileFunctionNames([string]$Path){
  $tokens=$null; $errors=$null
  $ast=[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if($errors.Count -gt 0){ throw "parse errors in $Path = $($errors.Count)" }
  return @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
}
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$tokens,[ref]$errors)
if($errors.Count -gt 0){ throw "PROFILE_PARSE_ERRORS=$($errors.Count)" }
$before=@(Get-ProfileFunctionNames $BackupPath)
$after=@(Get-ProfileFunctionNames $ProfilePath)
$missing=@()
$beforeGroups=$before | Group-Object
$afterGroups=$after | Group-Object
foreach($g in $beforeGroups){
  $m=@($afterGroups | Where-Object { $_.Name -eq $g.Name })
  $afterCount=if($m.Count){$m[0].Count}else{0}
  if($afterCount -lt $g.Count){ $missing += ("{0} before={1} after={2}" -f $g.Name,$g.Count,$afterCount) }
}
if($missing.Count -gt 0){ throw ('MISSING_FUNCTIONS=' + ($missing -join '; ')) }
. $ProfilePath
$self = @(allstart2 -SelfTest)
$scriptObj = @($self | Where-Object { $_.PSObject.Properties.Name -contains 'Script' } | Select-Object -First 1)
if(-not $scriptObj -or $scriptObj[0].Script -notlike '*allstart2-silent-launchers-20260604*'){ throw ('SelfTest did not bind to new project script: ' + ($self | Out-String)) }
allstart2 -Mode Verify -DryRun | Out-Null
allstart2 -Mode Startup | Out-Null
$expected = @{
  'OpenSpeedy_Tray' = 'allstart2-silent-launchers-20260604\openspeedy-silent\openspeedy-silent.vbs'
  'Murmure_Tray' = 'allstart2-silent-launchers-20260604\murmure-silent\murmure-silent.vbs'
  'CustomStartup_docker_7154a782' = 'allstart2-silent-launchers-20260604\trayquiet-start\trayquiet-start.vbs'
}
foreach($name in $expected.Keys){
  $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
  $actionText = (@($task.Actions | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' ')
  if($actionText -notlike ('*' + $expected[$name] + '*')){ throw "Task $name not updated: $actionText" }
  if($actionText -match [regex]::Escape('C:\Users\micha\.claude\scripts')){ throw "Task $name still references old C-drive scripts: $actionText" }
}
'BACKUP=' + $BackupPath
'PROFILE_PARSE=0'
'DOT_SOURCE=OK'
'ALLSTART2_SELFTEST=OK'
'ALLSTART2_VERIFY_DRYRUN=OK'
'ALLSTART2_STARTUP=OK'
'FUNCTION_COUNT_BEFORE=' + $before.Count
'FUNCTION_COUNT_AFTER=' + $after.Count
'UNRELATED_FUNCTIONS_DELETED=0'
'TASK_ACTIONS_UPDATED=OK'
