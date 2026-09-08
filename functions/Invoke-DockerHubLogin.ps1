[CmdletBinding()]
param([switch]$SelfTest)
if (-not ('DockerNativeContextV4' -as [type])) {
 Add-Type -TypeDefinition 'using System; using System.IO; using System.Text; using System.Runtime.InteropServices; public static class DockerNativeContextV4 { [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern uint GetFinalPathNameByHandle(IntPtr h,StringBuilder b,uint n,uint f); public static bool IsRedirected() { string p=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),".codex-docker-context-"+Guid.NewGuid().ToString("N")+".tmp"); using(var file=new FileStream(p,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.ReadWrite|FileShare.Delete,1,FileOptions.DeleteOnClose)) { var b=new StringBuilder(32768); if(GetFinalPathNameByHandle(file.SafeFileHandle.DangerousGetHandle(),b,32768,0)==0) throw new IOException("Cannot identify AppData write path"); return b.ToString().IndexOf("\\Packages\\",StringComparison.OrdinalIgnoreCase)>=0; } } }'
}
if ([DockerNativeContextV4]::IsRedirected()) {
 & 'F:\study\Platforms\windows\functions\Invoke-DockerNativeScript.ps1' -ScriptPath 'F:\study\Platforms\windows\functions\Invoke-DockerHubLogin.ps1' -Parameters $PSBoundParameters
 return
}

$ErrorActionPreference='Stop'
$cli='C:\Program Files\Docker\Docker\resources\bin\docker.exe'
$credentialPath=Join-Path $env:LOCALAPPDATA 'Codex\DockerCredentials\hub-token.dpapi'
if(-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
 $saved=Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\DockerCredentials\hub-token.dpapi'
 if(Test-Path -LiteralPath $saved -PathType Leaf) {
  $encrypted=[IO.File]::ReadAllText($saved).Trim()
  $check=$encrypted | ConvertTo-SecureString -ErrorAction Stop
  $check.Dispose()
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($credentialPath))
  [IO.File]::WriteAllText($credentialPath,$encrypted)
 }
}
if(-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)){throw "Docker Hub saved credential missing: $credentialPath"}
if(-not (Test-Path -LiteralPath $cli -PathType Leaf)){throw "Docker CLI missing: $cli"}
$secure=(Get-Content -LiteralPath $credentialPath -Raw).Trim() | ConvertTo-SecureString
if($SelfTest){Write-Output 'DLOG_SELFTEST_OK encrypted_credential_readable=true username=michadockermisha';return}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$cli
$info.EnvironmentVariables['PATH']=(Split-Path -Parent $cli)+';'+$env:PATH
$info.Arguments='login docker.io --username michadockermisha --password-stdin'
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$process=[Diagnostics.Process]::Start($info)
$outTask=$process.StandardOutput.ReadToEndAsync()
$errTask=$process.StandardError.ReadToEndAsync()
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {$process.StandardInput.WriteLine([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))}
finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$process.StandardInput.Close();$secure.Dispose()}
if(-not $process.WaitForExit(30000)){try{$process.Kill()}catch{};throw 'Docker Hub login exceeded 30 seconds'}
if($process.ExitCode -ne 0){throw ('Docker Hub login failed: '+$errTask.Result.Trim())}
Write-Output $outTask.Result.Trim()