$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'Invoke-DriverMega.ps1'
. $scriptPath

Describe 'DriverMega version helpers' {
    It 'compares dotted versions numerically' {
        Compare-DriverMegaVersion -Left '11.27.50.0920' -Right '11.26.50.2025' | Should Be 1
        Compare-DriverMegaVersion -Left '3.1.0.1571' -Right '3.1.0.1571' | Should Be 0
        Compare-DriverMegaVersion -Left '1.3.8.018' -Right '1.3.8.21' | Should Be -1
    }

    It 'compares Gigabyte BIOS branches safely' {
        Compare-DriverMegaBiosVersion -Left 'FB1a' -Right 'FA9' | Should Be 1
        Compare-DriverMegaBiosVersion -Left 'FA8' -Right 'FB1a' | Should Be -1
        Compare-DriverMegaBiosVersion -Left 'FB1A' -Right 'FB1a' | Should Be 0
    }
}

Describe 'DriverMega candidate resolution' {
    It 'blocks downgrade candidates' {
        $candidate = New-DriverMegaCandidate -Id 'bios' -Provider 'Gigabyte' -Category 'Firmware' -Title 'BIOS' `
            -InstalledVersion 'FB1a' -CandidateVersion 'FA9' -Channel 'test' -SourceUrl $null -PackagePath $null -PackageUrl $null `
            -DriverIdentity 'System Firmware' -Classification 'Firmware' -InstallMode 'manual-confirmation' -Revision '1.1'

        $resolved = Resolve-DriverMegaVersionState -Candidate $candidate -UseBiosComparison
        $resolved.State | Should Be 'blocked_downgrade'
        $resolved.Action | Should Be 'defer'
    }

    It 'marks newer dotted versions as update available' {
        $candidate = New-DriverMegaCandidate -Id 'lan' -Provider 'Gigabyte' -Category 'Driver' -Title 'LAN' `
            -InstalledVersion '11.21.0903.2024' -CandidateVersion '11.26.50.2025' -Channel 'test' -SourceUrl $null -PackagePath $null -PackageUrl $null `
            -DriverIdentity 'NIC' -Classification 'Net' -InstallMode 'pnputil-inf' -Revision '1.1'

        $resolved = Resolve-DriverMegaVersionState -Candidate $candidate
        $resolved.State | Should Be 'update_available'
        $resolved.Action | Should Be 'apply'
    }
}
