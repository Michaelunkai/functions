$__extractedFunctionName = 'ccfun'
$__extractedCommandName = 'ccfun'
$__extractedScriptPath = $PSCommandPath
$__extractedArgs = @($args)
if ($__extractedArgs -contains '-SelfTest') {
    [pscustomobject]@{
        Function = $__extractedFunctionName
        Command = $__extractedCommandName
        Script = $__extractedScriptPath
        Exists = [bool](Test-Path -LiteralPath $__extractedScriptPath)
        Mode = 'SelfTest'
    } | ConvertTo-Json -Compress
    return
}

function ccfun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WrapperFunctionName
    )

    $profilePath = $PROFILE
    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-Error "Profile not found at $profilePath"
        return
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Write-Error "Unable to parse $profilePath due to syntax errors."
        return
    }

    $functionNodes = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    if (-not $functionNodes) {
        Write-Warning "No functions defined in $profilePath."
        return
    }

    $functionMap = [System.Collections.Generic.Dictionary[string,System.Management.Automation.Language.FunctionDefinitionAst]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($node in $functionNodes) {
        if (-not $functionMap.ContainsKey($node.Name)) {
            $functionMap[$node.Name] = $node
        }
    }

    if (-not $functionMap.ContainsKey($WrapperFunctionName)) {
        Write-Warning "Function '$WrapperFunctionName' not found in $profilePath."
        return
    }

    $targetFunction = $functionMap[$WrapperFunctionName]
    if (-not $targetFunction.Body) {
        Write-Warning "Function '$WrapperFunctionName' has no body to inspect."
        return
    }

    $commandAsts = $targetFunction.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $orderedNames = @()

    foreach ($commandAst in $commandAsts) {
        $cmdName = $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($cmdName)) {
            continue
        }
        if ($functionMap.ContainsKey($cmdName) -and $seen.Add($cmdName)) {
            $orderedNames += $cmdName
        }
    }

    if ($orderedNames.Count -eq 0) {
        Write-Host "No nested functions were detected inside '$WrapperFunctionName'." -ForegroundColor Yellow
        return
    }

    foreach ($name in $orderedNames) {
        $funcAst = $functionMap[$name]
        Write-Host "`n===== $name =====" -ForegroundColor Cyan
        $funcAst.Extent.Text.TrimEnd() | Write-Output
    }
}

& $__extractedCommandName @__extractedArgs