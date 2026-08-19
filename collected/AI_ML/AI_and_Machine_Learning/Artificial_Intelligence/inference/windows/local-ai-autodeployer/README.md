# Windows Local AI Auto-Deployer

Standalone PowerShell 5.1 automation for provisioning a self-contained Windows 11 local AI inference sandbox. It dynamically queries live public APIs for the current llama.cpp Windows release and GGUF-compatible open-weight model candidates, fits the selected model to the host hardware, tunes runtime flags, configures the firewall, validates the OpenAI-compatible endpoint, and prints the two permanent manifest paths.

## Run

Use an elevated Windows PowerShell 5.1 session:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\Install-Or-Update-LocalAI.ps1" -Auto
```

## Start Existing Runtime

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\Open-LocalAIInteractive.ps1"
```

Non-interactive proof mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\Open-LocalAIInteractive.ps1" -Once "Reply with one sentence confirming interactive local AI works."
```

## Safe Checks

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\tests\SelfTest.ps1"
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\Test-LocalAI.ps1" -DiscoveryOnly -NoNetworkMutation
```

## Full Cleanup

Run from an elevated Windows PowerShell 5.1 session:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\inference\windows\local-ai-autodeployer\Undo-LocalAIAutodeployer.ps1"
```

## Notes

- The project is self-contained under this folder and does not use global package managers.
- Full install requires internet access and enough free disk space for the selected backend and model.
- Firewall, power plan, and port changes require elevation. The scripts fail fast instead of prompting.
- Existing unrelated listeners on port 8080 are not killed.
