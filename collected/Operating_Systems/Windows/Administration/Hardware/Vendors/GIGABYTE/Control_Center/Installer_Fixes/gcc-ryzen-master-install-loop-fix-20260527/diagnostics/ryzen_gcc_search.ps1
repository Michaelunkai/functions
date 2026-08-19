$ErrorActionPreference='SilentlyContinue'
$roots=@('C:\Program Files\GIGABYTE','C:\Program Files (x86)\GIGABYTE','C:\Program Files\WindowsApps\65d483df-b37e-4fcf-94de-8b795233db63_25.1.23.0_x64__1mmjbktjj1mkp')
$results=@()
foreach($r in $roots){
  if(Test-Path -LiteralPath $r){
    $files=Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 100MB -and $_.Extension -match '\.(txt|xml|json|ini|cfg|config|log|html|js|csv|db|dat|dll|exe)$' }
    foreach($f in $files){
      $m=Select-String -LiteralPath $f.FullName -Pattern 'Ryzen Master','RyzenMaster','AMDRyzen','3.0.0.4199' -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 3
      foreach($x in $m){ $results += [pscustomobject]@{Path=$x.Path; LineNumber=$x.LineNumber; Line=($x.Line -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]','').Trim()} }
      if($results.Count -ge 80){ break }
    }
  }
  if($results.Count -ge 80){ break }
}
$results | Select-Object -First 80 | ConvertTo-Json -Depth 4
