$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'repair-upgrade4.ps1')

Describe 'Get-LanguageFallbackChain' {
    It 'normalizes and deduplicates fallback languages' {
        $result = Get-LanguageFallbackChain `
            -InternationalLanguages @('en_US', 'he_il') `
            -CurrentUiLanguages @('en-US', 'fr-fr') `
            -RegistryLanguages @('HE-IL', '', $null, 'fr-FR')

        $result.Count | Should Be 3
        $result[0] | Should Be 'en-US'
        $result[1] | Should Be 'he-IL'
        $result[2] | Should Be 'fr-FR'
    }
}

Describe 'Convert-LcidHexToLanguage' {
    It 'converts Windows NLS hex LCIDs into normalized language names' {
        Convert-LcidHexToLanguage '0409' | Should Be 'en-US'
    }
}

Describe 'Resolve-ImageSelection' {
    It 'selects the matching Pro image from a multi-edition catalog' {
        $system = [pscustomobject]@{
            EditionKey = 'pro'
            EditionId  = 'Professional'
        }

        $images = @(
            [pscustomobject]@{ Index = 1; Name = 'Windows 11 Home'; Description = 'Windows 11 Home' },
            [pscustomobject]@{ Index = 6; Name = 'Windows 11 Pro'; Description = 'Windows 11 Pro' }
        )

        $result = Resolve-ImageSelection -SystemProfile $system -Images $images
        $result.Resolved | Should Be $true
        $result.Ambiguous | Should Be $false
        $result.SelectedImageIndex | Should Be 6
        $result.SelectedImageName | Should Be 'Windows 11 Pro'
    }

    It 'flags ambiguous matching when no quiet-safe edition match exists' {
        $system = [pscustomobject]@{
            EditionKey = 'pro'
            EditionId  = 'Professional'
        }

        $images = @(
            [pscustomobject]@{ Index = 1; Name = 'Windows 11 Home'; Description = 'Windows 11 Home' },
            [pscustomobject]@{ Index = 2; Name = 'Windows 11 Education'; Description = 'Windows 11 Education' }
        )

        $result = Resolve-ImageSelection -SystemProfile $system -Images $images
        $result.Resolved | Should Be $false
        $result.Ambiguous | Should Be $true
        $result.SelectedImageIndex | Should Be $null
    }
}

Describe 'Get-MediaEvaluation' {
    It 'rejects install media that is older than the current OS build' {
        $system = [pscustomobject]@{
            Build        = 26200
            Architecture = 'x64'
            Languages    = @('en-US')
            EditionKey   = 'pro'
            EditionId    = 'Professional'
        }

        $sourceMetadata = [pscustomobject]@{
            Source           = [pscustomobject]@{ Kind = 'IsoFile'; Path = 'C:\Temp\old.iso'; Reason = 'test'; Priority = 1 }
            Build            = 22631
            Version          = '10.0.22631.1'
            Architecture     = 'x64'
            DefaultLanguage  = 'en-US'
            Images           = @([pscustomobject]@{ Index = 6; Name = 'Windows 11 Pro'; Description = 'Windows 11 Pro' })
            LastWriteTimeUtc = [datetime]::UtcNow
        }

        $result = Get-MediaEvaluation -SystemProfile $system -SourceMetadata $sourceMetadata
        $result.BuildCompatible | Should Be $false
        $result.Compatible | Should Be $false
    }
}

Describe 'Select-BestEvaluation' {
    It 'prefers the lower-priority-number requested source over a newer cache when compatibility is equal' {
        $olderRequested = [pscustomobject]@{
            Compatible      = $true
            BuildCompatible = $true
            BuildDelta      = 0
            ImageSelection  = [pscustomobject]@{ Resolved = $true }
            Source          = [pscustomobject]@{ Priority = 1; Path = 'E:\isos\Windows.iso' }
            SourceMetadata  = [pscustomobject]@{ LastWriteTimeUtc = [datetime]'2026-04-01T00:00:00Z' }
        }

        $newerCache = [pscustomobject]@{
            Compatible      = $true
            BuildCompatible = $true
            BuildDelta      = 0
            ImageSelection  = [pscustomobject]@{ Resolved = $true }
            Source          = [pscustomobject]@{ Priority = 2; Path = 'C:\WinISO\Windows.iso' }
            SourceMetadata  = [pscustomobject]@{ LastWriteTimeUtc = [datetime]'2026-04-02T00:00:00Z' }
        }

        $result = Select-BestEvaluation -Evaluations @($newerCache, $olderRequested) -RequireCompatible
        $result.Source.Path | Should Be 'E:\isos\Windows.iso'
    }
}

Describe 'New-RunArtifactPaths' {
    It 'stores run artifacts outside the extract directory tree' {
        $startedAt = [datetime]'2026-04-30T12:41:12'
        $paths = New-RunArtifactPaths -StartedAt $startedAt -ExtractDir 'C:\WinSetup'

        $paths.RunId | Should Be '20260430-124112'
        $paths.RunDirectory | Should Match '^C:\\ProgramData\\WinSetup\\Logs\\20260430-124112$'
        $paths.RunDirectory.StartsWith('C:\WinSetup', [System.StringComparison]::OrdinalIgnoreCase) | Should Be $false
        $paths.TranscriptPath | Should Match 'transcript\.log$'
        $paths.CopyLogsPath | Should Match 'setup-copylogs\.zip$'
    }
}

Describe 'Get-ParentDirectoryPath' {
    It 'returns the parent directory without relying on Split-Path LiteralPath Parent combinations' {
        Get-ParentDirectoryPath -Path 'C:\WinISO\Windows.iso' | Should Be 'C:\WinISO'
    }
}

Describe 'New-SetupArgumentList' {
    It 'builds the fast launch path with visible setup progress and Windows 11 requirements' {
        $arguments = New-SetupArgumentList -Mode Fast -ImageIndex 6 -CopyLogsPath 'C:\ProgramData\WinSetup\Logs\setup-copylogs.zip' -BitLockerAlwaysSuspend -DynamicUpdate Disable
        $joined = $arguments -join ' '

        $joined | Should Not Match '/Quiet'
        $joined | Should Match '/EULA Accept'
        $joined | Should Match '/ImageIndex 6'
        $joined | Should Match '/CopyLogs C:\\ProgramData\\WinSetup\\Logs\\setup-copylogs.zip'
        $joined | Should Match '/DynamicUpdate Disable'
        $joined | Should Match '/BitLocker AlwaysSuspend'
    }

    It 'builds the scan-only deep path with quiet mode and no reboot' {
        $arguments = New-SetupArgumentList -Mode Deep -ScanOnly -NoReboot -Quiet -ImageIndex 6 -CopyLogsPath 'C:\ProgramData\WinSetup\Logs\setup-copylogs.zip' -DynamicUpdate NoDrivers
        $joined = $arguments -join ' '

        $joined | Should Match '/Quiet'
        $joined | Should Match '/NoReboot'
        $joined | Should Match '/Compat ScanOnly'
        $joined | Should Match '/Compat IgnoreWarning'
        $joined | Should Match '/DynamicUpdate NoDrivers'
    }
}

Describe 'Get-SetupExitCodeMeaning' {
    It 'decodes known setup compatibility blocks' {
        $code = Convert-HexToSignedInt 'C1900208'
        (Get-SetupExitCodeMeaning -ExitCode $code) | Should Match 'Blocking app or driver'
    }
}

Describe 'Get-PendingFileRenameCount' {
    It 'returns zero when the registry object is present but the property is missing' {
        Mock Get-ItemProperty { [pscustomobject]@{ Other = 'value' } }

        Get-PendingFileRenameCount | Should Be 0
    }

    It 'returns the number of pending rename entries when the property exists' {
        Mock Get-ItemProperty { [pscustomobject]@{ PendingFileRenameOperations = @('a', 'b', 'c') } }

        Get-PendingFileRenameCount | Should Be 3
    }
}

Describe 'Test-PortableExecutableFile' {
    It 'returns true for a minimally valid PE header' {
        $path = Join-Path $env:TEMP 'repair-upgrade4-valid-pe.bin'
        try {
            $bytes = New-Object byte[] 128
            $bytes[0] = 0x4D
            $bytes[1] = 0x5A
            [BitConverter]::GetBytes([int]64).CopyTo($bytes, 60)
            $bytes[64] = 0x50
            $bytes[65] = 0x45
            $bytes[66] = 0x00
            $bytes[67] = 0x00
            [BitConverter]::GetBytes([UInt16]0x8664).CopyTo($bytes, 68)
            [System.IO.File]::WriteAllBytes($path, $bytes)

            Test-PortableExecutableFile -Path $path | Should Be $true
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns false for a zero-filled file with a DLL extension' {
        $path = Join-Path $env:TEMP 'repair-upgrade4-invalid-pe.dll'
        try {
            [System.IO.File]::WriteAllBytes($path, (New-Object byte[] 256))

            Test-PortableExecutableFile -Path $path | Should Be $false
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-ShouldEscalateToDeepMode' {
    It 'stays on the fast path when no escalation signal exists' {
        $result = Test-ShouldEscalateToDeepMode -RequestedMode Fast
        $result.ShouldEscalate | Should Be $false
        $result.Reasons.Count | Should Be 0
    }

    It 'escalates when prior Panther logs exist' {
        $result = Test-ShouldEscalateToDeepMode -RequestedMode Fast -HasPriorPantherLogs:$true
        $result.ShouldEscalate | Should Be $true
        $result.Reasons.Count | Should Be 1
    }
}

Describe 'Get-ExecutionPlan' {
    It 'keeps a clean preflight-only fast run on the non-deep path' {
        $plan = Get-ExecutionPlan -RequestedMode Fast -PreflightOnly
        $plan.UseDeepPath | Should Be $false
        $plan.RunCompatScan | Should Be $false
        $plan.RunDeepServicing | Should Be $false
        $plan.LaunchUpgrade | Should Be $false
        $plan.CanLaunchUpgrade | Should Be $true
    }

    It 'selects compat scan and deep servicing in deep mode even when preflight-only' {
        $plan = Get-ExecutionPlan -RequestedMode Deep -PreflightOnly
        $plan.UseDeepPath | Should Be $true
        $plan.RunCompatScan | Should Be $true
        $plan.RunDeepServicing | Should Be $true
        $plan.LaunchUpgrade | Should Be $false
    }

    It 'blocks setup launch when media matching remains ambiguous' {
        $plan = Get-ExecutionPlan -RequestedMode Fast -MediaMatchingAmbiguous:$true
        $plan.UseDeepPath | Should Be $true
        $plan.CanLaunchUpgrade | Should Be $false
    }
}
