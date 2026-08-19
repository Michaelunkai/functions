$ErrorActionPreference='SilentlyContinue'
$envPF=${env:ProgramFiles}; $envPF86=${env:ProgramFiles(x86)}; $pd=${env:ProgramData}; $la=${env:LOCALAPPDATA}; $ra=${env:APPDATA}
$paths = New-Object System.Collections.Generic.List[string]
@("$envPF\AMD\RyzenMaster","$envPF\AMD","$envPF\GIGABYTE","$envPF\GIGABYTE\Control Center","$envPF86\GIGABYTE","$pd\GIGABYTE","$pd\AMD","$la\GIGABYTE","$ra\GIGABYTE","C:\AMD") | % { [void]$paths.Add($_) }
$pathInfo = foreach($p in $paths){ if(Test-Path -LiteralPath $p){ $i=Get-Item -LiteralPath $p; [pscustomobject]@{Path=$i.FullName; Exists=$true; LastWrite=$i.LastWriteTime; ChildCount=@(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue).Count} } else { [pscustomobject]@{Path=$p; Exists=$false} } }
$roots=@("$envPF\GIGABYTE","$pd\GIGABYTE","$la\GIGABYTE","$ra\GIGABYTE","C:\Program Files\WindowsApps")
$hits=New-Object System.Collections.Generic.List[object]
foreach($r in $roots){ if(Test-Path -LiteralPath $r){ Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'Ryzen|AMD|GCC|Update|Package|Software|version|install|manifest|json|xml|db|ini|log|config' -or $_.Name -match 'Ryzen|AMD|Update|Package|Software|version|install|manifest|json|xml|db|ini|log|config' } | Select-Object -First 300 FullName,Length,LastWriteTime | ForEach-Object { [void]$hits.Add($_) } } }
[pscustomobject]@{ Paths=$pathInfo; Hits=$hits } | ConvertTo-Json -Depth 4
