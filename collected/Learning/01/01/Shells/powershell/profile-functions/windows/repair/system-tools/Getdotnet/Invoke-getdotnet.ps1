$__extractedFunctionName = 'getdotnet'
$__extractedCommandName = 'getdotnet'
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

function getdotnet {
    Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -All -NoRestart
    dism /online /enable-feature /featurename:NetFx3 /all /norestart
    Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile dotnet-install.ps1
    foreach ($v in 1..5) {
        try {
            ./dotnet-install.ps1 -Version "$v.0.0" -InstallDir "C:\dotnet\$v" -Architecture x64 -NoPath
        } catch {
            Write-Output "? Failed to install .NET SDK $v.0.0"
        }
    }
    $packages = @(
        "Microsoft.NetFramework.4.8.SDK",
        "Microsoft.NetFramework.4.8.TargetingPack",
        "Microsoft.DotNet.SDK.6",
        "Microsoft.DotNet.SDK.7",
        "Microsoft.DotNet.SDK.8",
        "Microsoft.DotNet.Runtime.6",
        "Microsoft.DotNet.Runtime.7",
        "Microsoft.DotNet.Runtime.8",
        "Microsoft.WindowsDesktop.Runtime.6",
        "Microsoft.WindowsDesktop.Runtime.7",
        "Microsoft.WindowsDesktop.Runtime.8",
        "Microsoft.AspNetCore.6",
        "Microsoft.AspNetCore.7",
        "Microsoft.AspNetCore.8",
        "Microsoft.VisualStudio.2022.BuildTools",
        "Microsoft.VCRedist.2015+.x64",
        "Microsoft.VCRedist.2013.x64",
        "Microsoft.VCRedist.2012.x64",
        "Microsoft.VCRedist.2010.x64",
        "Microsoft.VCRedist.2008.x64",
        "Microsoft.VCRedist.2005.x64",
        "Microsoft.DirectX",
        "OpenAL.OpenAL",
        "Microsoft.Xna.Framework.4.0",
        "physx",
        "VulkanSDK"
    )
    foreach ($pkg in $packages) {
        try {
            winget install $pkg --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Output "? Failed to install $pkg"
        }
    }
    dotnet --list-sdks
    dotnet --list-runtimes
}

& $__extractedCommandName @__extractedArgs