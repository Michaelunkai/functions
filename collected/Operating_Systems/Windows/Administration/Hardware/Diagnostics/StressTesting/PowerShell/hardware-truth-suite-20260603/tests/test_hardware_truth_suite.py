from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / "a.ps1").read_text(encoding="utf-8-sig")


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def test_script_exposes_safe_modes_and_selftest():
    check("[ValidateSet('Inventory','FullStress','SelfTest')]" in SCRIPT, "missing validated modes")
    check("param(" in SCRIPT, "missing param block")
    check("$Mode" in SCRIPT, "missing Mode parameter")
    check("$DurationMinutes" in SCRIPT, "missing DurationMinutes parameter")
    check("$WhatIfOnly" in SCRIPT, "missing WhatIfOnly parameter")


def test_report_contains_fix_list_and_limitations_contract():
    check("needs_fixing_or_improving" in SCRIPT, "missing fix list output")
    check("software cannot directly inspect psu internals" in SCRIPT.lower(), "missing PSU limitation wording")
    check("ClearUnderstanding" in SCRIPT, "missing confidence/understanding marker")
    check("limitations" in SCRIPT, "missing limitations")


def test_checks_cover_requested_hardware_surface():
    required_checks = [
        "Collect-StorageHealth",
        "Collect-NetworkHealth",
        "Collect-PowerAndElectricitySignals",
        "Collect-CpuMemoryGpuHealth",
        "Collect-CableAndConnectionSignals",
        "Invoke-StressPhase",
    ]
    for check_name in required_checks:
        check(f"function {check_name}" in SCRIPT, f"missing {check_name}")


def test_realtime_progress_and_no_freeze_guards_exist():
    check("Write-Progress" in SCRIPT, "missing progress UI")
    check("Write-Heartbeat" in SCRIPT, "missing heartbeat")
    check("Start-Job" in SCRIPT or "Start-ThreadJob" in SCRIPT, "missing job isolation")
    check("TimeoutSeconds" in SCRIPT, "missing timeout guard")
    check("Assert-NotTimedOut" in SCRIPT, "timeout guard must be called by phases")
    check("Invoke-WithTimeoutJob" in SCRIPT and "Invoke-WithTimeoutJob -TimeoutSeconds" in SCRIPT, "job timeout helper must be used")
    check("timeline" in SCRIPT, "progress timeline must be persisted")


def test_outputs_machine_and_human_reports():
    check("ConvertTo-Json" in SCRIPT, "missing JSON output")
    check(".json" in SCRIPT, "missing JSON path")
    check(".md" in SCRIPT, "missing Markdown path")
    check("OneLiner" in SCRIPT, "missing one-liner output")
    check("$PSCommandPath" in SCRIPT, "one-liner must point to the actual script path, not RootDir")


if __name__ == "__main__":
    tests = [name for name in globals() if name.startswith("test_")]
    failures = []
    for name in tests:
        try:
            globals()[name]()
            print(f"PASS {name}")
        except Exception as exc:
            failures.append((name, exc))
            print(f"FAIL {name}: {exc}")
    if failures:
        raise SystemExit(1)
    print(f"{len(tests)} tests passed")
