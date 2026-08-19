@{
    Settings = @{
        StartupOpenClawCheckTimeoutSec = 12
        VerifyOpenClawCheckTimeoutSec = 45
        SnapshotTaskNames = @(
            'Autorun_current_ahk',
            'ClawdBotTray',
            'OpenSpeedy_Tray',
            'Murmure_Tray'
        )
    }

    RequiredLaunchPoints = @{
        AhkScript = 'F:\study\Platforms\windows\autohotkey\mymainahk\current.ahk'
        AutoHotkeyExe = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
        FullScreenSnipExe = 'F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe'
        OpenSpeedyExe = 'C:\Users\micha\AppData\Local\Microsoft\WinGet\Packages\Game1024.OpenSpeedy_Microsoft.Winget.Source_8wekyb3d8bbwe\Speedy.exe'
        OpenSpeedyVbs = 'C:\Users\micha\.claude\scripts\openspeedy-silent.vbs'
        MurmureExe = 'C:\Program Files\murmure\murmure.exe'
        MurmureVbs = 'C:\Users\micha\.claude\scripts\murmure-silent.vbs'
        PhoneLinkAppId = 'Microsoft.YourPhone_8wekyb3d8bbwe!App'
        PhoneLinkPackageFamilyName = 'Microsoft.YourPhone_8wekyb3d8bbwe'
        PhoneLinkStartupTaskId = 'YourPhone.Start'
        CrossDevicePackageFamilyName = 'MicrosoftWindows.CrossDevice_cw5n1h2txyewy'
        ClawdBotTrayVbs = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\ClawdBot\ClawdbotTray.vbs'
        ClawdBotManagerExe = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\ClawdBot\ClawdBotManager.exe'
        ClawdBotConfigPath = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\openclaw-home\openclaw.json'
        ClawdBotRestartScript = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\ProfileFunctions\Restart-OpenclawGateway.ps1'
        TelegramDmScope = 'per-account-channel-peer'
    }

    RequiredRegistryRun = @(
        @{ Name = 'FullScreenSnip'; Command = '"F:\study\Platforms\windows\snipping\SnipToClipBoard\FullScreenSnip.exe"'; Hive = 'HKCU' }
    )

    RequiredScheduledTasks = @(
        @{ Name = 'Autorun_current_ahk'; Execute = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'; Arguments = '"F:\study\Platforms\windows\autohotkey\mymainahk\current.ahk"'; Description = 'current.ahk hidden launcher at logon' },
        @{ Name = 'ClawdBotTray'; Execute = 'C:\Windows\System32\wscript.exe'; Arguments = '//B //Nologo "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\ClawdBot\ClawdbotTray.vbs"'; Description = 'ClawdBot tray hidden launcher at logon' },
        @{ Name = 'OpenSpeedy_Tray'; Execute = 'C:\Windows\System32\wscript.exe'; Arguments = '"C:\Users\micha\.claude\scripts\openspeedy-silent.vbs"'; Description = 'OpenSpeedy tray hidden launcher at logon' },
        @{ Name = 'Murmure_Tray'; Execute = 'C:\Windows\System32\wscript.exe'; Arguments = '"C:\Users\micha\.claude\scripts\murmure-silent.vbs"'; Description = 'Murmure tray hidden launcher at logon' }
    )

    RequiredAppStartupTasks = @(
        @{ Name = 'PhoneLinkNative'; PackageFamilyName = 'Microsoft.YourPhone_8wekyb3d8bbwe'; TaskId = 'YourPhone.Start'; EnabledState = 2 },
        @{ Name = 'CrossDeviceNative'; PackageFamilyName = 'MicrosoftWindows.CrossDevice_cw5n1h2txyewy'; TaskId = 'CrossDevice.Start'; EnabledState = 2 }
    )

    # These names are allowed to remain enabled. Anything else on supported
    # startup surfaces is quarantined/disabled with a snapshot before mutation.
    ProtectedNames = @()

    # Exact opt-in rules only. Keep empty until a specific name/path is audited.
    # Unknown entries are reported and kept.
    ExplicitDisableRules = @()

    # Exact opt-in delay rules only. This safe build reports delay candidates but
    # does not migrate launch points automatically.
    DelayRules = @()
}
