# Generated for GLM-5.2 default OpenCode launcher
# Self-bootstrap: load the profile environment when this script runs
# outside a profile session so it behaves exactly like the function it
# was copied from.
$__2scProfileModule = 'C:\Users\micha\Documents\WindowsPowerShell\Modules\CodexProfileFunctions\CodexProfileFunctions.psd1'
$__2scNeedBootstrap = -not (Get-Command -Name 'Initialize-CodexProfileFunctions' -CommandType Function -ErrorAction SilentlyContinue)
if (-not $__2scNeedBootstrap) {
    $__2scLoadedModule = Get-Module -Name 'CodexProfileFunctions' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($__2scLoadedModule) {
        $__2scLoadedFingerprint = $__2scLoadedModule.SessionState.PSVariable.GetValue('ProfileModuleFingerprint')
        $__2scModuleFile = Join-Path $__2scLoadedModule.ModuleBase 'CodexProfileFunctions.psm1'
        if ([System.IO.File]::Exists($__2scModuleFile)) {
            $__2scDiskInfo = Get-Item -LiteralPath $__2scModuleFile -ErrorAction SilentlyContinue
            if ($__2scDiskInfo) {
                $__2scDiskFingerprint = '{0}|{1}' -f $__2scDiskInfo.Length, $__2scDiskInfo.LastWriteTimeUtc.Ticks
                if ([string]$__2scLoadedFingerprint -and $__2scDiskFingerprint -ne [string]$__2scLoadedFingerprint) { $__2scNeedBootstrap = $true }
            }
        }
    }
}
if ($__2scNeedBootstrap) {
    if (-not (Test-Path -LiteralPath $__2scProfileModule -PathType Leaf)) {
        throw "2sc-generated script requires the Codex profile module: $__2scProfileModule"
    }
    Import-Module -Name $__2scProfileModule -Force -DisableNameChecking -ErrorAction Stop
    Initialize-CodexProfileFunctions
}
function glm52oc {
    [CmdletBinding()]
    param(
        [switch]$Check,
        [switch]$Wait,  # Wait for GLM-5.2 if rate-limited (like nvioc -m behavior)
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Args
    )

    # ═══════════════════════════════════════════════════════════════════
    # NVIDIA API KEY LOADING (same priority as nvioc)
    # ═══════════════════════════════════════════════════════════════════
    $nvidiaApiKey = $env:NVIDIA_API_KEY
    $keySource = 'env'

    if (-not $nvidiaApiKey -or [string]::IsNullOrWhiteSpace($nvidiaApiKey)) {
        $keyFile = 'F:\backup\windowsapps\credentials\nvidia\api.txt'
        if (Test-Path -LiteralPath $keyFile -PathType Leaf) {
            $nvidiaApiKey = (Get-Content -LiteralPath $keyFile -Raw).Trim()
            $keySource = 'file'
            Write-Host "OC_PROGRESS stage=api-key-loaded source=file"
        }
    }

    if (-not $nvidiaApiKey -or [string]::IsNullOrWhiteSpace($nvidiaApiKey)) {
        $authFile = Join-Path $env:USERPROFILE '.local\share\opencode\auth.json'
        if (Test-Path -LiteralPath $authFile -PathType Leaf) {
            try {
                $authJson = Get-Content -LiteralPath $authFile -Raw | ConvertFrom-Json
                if ($authJson.nvidia -and $authJson.nvidia.key) {
                    $nvidiaApiKey = $authJson.nvidia.key
                    $keySource = 'auth.json'
                    Write-Host "OC_PROGRESS stage=api-key-loaded source=auth.json"
                }
            } catch {
                Write-Host "OC_PROGRESS stage=auth-json-parse-error msg=$($_.Exception.Message)"
            }
        }
    }

    if (-not $nvidiaApiKey -or [string]::IsNullOrWhiteSpace($nvidiaApiKey)) {
        $ocCfgCandidates = @(
            (Join-Path $env:USERPROFILE '.config\opencode\opencode.json'),
            (Join-Path $env:APPDATA 'opencode\opencode.json')
        )
        foreach ($ocCfg in $ocCfgCandidates) {
            if (-not (Test-Path -LiteralPath $ocCfg -PathType Leaf)) { continue }
            try {
                $ocCfgJson = Get-Content -LiteralPath $ocCfg -Raw | ConvertFrom-Json
                $nested = $null
                if ($ocCfgJson.provider -and $ocCfgJson.provider.'nvidia-nim') {
                    $nested = $ocCfgJson.provider.'nvidia-nim'
                } elseif ($ocCfgJson.provider -and $ocCfgJson.provider.nvidia) {
                    $nested = $ocCfgJson.provider.nvidia
                }
                if ($nested) {
                    if ($nested.options -and $nested.options.apiKey) {
                        $nvidiaApiKey = [string]$nested.options.apiKey
                        $keySource = 'opencode.json'
                        Write-Host "OC_PROGRESS stage=api-key-loaded source=opencode.json"
                        break
                    }
                }
            } catch {
                Write-Host "OC_PROGRESS stage=opencode-config-parse-error msg=$($_.Exception.Message)"
            }
        }
    }

    if (-not $nvidiaApiKey -or [string]::IsNullOrWhiteSpace($nvidiaApiKey)) {
        throw "NVIDIA_API_KEY not found. Set env var, ensure key file at F:\backup\windowsapps\credentials\nvidia\api.txt, or run 'opencode auth login' with nvidia provider."
    }

    # Set NVIDIA API key in environment for opencode's built-in nvidia provider
    $env:NVIDIA_API_KEY = $nvidiaApiKey
    $env:OPENAI_API_KEY = $nvidiaApiKey

    # ═══════════════════════════════════════════════════════════════════
    # PERMISSION MODE (auto-allow all tools)
    # ═══════════════════════════════════════════════════════════════════
    $env:OPENCODE_PERMISSION_BASH = 'allow'
    $env:OPENCODE_PERMISSION_READ = 'allow'
    $env:OPENCODE_PERMISSION_WRITE = 'allow'
    $env:OPENCODE_PERMISSION_EDIT = 'allow'
    $env:OPENCODE_PERMISSION_GLOB = 'allow'
    $env:OPENCODE_PERMISSION_GREP = 'allow'
    $env:OPENCODE_PERMISSION_TASK = 'allow'
    $env:OPENCODE_PERMISSION_WEBFETCH = 'allow'
    $env:OPENCODE_PERMISSION_PATCH = 'allow'
    $env:OPENCODE_PERMISSION_LIST = 'allow'
    $env:OPENCODE_PERMISSION_TODO = 'allow'
    $env:OPENCODE_PERMISSION_QUESTION = 'allow'

    # ═══════════════════════════════════════════════════════════════════
    # GLM-5.2 AS DEFAULT MODEL (no complex fallback chain)
    # ═══════════════════════════════════════════════════════════════════
    $modelOrder = @(
        'nvidia-nim/z-ai/glm-5.2',                    # DEFAULT: GLM-5.2 (753B MoE, best coding)
        'nvidia-nim/nvidia/nemotron-3-ultra-550b-a55b',  # Fallback 1: Nemotron 3 Ultra
        'nvidia-nim/nvidia/nemotron-3-super-120b-a12b',  # Fallback 2: Nemotron 3 Super
        'nvidia-nim/deepseek-ai/deepseek-v4-flash-0731', # Fallback 3: DeepSeek V4 Flash
        'nvidia-nim/thinkingmachines/inkling'           # Fallback 4: Inkling
    )

    $modelLabels = @{
        'nvidia-nim/z-ai/glm-5.2'                       = 'GLM-5.2 (753B MoE, best coding)'
        'nvidia-nim/nvidia/nemotron-3-ultra-550b-a55b'  = 'Nemotron 3 Ultra (550B flagship, best general)'
        'nvidia-nim/nvidia/nemotron-3-super-120b-a12b'  = 'Nemotron 3 Super (120B, strong general)'
        'nvidia-nim/deepseek-ai/deepseek-v4-flash-0731' = 'DeepSeek V4 Flash (284B MoE, fast coding)'
        'nvidia-nim/thinkingmachines/inkling'            = 'Inkling (multimodal, text+image+audio)'
    }

    $defaultModel = $modelOrder[0]  # GLM-5.2 is now DEFAULT

    # ═══════════════════════════════════════════════════════════════════
    # PARSE COMMAND-LINE ARGUMENTS (same as nvioc)
    # ═══════════════════════════════════════════════════════════════════
    $modelArg = $defaultModel
    $hasModelFlag = $false
    $filteredArgs = @()
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $arg = $Args[$i]
        if ($arg -eq '-m' -or $arg -eq '--model') {
            $hasModelFlag = $true
            if ($i + 1 -lt $Args.Count) {
                $modelArg = $Args[$i + 1]
                $i++
            }
        } elseif ($arg -match '^-m=(.+)$') {
            $hasModelFlag = $true
            $modelArg = $matches[1]
        } elseif ($arg -match '^--model=(.+)$') {
            $hasModelFlag = $true
            $modelArg = $matches[1]
        } else {
            $filteredArgs += $arg
        }
    }
    $Args = $filteredArgs

    # ═══════════════════════════════════════════════════════════════════
    # SIMPLE HEALTH CHECK - NO RETRY LOOPS THAT CAUSE "RETRYING" ERRORS
    # ═══════════════════════════════════════════════════════════════════
    function Test-ModelFast {
        param(
            [string]$ModelId,
            [string]$ApiKey,
            [int]$TimeoutSec = 5
        )
        $apiModelId = $ModelId -replace '^[^/]+/', ''
        try {
            $headers = @{
                'Authorization' = "Bearer $ApiKey"
                'Content-Type'  = 'application/json'
            }
            $body = @{
                model       = $apiModelId
                messages    = @(@{ role = 'user'; content = 'Hi' })
                max_tokens  = 1
                temperature = 0
            } | ConvertTo-Json -Depth 5
            $null = Invoke-RestMethod -Uri 'https://integrate.api.nvidia.com/v1/chat/completions' -Headers $headers -Method Post -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }

    # ═══════════════════════════════════════════════════════════════════
    # MODEL HEALTH CACHE (same as nvioc but simplified)
    # ═══════════════════════════════════════════════════════════════════
    $healthCachePath = Join-Path $env:USERPROFILE '.config\opencode\model-health.json'

    function Read-ModelHealthCache {
        if (Test-Path -LiteralPath $healthCachePath -PathType Leaf) {
            try {
                $json = Get-Content -LiteralPath $healthCachePath -Raw | ConvertFrom-Json
                # Convert PSObject models to hashtable for indexing
                if ($json -and $json.models) {
                    $hashModels = @{}
                    foreach ($prop in $json.models.PSObject.Properties) {
                        $hashModels[$prop.Name] = $prop.Value
                    }
                    $json.models = $hashModels
                }
                return $json
            } catch { }
        }
        return $null
    }

    function Write-ModelHealthCache {
        param([object]$Cache)
        try {
            $dir = Split-Path -Parent $healthCachePath
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }
            $Cache | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $healthCachePath -Encoding UTF8
        } catch { }
    }

    function Test-ModelCached {
        param(
            [string]$ModelId,
            [string]$ApiKey,
            [int]$OkTtlSec = 60,
            [int]$ThrottledRetrySec = 45
        )
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $cache = Read-ModelHealthCache
        if ($cache -and $cache.models -and $cache.models[$ModelId]) {
            $entry = $cache.models[$ModelId]
            $ageSec = ($now - [int64]$entry.ts) / 1000.0
            if ($entry.ok -and $ageSec -le $OkTtlSec) {
                return @{ ok = $true; status = 200; source = 'cache' }
            }
            if (-not $entry.ok -and $entry.status -eq 429 -and $ageSec -le $ThrottledRetrySec) {
                return @{ ok = $false; status = 429; source = 'cache' }
            }
        }
        # Single probe, no retries
        $apiModelId = $ModelId -replace '^[^/]+/', ''
        $resultOk = $false
        $resultStatus = 0
        try {
            $headers = @{
                'Authorization' = "Bearer $ApiKey"
                'Content-Type'  = 'application/json'
            }
            $body = @{
                model       = $apiModelId
                messages    = @(@{ role = 'user'; content = 'Hi' })
                max_tokens  = 1
                temperature = 0
            } | ConvertTo-Json -Depth 5
            $null = Invoke-RestMethod -Uri 'https://integrate.api.nvidia.com/v1/chat/completions' -Headers $headers -Method Post -Body $body -TimeoutSec 5 -ErrorAction Stop
            $resultOk = $true
            $resultStatus = 200
        } catch {
            if ($_.Exception.Response) { $resultStatus = [int]$_.Exception.Response.StatusCode }
        }
        if ($null -eq $cache) { $cache = @{} }
        if (-not $cache.models) { $cache.models = @{} }
        $cache.models[$ModelId] = @{
            ok     = $resultOk
            status = $resultStatus
            ts     = $now
        }
        Write-ModelHealthCache -Cache $cache
        return @{ ok = $resultOk; status = $resultStatus; source = 'probe' }
    }

    function Clear-StaleOpenCode {
        try {
            $procs = Get-Process -Name 'opencode' -ErrorAction SilentlyContinue
            foreach ($p in $procs) {
                $parentPid = 0
                try {
                    $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).ParentProcessId
                } catch { }
                if ($parentPid -gt 0) {
                    $parentAlive = Get-Process -Id $parentPid -ErrorAction SilentlyContinue
                    if (-not $parentAlive) {
                        Write-Host "OC_PROGRESS stage=stale-opencode-killed pid=$($p.Id) (orphan retry loop)"
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        } catch { }
    }

    function Backup-OpenCodeSessions {
        $dbPath = Join-Path $env:USERPROFILE '.local\share\opencode\opencode.db'
        if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf)) { return }
        $backupDir = 'F:\backup\opencode-sessions'
        try {
            if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
            }
            $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupPath = Join-Path $backupDir "opencode_$stamp.db"
            $pyExe = $null
            $pyCandidates = @()
            foreach ($pyCmd in (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue)) {
                if ($pyCmd.Source -notmatch 'WindowsApps') { $pyCandidates += $pyCmd.Source }
            }
            if ($pyCandidates.Count -gt 0) { $pyExe = $pyCandidates[0] }
            if (-not $pyExe) {
                foreach ($pyCmd in (Get-Command py -CommandType Application -ErrorAction SilentlyContinue)) {
                    if ($pyCmd.Source -notmatch 'WindowsApps') { $pyCandidates += $pyCmd.Source }
                }
                if ($pyCandidates.Count -gt 0) { $pyExe = $pyCandidates[0] }
            }
            if (-not $pyExe) { return }
            $pyScript = "import sqlite3,sys;src=sqlite3.connect(r'$dbPath');dst=sqlite3.connect(r'$backupPath');src.backup(dst);dst.close();src.close()"
            & $pyExe -c $pyScript 2>$null
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Get-ChildItem -LiteralPath $backupDir -Filter 'opencode_*.db' |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -Skip 20 |
                    Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "OC_PROGRESS stage=sessions-backed-up path=$backupPath"
            }
        } catch {
            Write-Host "OC_PROGRESS stage=sessions-backup-skip msg=$($_.Exception.Message)"
        }
    }

    $finalModelArg = $modelArg
    $finalLabel = $modelLabels[$finalModelArg]
    if (-not $finalLabel) { $finalLabel = $finalModelArg }

    if ($Check) {
        # Full health check mode (for explicit verification)
        Write-Host "OC_PROGRESS stage=fetching-model-list"
        $headers = @{ 'Authorization' = "Bearer $nvidiaApiKey" }
        try {
            $response = Invoke-RestMethod -Uri 'https://integrate.api.nvidia.com/v1/models' -Headers $headers -Method Get -TimeoutSec 30 -ErrorAction Stop
            $nimModelList = if ($response -and $response.data) { $response.data } else { $null }
        } catch {
            $nimModelList = $null
            Write-Host "OC_PROGRESS stage=model-list-error msg=$($_.Exception.Message)"
        }

        $modelsToTest = @()
        if ($hasModelFlag) {
            $modelsToTest += $modelArg
            foreach ($m in $modelOrder) { if ($m -ne $modelArg) { $modelsToTest += $m } }
        } else { $modelsToTest = $modelOrder }

        $workingModelId = $null
        if ($null -ne $nimModelList) {
            foreach ($testId in $modelsToTest) {
                $label = $modelLabels[$testId]; if (-not $label) { $label = $testId }
                # Check model exists in catalog
                $apiModelId = $testId -replace '^[^/]+/', ''
                $found = $false
                foreach ($m in $nimModelList) { if ($m.id -eq $apiModelId) { $found = $true; break } }
                if (-not $found) {
                    Write-Host "OC_PROGRESS stage=model-not-listed model=$testId label=$label"
                    continue
                }
                Write-Host "OC_PROGRESS stage=probe-testing model=$testId label=$label"
                $probe = Test-ModelCached -ModelId $testId -ApiKey $nvidiaApiKey
                if ($probe.ok) {
                    Write-Host "OC_PROGRESS stage=model-verified model=$testId label=$label source=$($probe.source)"
                    $workingModelId = $testId
                    break
                } else {
                    Write-Host "OC_PROGRESS stage=model-probe-failed model=$testId label=$label status=$($probe.status)"
                }
            }
        }
        if (-not $workingModelId) {
            Write-Host "OC_PROGRESS stage=all-probes-failed using-fallback=$defaultModel"
            $workingModelId = $defaultModel
        }
        $finalModelArg = $workingModelId
        $finalLabel = $modelLabels[$finalModelArg]
        if (-not $finalLabel) { $finalLabel = $finalModelArg }
        if ($finalModelArg -ne $modelArg) {
            Write-Host "OC_PROGRESS stage=auto-fallback from=$modelArg to=$finalModelArg label=$finalLabel"
        } else {
            Write-Host "OC_PROGRESS stage=model-selected model=$finalModelArg label=$finalLabel"
        }
    } else {
        # INSTANT PATH - NO WAIT LOOPS (unless -Wait for GLM-5.2 default)
        Clear-StaleOpenCode
        Backup-OpenCodeSessions

        $isDefaultModel = ($finalModelArg -eq $defaultModel)

        # Single probe for chosen model (cache-aware, instant if fresh)
        $launchModel = $null
        $probe = Test-ModelCached -ModelId $finalModelArg -ApiKey $nvidiaApiKey
        if ($probe.ok) {
            $launchModel = $finalModelArg
            Write-Host "OC_PROGRESS stage=preflight-ok model=$finalModelArg label=$finalLabel source=$($probe.source)"
        } else {
            Write-Host "OC_PROGRESS stage=preflight-skip model=$finalModelArg status=$($probe.status) source=$($probe.source) (rate-limited or unavailable)"
        }

        # If -Wait flag and using default GLM-5.2, wait for rate limit to clear (like nvioc -m behavior)
        if (-not $launchModel -and $Wait -and $isDefaultModel) {
            Write-Host "OC_PROGRESS stage=preflight-wait model=$finalModelArg (waiting for rate limit to clear, up to 90s)"
            $deadline = (Get-Date).AddSeconds(90)
            $attempt = 0
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 10
                $attempt++
                $probe = Test-ModelCached -ModelId $finalModelArg -ApiKey $nvidiaApiKey -OkTtlSec 5 -ThrottledRetrySec 5
                if ($probe.ok) {
                    Write-Host "OC_PROGRESS stage=preflight-ok model=$finalModelArg label=$finalLabel (after wait)"
                    $launchModel = $finalModelArg
                    break
                } else {
                    Write-Host "OC_PROGRESS stage=preflight-wait-retry model=$finalModelArg status=$($probe.status) attempt=$attempt"
                }
            }
            if (-not $launchModel) {
                Write-Host "OC_PROGRESS stage=preflight-wait-expired model=$finalModelArg (still rate-limited after 90s, falling back)"
            }
        }

        # If still no launch model, try fallbacks ONCE (no wait loop)
        if (-not $launchModel) {
            foreach ($testId in $modelOrder) {
                if ($testId -eq $finalModelArg) { continue }
                Write-Host "OC_PROGRESS stage=preflight-probe model=$testId"
                $probe = Test-ModelCached -ModelId $testId -ApiKey $nvidiaApiKey
                if ($probe.ok) {
                    $launchModel = $testId
                    $okLabel = $modelLabels[$testId]; if (-not $okLabel) { $okLabel = $testId }
                    Write-Host "OC_PROGRESS stage=preflight-ok model=$testId label=$okLabel source=$($probe.source)"
                    break
                } else {
                    Write-Host "OC_PROGRESS stage=preflight-skip model=$testId status=$($probe.status) source=$($probe.source)"
                }
            }
        }

        if (-not $launchModel) {
            # All throttled - launch with requested model anyway, let opencode handle it
            Write-Host "OC_PROGRESS stage=all-rate-limited using=$finalModelArg (launching anyway)"
            $launchModel = $finalModelArg
        }

        if ($launchModel -ne $finalModelArg) {
            Write-Host "OC_PROGRESS stage=auto-fallback from=$finalModelArg to=$launchModel"
        }
        $finalModelArg = $launchModel
        $finalLabel = $modelLabels[$finalModelArg]
        if (-not $finalLabel) { $finalLabel = $finalModelArg }
        Write-Host "OC_PROGRESS stage=instant-launch model=$finalModelArg label=$finalLabel"
    }

    # ═══════════════════════════════════════════════════════════════════
    # OPENCODE CONFIG MANAGEMENT (same as nvioc)
    # ═══════════════════════════════════════════════════════════════════
    $configPaths = @(
        (Join-Path $env:APPDATA 'opencode\opencode.json'),
        (Join-Path $env:USERPROFILE '.config\opencode\opencode.json')
    )

    $permissionConfig = @{
        '*'         = 'allow'
        'doom_loop' = 'ask'
    }

    $instructionsPath = Join-Path $env:USERPROFILE '.config\opencode\instructions.md'
    $instructionsRel = '~/.config/opencode/instructions.md'

    $buildPromptPath = Join-Path $env:USERPROFILE '.config\opencode\build-prompt.txt'
    $buildPromptRel = '{file:~/.config/opencode/build-prompt.txt}'

    $agentConfig = @{
        build = @{
            mode       = 'primary'
            prompt     = $buildPromptRel
            steps      = 100000
            permission = @{ '*' = 'allow' }
        }
    }

    $nvidiaProviderConfig = @{
        npm     = '@ai-sdk/openai-compatible'
        name    = 'NVIDIA NGC'
        env     = @('NVIDIA_API_KEY')
        options = @{
            baseURL = 'https://integrate.api.nvidia.com/v1'
            apiKey  = $nvidiaApiKey
        }
        models  = @{
            'z-ai/glm-5.2'                        = @{ name = 'GLM-5.2 (753B MoE, best coding)' }
            'nvidia/nemotron-3-ultra-550b-a55b'   = @{ name = 'Nemotron 3 Ultra (550B flagship, best general)' }
            'nvidia/nemotron-3-super-120b-a12b'   = @{ name = 'Nemotron 3 Super (120B, strong general)' }
            'deepseek-ai/deepseek-v4-flash-0731'  = @{ name = 'DeepSeek V4 Flash (284B MoE, fast coding)' }
            'thinkingmachines/inkling'            = @{ name = 'Inkling (256-expert MoE, 1M ctx, multimodal)' }
        }
    }

    foreach ($configPath in $configPaths) {
        $configDir = Split-Path -Parent $configPath
        if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        }

        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            $config = @{
                '$schema'    = 'https://opencode.ai/config.json'
                model        = $finalModelArg
                permission   = $permissionConfig
                instructions = @($instructionsRel)
                agent        = $agentConfig
                provider     = @{ 'nvidia-nim' = $nvidiaProviderConfig }
            }
            $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
            Write-Host "OC_PROGRESS stage=config-created path=$configPath model=$finalModelArg"
        } else {
            try {
                $rawJson = Get-Content -LiteralPath $configPath -Raw
                $existing = $null
                try { $existing = $rawJson | ConvertFrom-Json } catch { }
                $merged = @{
                    '$schema'    = 'https://opencode.ai/config.json'
                    model        = $finalModelArg
                    permission   = $permissionConfig
                    instructions = @($instructionsRel)
                    agent        = $agentConfig
                    provider     = @{ 'nvidia-nim' = $nvidiaProviderConfig }
                }
                if ($existing -and $existing.plugin) {
                    $pluginArray = @()
                    foreach ($p in $existing.plugin) { $pluginArray += $p }
                    $merged['plugin'] = $pluginArray
                }
                $merged | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
                Write-Host "OC_PROGRESS stage=config-updated path=$configPath model=$finalModelArg"
            } catch {
                Write-Host "OC_PROGRESS stage=config-write-error path=$configPath msg=$($_.Exception.Message)"
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════
    # ENSURE INSTRUCTIONS FILE EXISTS
    # ═══════════════════════════════════════════════════════════════════
    if (-not (Test-Path -LiteralPath $instructionsPath -PathType Leaf)) {
        $instructionsDir = Split-Path -Parent $instructionsPath
        if (-not (Test-Path -LiteralPath $instructionsDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $instructionsDir | Out-Null
        }
        $defaultInstructions = @"
# Global Rules for OpenCode

These rules apply to ALL opencode sessions.

## CRITICAL RULES - ALWAYS FOLLOW

### Rule 1: ALWAYS test what you create
- After creating or modifying ANY file, you MUST run/test it to verify it works

### Rule 2: ALWAYS output the full path when done
- Format: FULL PATH: C:\path\to\file

### Rule 3: NEVER create generic garbage
- Always create REAL, WORKING code with proper error handling

### Rule 4: ALWAYS show real-time progress
- Show what you're doing at each step

### Rule 5: PowerShell 5 compatibility
- All scripts MUST work in PowerShell 5.1
- Avoid PS6+ features like pipe-pipe, question-question, AsHashtable
- Use try/catch blocks instead of single-pipe error handling

### Rule 6: NEVER STOP until the task is achieved
- Never stop working before the user's request is fully and verifiably achieved, no matter how complex or how long it takes.
- Do not stop after partial work. Do not stop to ask "should I continue?" - just continue.
- Keep looping: plan -> execute -> test -> fix -> verify -> continue until done.
- If something fails, diagnose it, fix it, and retry with a different approach. Never report failure as the outcome while a path forward exists.
- Only stop when the request is fully implemented AND verified working, or when the user manually stops you.
"@
        $defaultInstructions | Set-Content -LiteralPath $instructionsPath -Encoding UTF8
        Write-Host "OC_PROGRESS stage=instructions-created path=$instructionsPath"
    }

    if (-not (Test-Path -LiteralPath $buildPromptPath -PathType Leaf)) {
        $buildPromptDir = Split-Path -Parent $buildPromptPath
        if (-not (Test-Path -LiteralPath $buildPromptDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $buildPromptDir | Out-Null
        }
        $defaultBuildPrompt = @'
# Build Agent Rules

You are the build agent. You turn requests into real, working, verified code. You FINISH what you start.

## THE #1 RULE - NEVER STOP UNTIL THE GOAL IS ACHIEVED

You must NEVER stop working before the user's request is fully and verifiably achieved - no matter how
complex, how long it takes, or how many obstacles appear. This is non-negotiable and overrides everything
else except an explicit manual stop by the user (Ctrl+C / Esc / "stop").

- Do not stop after a partial implementation. Do not stop after "a good start". Do not stop to ask
  "should I continue?" - JUST CONTINUE.
- Keep working in a loop: plan -> execute -> test -> fix -> verify -> continue, until the task is done.
- If a step fails or an error appears, do NOT stop and report the failure as the outcome. Diagnose it,
  fix it, and retry. Try alternative approaches until one works.
- If you are uncertain, investigate (read files, search, web fetch, run commands) until you are certain.
- Only stop when BOTH are true: (1) the user's request is fully implemented, and (2) you have verified
  it actually works by running/testing it. If either is false, keep going.
- Break large tasks into steps and track them with the todo tool. Work through the list to completion
  without being asked.
- If a truly external blocker exists (e.g., a service is down, credentials missing), do everything you
  can to work around it first. Only if there is literally no path forward do you report the blocker -
  and say exactly what is blocking and what unblocks it.

## Non-negotiable rules

1. ALWAYS test what you create: after creating or modifying ANY file, run or test it to prove it works.
   If it doesn't work, fix it - never leave broken code behind.
2. ALWAYS report the full path of every file you create or modify. Format: FULL PATH: C:\path\to\file
3. NEVER create generic garbage: produce real, complete, working code with proper error handling.
4. ALWAYS show real-time progress: state what you are doing at each step before doing it.
5. PowerShell 5 compatibility: on Windows, scripts MUST work in Windows PowerShell 5.1 - no ??, no &&,
   no AsHashtable; use try/catch blocks.
6. Never leave broken or half-finished work. If something cannot be completed, say exactly what is
   blocking it - after exhausting every workaround.

Use any tool you need to verify your work. When the task is done, summarize exactly what changed and
how it was verified.
'@
        $defaultBuildPrompt | Set-Content -LiteralPath $buildPromptPath -Encoding UTF8
        Write-Host "OC_PROGRESS stage=build-prompt-created path=$buildPromptPath"
    }

    # ═══════════════════════════════════════════════════════════════════
    # LAUNCH OPENCODE - IMMEDIATELY (auto-heals if missing)
    # ═══════════════════════════════════════════════════════════════════
    function Resolve-OpenCode {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'npm-global\node_modules\opencode-ai\bin\opencode.exe'),
            (Join-Path $env:LOCALAPPDATA 'npm-global\node_modules\opencode-ai\node_modules\opencode-windows-x64\bin\opencode.exe'),
            (Join-Path $env:LOCALAPPDATA 'npm-global\node_modules\opencode-ai\node_modules\opencode-windows-x64-baseline\bin\opencode.exe'),
            (Join-Path $env:APPDATA 'npm\node_modules\opencode-ai\bin\opencode.exe')
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
        foreach ($shim in @('opencode.cmd', 'opencode')) {
            $cmd = Get-Command $shim -CommandType Application -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source) { return $cmd.Source }
        }
        return $null
    }

    function Test-OpenCodeWorks {
        param([string]$Path)
        try {
            $out = (& $Path '--version' 2>$null) -join " "
            if ($LASTEXITCODE -eq 0 -and $out -match '\d+\.\d+\.\d+') { return $true }
        } catch { }
        return $false
    }

    $openCodePath = Resolve-OpenCode
    if ($openCodePath -and -not (Test-OpenCodeWorks -Path $openCodePath)) {
        Write-Host "OC_PROGRESS stage=invalid-binary path=$openCodePath"
        $openCodePath = $null
    }
    if (-not $openCodePath) {
        Write-Host 'OC_PROGRESS stage=not-installed-auto-bootstrap'
        $installer = 'F:\study\Platforms\windows\functions\getoc2.ps1'
        if (Test-Path -LiteralPath $installer -PathType Leaf) {
            & $installer
            if (-not $?) { throw "glm52oc: opencode auto-install failed: $installer" }
        } else {
            throw "glm52oc: opencode auto-install script is missing: $installer"
        }
        $openCodePath = Resolve-OpenCode
        Write-Host "OC_PROGRESS stage=auto-installed path=$openCodePath"
    }
    if (-not $openCodePath) {
        throw 'glm52oc: opencode could not be installed. Check your network / npm, then run getoc2 manually.'
    }

    Write-Host "OC_PROGRESS stage=launching model=$finalModelArg label=$finalLabel"
    & $openCodePath '-m' $finalModelArg @Args
}

if ($MyInvocation.InvocationName -ne '.') {
    $__checkSwitch = $false
    $__waitSwitch = $false
    $__passArgs = @()
    foreach ($__a in $args) {
        if ($__a -eq '-Check' -or $__a -eq '-check') {
            $__checkSwitch = $true
        } elseif ($__a -eq '-Wait' -or $__a -eq '-wait') {
            $__waitSwitch = $true
        } else {
            $__passArgs += $__a
        }
    }
    if ($__checkSwitch) {
        & 'glm52oc' -Check @__passArgs
    } elseif ($__waitSwitch) {
        & 'glm52oc' -Wait @__passArgs
    } else {
        & 'glm52oc' @__passArgs
    }
}