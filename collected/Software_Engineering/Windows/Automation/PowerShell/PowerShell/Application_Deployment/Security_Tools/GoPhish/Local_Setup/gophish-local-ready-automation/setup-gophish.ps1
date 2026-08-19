[CmdletBinding()]
param(
    [string]$Root = "",
    [int]$AdminPort = 3333,
    [int]$PhishPort = 8080,
    [int]$MaxAttempts = 5,
    [switch]$NoOpen
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    Split-Path -Parent $PSCommandPath
} else {
    (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $ScriptRoot ".gophish-runtime"
}

$ReleaseVersion = "v0.12.1"
$AssetName = "gophish-v0.12.1-windows-64bit.zip"
$DownloadUrl = "https://github.com/gophish/gophish/releases/download/$ReleaseVersion/$AssetName"
$ExpectedSha256 = "e6936b8a472c730dcb0da64024d82341806869af666fad10f8639e7f85b1b7e6"

$Root = [System.IO.Path]::GetFullPath($Root)
$DownloadDir = Join-Path $Root "downloads"
$InstallDir = Join-Path $Root "gophish"
$LogsDir = Join-Path $Root "logs"
$StateDir = Join-Path $Root "state"
$ZipPath = Join-Path $DownloadDir $AssetName
$ExePath = Join-Path $InstallDir "gophish.exe"
$ConfigPath = Join-Path $InstallDir "config.json"
$VersionMarkerPath = Join-Path $StateDir "release-version.txt"
$PidPath = Join-Path $StateDir "gophish.pid"
$CredentialPath = Join-Path $StateDir "admin-credentials.txt"
$StatusPath = Join-Path $StateDir "setup-status.json"
$LogPath = Join-Path $LogsDir "gophish.stdout.log"
$ErrLogPath = Join-Path $LogsDir "gophish.stderr.log"
$BrowserAutomationDir = Join-Path $Root "browser-automation"
$BrowserProfileDir = Join-Path $Root "browser-profile"
$BrowserPidPath = Join-Path $StateDir "browser.pid"
$BrowserDebugPortPath = Join-Path $StateDir "browser-debug-port.txt"
$BrowserLoginHelperPath = Join-Path $BrowserAutomationDir "open-gophish-logged-in.js"
$BrowserLoginLogPath = Join-Path $LogsDir "browser-login.log"

function Write-Step {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Enable-LocalHttpsTrust {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if (-not ([System.Management.Automation.PSTypeName]"LocalTrustAllCertsPolicy").Type) {
            Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;

public class LocalTrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
        }
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object LocalTrustAllCertsPolicy
    }
}

function Invoke-LocalWebRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Method = "Get",
        [object]$Body = $null,
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession = $null,
        [int]$TimeoutSec = 10
    )

    $params = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = $TimeoutSec
        ErrorAction = "Stop"
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $params.UseBasicParsing = $true
    } else {
        $params.SkipCertificateCheck = $true
    }
    if ($null -ne $Body) {
        $params.Body = $Body
    }
    if ($null -ne $WebSession) {
        $params.WebSession = $WebSession
    }

    Invoke-WebRequest @params
}

function Invoke-LocalWebRequestAllowStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [int[]]$AllowedStatusCodes = @(200),
        [int]$TimeoutSec = 10
    )

    try {
        $response = Invoke-LocalWebRequest -Uri $Uri -TimeoutSec $TimeoutSec
        if ($AllowedStatusCodes -notcontains [int]$response.StatusCode) {
            throw "Unexpected HTTP status $([int]$response.StatusCode) from $Uri."
        }
        return
    } catch {
        $response = $_.Exception.Response
        if ($null -ne $response -and $AllowedStatusCodes -contains [int]$response.StatusCode) {
            return
        }
        throw
    }
}

function Get-Sha256 {
    param([string]$Path)

    $stream = $null
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            break
        } catch {
            if ($attempt -eq 30) {
                throw
            }
            Start-Sleep -Milliseconds 500
        }
    }

    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Test-TcpPortOpen {
    param([string]$HostName, [int]$Port, [int]$TimeoutMilliseconds = 350)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-TcpPortFree {
    param([int]$Port)
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), $Port)
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Find-FreeTcpPort {
    param([int]$StartPort)
    for ($port = $StartPort; $port -le ($StartPort + 100); $port++) {
        if (Test-TcpPortFree -Port $port) {
            return $port
        }
    }
    throw "No free localhost TCP port found from $StartPort through $($StartPort + 100)."
}

function Get-WorkspaceGophishProcesses {
    if (-not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    $escaped = $Root.TrimEnd("\")
    @(Get-CimInstance Win32_Process -Filter "Name = 'gophish.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ExecutablePath -and
            ([System.IO.Path]::GetFullPath($_.ExecutablePath)).StartsWith($escaped, [System.StringComparison]::OrdinalIgnoreCase)
        })
}

function Get-WorkspaceBrowserProcesses {
    $needle = $BrowserProfileDir
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
}

function Stop-WorkspaceBrowser {
    $processes = @(Get-WorkspaceBrowserProcesses)

    if (Test-Path -LiteralPath $BrowserPidPath) {
        $pidText = (Get-Content -LiteralPath $BrowserPidPath -Raw).Trim()
        if ($pidText -match "^\d+$") {
            $pidProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
            if ($pidProcess -and $pidProcess.CommandLine -and $pidProcess.CommandLine.IndexOf($BrowserProfileDir, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $processes += $pidProcess
            }
        }
    }

    $processes = @($processes | Sort-Object ProcessId -Unique)
    foreach ($proc in $processes) {
        Write-Step "Stopping workspace browser process PID $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(20)
    do {
        $remaining = @(Get-WorkspaceBrowserProcesses)
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw "Timed out stopping workspace browser process."
}

function Stop-WorkspaceGophish {
    $processes = @(Get-WorkspaceGophishProcesses)

    if (Test-Path -LiteralPath $PidPath) {
        $pidText = (Get-Content -LiteralPath $PidPath -Raw).Trim()
        if ($pidText -match "^\d+$") {
            $pidProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $pidText" -ErrorAction SilentlyContinue
            if ($pidProcess -and $pidProcess.ExecutablePath -and ([System.IO.Path]::GetFullPath($pidProcess.ExecutablePath)).StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $processes += $pidProcess
            }
        }
    }

    $processes = @($processes | Sort-Object ProcessId -Unique)
    foreach ($proc in $processes) {
        Write-Step "Stopping previous workspace GoPhish process PID $($proc.ProcessId)"
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        $remaining = @(Get-WorkspaceGophishProcesses)
        if ($remaining.Count -eq 0) {
            return
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw "Timed out stopping previous workspace GoPhish process."
}

function Find-BrowserExecutable {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Google\Chrome\Application\chrome.exe"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
        (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command chrome.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $command = Get-Command msedge.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Could not find Chrome or Edge executable for automatic logged-in browser launch."
}

function Assert-PlaywrightCore {
    Ensure-Directory -Path $BrowserAutomationDir
    $packageCandidates = @(
        (Join-Path $BrowserAutomationDir "node_modules\playwright-core\package.json"),
        (Join-Path $env:USERPROFILE ".codex\tools\playwright-mcp\node_modules\playwright-core\package.json")
    )

    foreach ($packagePath in $packageCandidates) {
        if ($packagePath -and (Test-Path -LiteralPath $packagePath)) {
            $script:PlaywrightNodePath = Split-Path -Parent (Split-Path -Parent $packagePath)
            return
        }
    }

    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $nodeCommand) {
        throw "node.exe is required for automatic browser login, but it was not found."
    }
    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npmCommand) {
        $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    }
    if (-not $npmCommand) {
        throw "npm is required to install local playwright-core for browser login, but it was not found."
    }

    Write-Step "Installing local playwright-core for browser login"
    Push-Location $BrowserAutomationDir
    try {
        & $npmCommand.Source install --prefix $BrowserAutomationDir playwright-core@latest --no-audit --no-fund --loglevel=error
        if ($LASTEXITCODE -ne 0) {
            throw "npm install playwright-core failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }

    $localPackagePath = Join-Path $BrowserAutomationDir "node_modules\playwright-core\package.json"
    if (-not (Test-Path -LiteralPath $localPackagePath)) {
        throw "playwright-core package was not found after npm install."
    }
    $script:PlaywrightNodePath = Split-Path -Parent (Split-Path -Parent $localPackagePath)
}

function Write-BrowserLoginHelper {
    Ensure-Directory -Path $BrowserAutomationDir
    @'
const { chromium } = require("playwright-core");

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

(async () => {
  const adminUrl = required("GOPHISH_ADMIN_URL").replace(/\/$/, "");
  const username = required("GOPHISH_ADMIN_USERNAME");
  const password = required("GOPHISH_ADMIN_PASSWORD");
  const newPassword = required("GOPHISH_ADMIN_NEW_PASSWORD");
  const debugUrl = required("GOPHISH_BROWSER_DEBUG_URL");

  const browser = await chromium.connectOverCDP(debugUrl);
  const context = browser.contexts()[0];
  if (!context) throw new Error("No browser context was available over CDP");

  let page = context.pages().find((candidate) => candidate.url().startsWith(adminUrl)) || context.pages()[0];
  if (!page) page = await context.newPage();
  page.setDefaultTimeout(30000);

  await page.goto(`${adminUrl}/login`, { waitUntil: "domcontentloaded" });
  await page.locator('input[name="username"]').fill(username);
  await page.locator('input[name="password"]').fill(password);

  await Promise.all([
    page.waitForLoadState("domcontentloaded").catch(() => {}),
    page.locator('button[type="submit"], input[type="submit"]').first().click(),
  ]);

  await page.waitForTimeout(1000);
  if (page.url().includes("/login")) {
    await page.waitForURL((url) => !url.toString().includes("/login"), { timeout: 15000 }).catch(() => {});
  }

  let passwordReset = false;
  const bodyAfterLogin = await page.locator("body").innerText({ timeout: 15000 }).catch(async () => page.content());
  const resetFormPresent = await page.locator('input[name="confirm_password"]').count().catch(() => 0);
  if (resetFormPresent > 0 && /Reset Your Password|Save Password/i.test(bodyAfterLogin)) {
    await page.locator('input[name="password"]').fill(newPassword);
    await page.locator('input[name="confirm_password"]').fill(newPassword);
    await Promise.all([
      page.waitForLoadState("domcontentloaded").catch(() => {}),
      page.locator('button[type="submit"], input[type="submit"]').first().click(),
    ]);
    await page.waitForTimeout(1000);
    passwordReset = true;
  }

  await page.goto(adminUrl, { waitUntil: "networkidle" });
  const bodyText = await page.locator("body").innerText({ timeout: 15000 }).catch(async () => page.content());
  if (page.url().includes("/login") || !/Dashboard|Campaigns|Users & Groups|Sending Profiles|Landing Pages/i.test(bodyText)) {
    throw new Error(`Browser did not reach authenticated GoPhish UI. url=${page.url()} body=${bodyText.slice(0, 300)}`);
  }

  console.log(`BROWSER_PASSWORD_RESET=${passwordReset ? "true" : "false"}`);
  console.log(`BROWSER_LOGIN_READY=${page.url()}`);
  process.exit(0);
})();
'@ | Set-Content -LiteralPath $BrowserLoginHelperPath -Encoding ASCII
}

function Wait-ForBrowserDebug {
    param([int]$DebugPort)

    $debugUrl = "http://127.0.0.1:$DebugPort/json/version"
    $deadline = (Get-Date).AddSeconds(45)
    do {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $debugUrl -TimeoutSec 2 | Out-Null
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)

    throw "Browser remote debugging endpoint did not become reachable at $debugUrl."
}

function Open-LoggedInBrowser {
    param([string]$AdminUrl, [object]$Credential, [string]$NewPassword)

    Stop-WorkspaceBrowser
    Ensure-Directory -Path $BrowserProfileDir
    Ensure-Directory -Path $BrowserAutomationDir
    Assert-PlaywrightCore
    Write-BrowserLoginHelper

    $browserExe = Find-BrowserExecutable
    $debugPort = Find-FreeTcpPort -StartPort 9222
    $browserArgs = @(
        "--remote-debugging-port=$debugPort",
        "--user-data-dir=`"$BrowserProfileDir`"",
        "--ignore-certificate-errors",
        "--no-first-run",
        "--no-default-browser-check",
        "--new-window",
        "`"$AdminUrl/login`""
    )

    Write-Step "Opening logged-in GoPhish browser session"
    $browserProc = Start-Process -FilePath $browserExe -ArgumentList $browserArgs -PassThru
    Set-Content -LiteralPath $BrowserPidPath -Value $browserProc.Id -Encoding ASCII
    Set-Content -LiteralPath $BrowserDebugPortPath -Value $debugPort -Encoding ASCII
    Wait-ForBrowserDebug -DebugPort $debugPort

    $nodeCommand = Get-Command node.exe -ErrorAction Stop
    $env:GOPHISH_ADMIN_URL = $AdminUrl
    $env:GOPHISH_ADMIN_USERNAME = $Credential.Username
    $env:GOPHISH_ADMIN_PASSWORD = $Credential.Password
    $env:GOPHISH_ADMIN_NEW_PASSWORD = $NewPassword
    $env:GOPHISH_BROWSER_DEBUG_URL = "http://127.0.0.1:$debugPort"

    $previousNodePath = $env:NODE_PATH
    $env:NODE_PATH = $script:PlaywrightNodePath
    try {
        $output = & $nodeCommand.Source $BrowserLoginHelperPath 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $env:NODE_PATH = $previousNodePath
    }
    $output | Set-Content -LiteralPath $BrowserLoginLogPath -Encoding ASCII
    if ($exitCode -ne 0) {
        throw "Browser login automation failed with exit code $exitCode. See $BrowserLoginLogPath"
    }

    return [pscustomobject]@{
        BrowserExecutable = $browserExe
        BrowserPid = $browserProc.Id
        DebugPort = $debugPort
        Log = $BrowserLoginLogPath
        PasswordReset = (($output -join "`n") -match "BROWSER_PASSWORD_RESET=true")
    }
}

function Assert-Download {
    Ensure-Directory -Path $DownloadDir

    $needsDownload = $true
    if (Test-Path -LiteralPath $ZipPath) {
        $actualHash = Get-Sha256 -Path $ZipPath
        if ($actualHash -eq $ExpectedSha256) {
            $needsDownload = $false
        } else {
            Remove-Item -LiteralPath $ZipPath -Force
        }
    }

    if ($needsDownload) {
        Write-Step "Downloading $AssetName"
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
    }

    $hash = Get-Sha256 -Path $ZipPath
    if ($hash -ne $ExpectedSha256) {
        throw "SHA256 mismatch for $ZipPath. Expected $ExpectedSha256, got $hash."
    }
    Write-Step "Verified release SHA256 $hash"
}

function Assert-Install {
    $currentVersion = $null
    if (Test-Path -LiteralPath $VersionMarkerPath) {
        $currentVersion = (Get-Content -LiteralPath $VersionMarkerPath -Raw).Trim()
    }

    if ((Test-Path -LiteralPath $ExePath) -and $currentVersion -eq $ReleaseVersion) {
        Write-Step "Existing $ReleaseVersion install is present"
        return
    }

    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force
    }
    Ensure-Directory -Path $InstallDir
    Write-Step "Extracting $AssetName"
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $InstallDir -Force

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "GoPhish executable was not found after extraction: $ExePath"
    }

    Set-Content -LiteralPath $VersionMarkerPath -Value $ReleaseVersion -Encoding ASCII
}

function Set-GophishConfig {
    param([int]$ResolvedAdminPort, [int]$ResolvedPhishPort)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "GoPhish config was not found: $ConfigPath"
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $config.admin_server.listen_url = "127.0.0.1:$ResolvedAdminPort"
    $config.admin_server.use_tls = $true
    $config.phish_server.listen_url = "127.0.0.1:$ResolvedPhishPort"
    $config.phish_server.use_tls = $false

    if (-not ($config.PSObject.Properties.Name -contains "contact_address")) {
        $config | Add-Member -MemberType NoteProperty -Name contact_address -Value "local-admin@example.invalid"
    } else {
        $config.contact_address = "local-admin@example.invalid"
    }

    if (-not ($config.admin_server.PSObject.Properties.Name -contains "trusted_origins")) {
        $config.admin_server | Add-Member -MemberType NoteProperty -Name trusted_origins -Value @()
    }
    $config.admin_server.trusted_origins = @(
        "https://127.0.0.1:$ResolvedAdminPort",
        "https://localhost:$ResolvedAdminPort"
    )

    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ConfigPath -Encoding ASCII
    Write-Step "Configured localhost admin port $ResolvedAdminPort and phishing port $ResolvedPhishPort"
}

function Wait-ForTcp {
    param([string]$HostName, [int]$Port, [int]$TimeoutSeconds = 45)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-TcpPortOpen -HostName $HostName -Port $Port -TimeoutMilliseconds 500) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-CombinedLogText {
    $parts = @()
    foreach ($path in @($LogPath, $ErrLogPath)) {
        if (Test-Path -LiteralPath $path) {
            $parts += Get-Content -LiteralPath $path -Raw
        }
    }
    $parts -join "`n"
}

function Get-AdminCredentialFromLogs {
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $text = Get-CombinedLogText
        $match = [regex]::Match($text, "Please login with the username\s+(?<username>[^\s`"]+)\s+and the password\s+(?<password>[^\s`"]+)")
        if ($match.Success) {
            return [pscustomobject]@{
                Username = $match.Groups["username"].Value
                Password = $match.Groups["password"].Value
            }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Read-StoredCredential {
    if (-not (Test-Path -LiteralPath $CredentialPath)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $CredentialPath -Raw
    $username = [regex]::Match($raw, "^Username:\s*(?<value>.+)$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $password = [regex]::Match($raw, "^Password:\s*(?<value>.+)$", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($username.Success -and $password.Success) {
        return [pscustomobject]@{
            Username = $username.Groups["value"].Value.Trim()
            Password = $password.Groups["value"].Value.Trim()
        }
    }

    return $null
}

function Save-AdminCredential {
    param([string]$AdminUrl, [object]$Credential)

    $content = @(
        "GoPhish local admin credentials",
        "Generated: $(Get-Date -Format o)",
        "AdminUrl: $AdminUrl",
        "Username: $($Credential.Username)",
        "Password: $($Credential.Password)",
        "",
        "This file was generated by setup-gophish.ps1 for the local 127.0.0.1 workspace instance only."
    )
    Set-Content -LiteralPath $CredentialPath -Value $content -Encoding ASCII
}

function New-LocalAdminPassword {
    $random = ([guid]::NewGuid().ToString("N") + [guid]::NewGuid().ToString("N")).Substring(0, 24)
    return "Gophish!$random"
}

function Test-AdminLogin {
    param([string]$AdminUrl, [object]$Credential)

    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $loginResponse = Invoke-LocalWebRequest -Uri "$AdminUrl/login" -WebSession $session -TimeoutSec 15
    $content = [string]$loginResponse.Content
    $csrfMatch = [regex]::Match($content, "name=`"csrf_token`"[^>]*value=`"(?<token>[^`"]+)`"|value=`"(?<token2>[^`"]+)`"[^>]*name=`"csrf_token`"")
    if (-not $csrfMatch.Success) {
        throw "Could not find GoPhish CSRF token on login page."
    }

    $token = $csrfMatch.Groups["token"].Value
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = $csrfMatch.Groups["token2"].Value
    }

    $body = @{
        username = $Credential.Username
        password = $Credential.Password
        csrf_token = $token
    }
    try {
        $postResponse = Invoke-LocalWebRequest -Uri "$AdminUrl/login" -Method Post -Body $body -WebSession $session -TimeoutSec 15
    } catch {
        throw "GoPhish admin credential login probe failed: $($_.Exception.Message)"
    }
    $postContent = [string]$postResponse.Content

    if ($postContent -match "Invalid Username/Password|Login") {
        throw "GoPhish admin credential login probe did not reach the authenticated UI."
    }

    return $true
}

function Start-Gophish {
    Remove-Item -LiteralPath $LogPath, $ErrLogPath -Force -ErrorAction SilentlyContinue
    Write-Step "Starting GoPhish"
    $proc = Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir -RedirectStandardOutput $LogPath -RedirectStandardError $ErrLogPath -PassThru -WindowStyle Hidden
    Set-Content -LiteralPath $PidPath -Value $proc.Id -Encoding ASCII
    return $proc
}

function Reset-WorkspaceDatabase {
    foreach ($name in @("gophish.db", "gophish.db-shm", "gophish.db-wal")) {
        $path = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $CredentialPath -Force -ErrorAction SilentlyContinue
    Write-Step "Reset workspace GoPhish database to recover local admin credentials"
}

function Invoke-SetupAttempt {
    Enable-LocalHttpsTrust
    Ensure-Directory -Path $Root
    Ensure-Directory -Path $LogsDir
    Ensure-Directory -Path $StateDir

    Stop-WorkspaceGophish
    Stop-WorkspaceBrowser
    Assert-Download
    Assert-Install

    $resolvedAdminPort = Find-FreeTcpPort -StartPort $AdminPort
    $resolvedPhishPort = Find-FreeTcpPort -StartPort $PhishPort
    if ($resolvedAdminPort -eq $resolvedPhishPort) {
        $resolvedPhishPort = Find-FreeTcpPort -StartPort ($resolvedPhishPort + 1)
    }

    Set-GophishConfig -ResolvedAdminPort $resolvedAdminPort -ResolvedPhishPort $resolvedPhishPort
    $adminUrl = "https://127.0.0.1:$resolvedAdminPort"
    $phishUrl = "http://127.0.0.1:$resolvedPhishPort"
    $proc = Start-Gophish

    if (-not (Wait-ForTcp -HostName "127.0.0.1" -Port $resolvedAdminPort -TimeoutSeconds 60)) {
        throw "Admin port $resolvedAdminPort did not become reachable."
    }
    if (-not (Wait-ForTcp -HostName "127.0.0.1" -Port $resolvedPhishPort -TimeoutSeconds 60)) {
        throw "Phishing server port $resolvedPhishPort did not become reachable."
    }

    Invoke-LocalWebRequest -Uri "$adminUrl/login" -TimeoutSec 15 | Out-Null
    Invoke-LocalWebRequestAllowStatus -Uri $phishUrl -AllowedStatusCodes @(200, 404) -TimeoutSec 15

    $credential = Get-AdminCredentialFromLogs
    if ($null -ne $credential) {
        Save-AdminCredential -AdminUrl $adminUrl -Credential $credential
    } else {
        $credential = Read-StoredCredential
    }

    if ($null -eq $credential) {
        throw "GoPhish started, but no admin credential was printed or already stored at $CredentialPath."
    }

    $browserResult = $null
    $adminLoginProof = "skipped"
    if (-not $NoOpen) {
        $newPassword = New-LocalAdminPassword
        $browserResult = Open-LoggedInBrowser -AdminUrl $adminUrl -Credential $credential -NewPassword $newPassword
        if ($browserResult.PasswordReset) {
            $credential = [pscustomobject]@{
                Username = $credential.Username
                Password = $newPassword
            }
            Save-AdminCredential -AdminUrl $adminUrl -Credential $credential
        }
    } else {
        Test-AdminLogin -AdminUrl $adminUrl -Credential $credential | Out-Null
        $adminLoginProof = "pass"
    }

    $status = [ordered]@{
        release_version = $ReleaseVersion
        asset = $AssetName
        sha256 = $ExpectedSha256
        root = $Root
        install_dir = $InstallDir
        executable = $ExePath
        admin_url = $adminUrl
        phish_url = $phishUrl
        credentials_file = $CredentialPath
        pid = $proc.Id
        browser_pid = if ($null -ne $browserResult) { $browserResult.BrowserPid } else { $null }
        browser_debug_port = if ($null -ne $browserResult) { $browserResult.DebugPort } else { $null }
        browser_executable = if ($null -ne $browserResult) { $browserResult.BrowserExecutable } else { $null }
        started_at = (Get-Date -Format o)
        verification = [ordered]@{
            sha256 = "pass"
            admin_tcp = "pass"
            phish_tcp = "pass"
            admin_login_page = "pass"
            phish_http = "pass"
            admin_login = $adminLoginProof
            browser_logged_in = if ($null -ne $browserResult) { "pass" } else { "skipped" }
        }
    }
    $status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StatusPath -Encoding ASCII

    Write-Step "GoPhish is ready at $adminUrl"
    Write-Host "STATUS_FILE=$StatusPath"
    Write-Host "CREDENTIALS_FILE=$CredentialPath"
}

$lastError = $null
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
        Write-Step "Setup attempt $attempt of $MaxAttempts"
        Invoke-SetupAttempt
        exit 0
    } catch {
        $lastError = $_
        Write-Warning "Attempt $attempt failed: $($_.Exception.Message)"
        Stop-WorkspaceGophish
        Stop-WorkspaceBrowser
        if ($_.Exception.Message -match "admin credential|no admin credential|Browser login automation failed") {
            Reset-WorkspaceDatabase
        }
        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds 2
        }
    }
}

throw "GoPhish setup failed after $MaxAttempts attempts. Last error: $($lastError.Exception.Message)"
