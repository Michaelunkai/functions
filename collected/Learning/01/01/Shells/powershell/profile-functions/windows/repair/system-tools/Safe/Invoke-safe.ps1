$__extractedFunctionName = 'Safe'
$__extractedCommandName = 'Safe'
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

function Safe {
    param (
        [string]$SourceStudy = "F:\\study",
        [string]$SourceBackup = "F:\\backup",
        [string]$TargetDrive = "F:"
    )
    # Function to get total used space on the drive in GB
    function Get-UsedSpace {
        param (
            [string]$DriveLetter
        )
        $driveInfo = Get-PSDrive -Name $DriveLetter
        if ($driveInfo) {
            $usedSpace = $driveInfo.Used / 1GB
            [math]::Round($usedSpace, 2)
        } else {
            0
        }
    }
    # Start time tracking
    $start = Get-Date
    # Define target paths
    $TargetStudy = Join-Path -Path $TargetDrive -ChildPath "study"
    $TargetBackup = Join-Path -Path $TargetDrive -ChildPath "backup"
    # Sync function with used space monitoring
    function Sync-WithSpaceMonitoring {
        param (
            [string]$SourcePath,
            [string]$TargetPath
        )
        Write-Output "Synchronizing $SourcePath with $TargetPath..." -ForegroundColor Yellow
        if (Test-Path $SourcePath) {
            # Start a background job to monitor used space on the target drive
            $monitorJob = Start-Job -ScriptBlock {
                while ($true) {
                    $usedSpace = Get-UsedSpace -DriveLetter $Using:TargetDrive
                    Write-Output "Total used space on $Using:TargetDrive: $usedSpace GB" -ForegroundColor Cyan
                    Start-Sleep -Seconds 10
                }
            }
            # Run robocopy to sync files
            robocopy $SourcePath $TargetPath /MIR /E /R:2 /W:2 /NFL /NDL /NP /MT
            $exitCode = $LASTEXITCODE
            # Stop the monitoring job once sync completes
            Stop-Job -Job $monitorJob
            Remove-Job -Job $monitorJob
            # Check robocopy result
            if ($exitCode -lt 8) {
                Write-Output "Synchronized $SourcePath with $TargetPath successfully." -ForegroundColor Green
            } else {
                Write-Output "Error synchronizing $SourcePath with $TargetPath." -ForegroundColor Red
            }
        } else {
            Write-Output "Source folder $SourcePath does not exist. Skipping synchronization." -ForegroundColor Red
        }
    }
    # Sync study folder
    Sync-WithSpaceMonitoring -SourcePath $SourceStudy -TargetPath $TargetStudy
    # Sync backup folder
    Sync-WithSpaceMonitoring -SourcePath $SourceBackup -TargetPath $TargetBackup
    # End time tracking
    $end = Get-Date
    $duration = $end - $start
    Write-Output "Operation completed in $duration." -ForegroundColor Green
}

& $__extractedCommandName @__extractedArgs