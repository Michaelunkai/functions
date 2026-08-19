$protectedDataType = [System.Type]::GetType(
    'System.Security.Cryptography.ProtectedData, System.Security',
    $false
)
if ($null -eq $protectedDataType) {
    Add-Type -AssemblyName System.Security
}

$script:AgentControlCredentialEntropy = [System.Text.Encoding]::UTF8.GetBytes(
    'AgentControl.WindowsAdapter.OwnerToken.v1'
)
$script:AgentControlHookSecretEntropy = [System.Text.Encoding]::UTF8.GetBytes(
    'AgentControl.WindowsAdapter.HookSecret.v1'
)

function Get-AgentControlCredentialPath {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    return Join-Path $Root 'owner-token.dpapi'
}

function Write-AgentControlOwnerToken {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Token,
        [string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl')
    )

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $path = Get-AgentControlCredentialPath -Root $Root
    $temporary = "$path.$PID.tmp"
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Token)
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $script:AgentControlCredentialEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.IO.File]::WriteAllBytes($temporary, $protectedBytes)
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally {
        if ($plainBytes) {
            [System.Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Read-AgentControlOwnerToken {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    $path = Get-AgentControlCredentialPath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    $protectedBytes = [System.IO.File]::ReadAllBytes($path)
    $plainBytes = $null
    try {
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $script:AgentControlCredentialEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } finally {
        if ($plainBytes) {
            [System.Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
    }
}

function Remove-AgentControlOwnerToken {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    Remove-Item -LiteralPath (Get-AgentControlCredentialPath -Root $Root) `
        -Force -ErrorAction SilentlyContinue
}

function Get-AgentControlHookSecretPath {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    return Join-Path $Root 'hook-secret.dpapi'
}

function Write-AgentControlHookSecret {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Secret,
        [string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl')
    )

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $path = Get-AgentControlHookSecretPath -Root $Root
    $temporary = "$path.$PID.tmp"
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    try {
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $script:AgentControlHookSecretEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.IO.File]::WriteAllBytes($temporary, $protectedBytes)
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally {
        if ($plainBytes) {
            [System.Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Read-AgentControlHookSecret {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    $path = Get-AgentControlHookSecretPath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    $protectedBytes = [System.IO.File]::ReadAllBytes($path)
    $plainBytes = $null
    try {
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes,
            $script:AgentControlHookSecretEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } finally {
        if ($plainBytes) {
            [System.Array]::Clear($plainBytes, 0, $plainBytes.Length)
        }
    }
}

function Initialize-AgentControlHookSecret {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    $existing = Read-AgentControlHookSecret -Root $Root
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return $existing
    }

    $secretBytes = New-Object byte[] 32
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($secretBytes)
        $secret = [Convert]::ToBase64String($secretBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        Write-AgentControlHookSecret -Secret $secret -Root $Root
        return $secret
    } finally {
        $random.Dispose()
        [System.Array]::Clear($secretBytes, 0, $secretBytes.Length)
    }
}

function Remove-AgentControlHookSecret {
    param([string]$Root = (Join-Path $env:LOCALAPPDATA 'AgentControl'))

    Remove-Item -LiteralPath (Get-AgentControlHookSecretPath -Root $Root) `
        -Force -ErrorAction SilentlyContinue
}
