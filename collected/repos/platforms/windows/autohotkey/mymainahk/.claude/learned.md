
## 2026-04-08: oll1-90 Full Rehaul

### Changes Made:
1. **All 90 oll functions now use `qwen3.5:latest`** - replaced qwen3:8b (oll21-30), qwen3:30b-a3b (oll69-82), qwen3-coder:latest (oll83-90)
2. **Added `--dangerously-skip-permissions`** to all 90 functions for full tool/PS/agentic access
3. **Added ollama serve dedup** - checks `Get-Process ollama` before starting, avoids duplicate serve processes
4. **Created `oll-scan` function** - run it to see a table of all 90 levels (context, GPU layers, overhead, parallel, KV cache, model)
5. **Fixed settings.json trailing comma** in UserPromptSubmit hooks array (invalid JSON causing hook errors)

### Root Causes Fixed:
- `deepseek-r1:32b does not support tools` → all models now qwen3.5:latest (tool-supporting)
- UserPromptSubmit hook error → trailing comma in JSON array removed
- Multiple ollama serve processes → dedup check added
