# Claude Rules
## Rule 1

first thing to do before starting the task/s i gave you must always be this : run in powershell : mcpl; claude mcp list    . than use mcp-off <mcp> For every single MCP you know for sure isn't necessary at all for the given task you need to achieve now to make sure to maximize the necessary usage the minimum... than mcpon <mcp> For every single MCP from the list That will enhance your ability to achieve my task in the best possible way

## Rule 2

if working in F:/tovplay: always remove all files and folders expet: tovplay-backend, tovplay-frontend, claude.md , .claude, .logs, .git. everything else must be purged!!! after than inside tovplay-backend, tovplay-frontend force purge every single folder and file that isnt needed or neccery to remove all bloat!!!!

## Rule 3

For any project: preserve only essential source/config directories and files at root, then recursively purge all non-essential content (deps, builds, cache, logs, temp files, commented code, redundant files) from every directory to eliminate bloat.

## Rule 4

After every file modification, immediately verify the change actually solved the intended problem by running relevant tests/commands - don't assume success, confirm it before moving to the next task, because cascading failures from unverified changes waste exponentially more time than quick validation checks.

## Rule 5

You must provide continuous real-time progress updates at every single step - never work silently. Before touching any file, announce it. While processing, stream what you're doing. After each action, confirm completion. Show command outputs immediately. Report errors instantly. I need to see everything happening live, not summaries after the fact - treat silence as failure.

## Rule 6

If a task is simple, repetitive, or doesn't require advanced reasoning (like deleting files, renaming, copying, basic formatting, running standard commands), immediately switch to the cheapest/fastest model available - reserve high-capability models only for complex logic, architecture decisions, debugging hard problems, or novel solutions to avoid wasting tokens on trivial operations.

## Rule 7

After every error, failure, or suboptimal approach: immediately document what went wrong, why it happened, and the correct solution in `.claude/learned.md` with timestamp and context - then before starting ANY new task, review this file first to avoid repeating past mistakes, building institutional memory that compounds session-over-session making you progressively smarter and more efficient with this specific project.

## Rule 8

**NEVER ask user to do anything manually** - if you need information, search for it; if something's broken, fix it yourself; if a dependency is missing, install it; if config is needed, create it; if tests fail, debug and resolve them; work completely autonomously from problem identification through to verified solution without requesting user intervention at any step - only stop when everything works perfectly.

## Rule 9

Always verify with Puppeteer MCP** - whenever working on web UIs, APIs with web interfaces, or anything that can be visually/functionally tested in a browser, automatically use Puppeteer to verify the actual result works as intended rather than assuming code changes are correct - catch visual bugs, broken interactions, and runtime errors that static analysis misses.

## Rule 10

**NEVER stop until goal is 100% achieved and verified** - you are absolutely forbidden from ending work prematurely, marking tasks as "done" without testing, or leaving partial solutions - continue iterating, debugging, and refining until the exact goal is perfectly accomplished and you've proven it works through actual execution/testing, not assumptions - incomplete is unacceptable.

## Rule 11

**Create granular, time-balanced task lists** - break every goal into comprehensive tasks where each takes roughly equal time/effort to complete (avoid mixing 2-minute tasks with 2-hour tasks in same list) - this prevents uneven progress bars and gives accurate completion tracking - immediately mark each task with [x] the moment it's verified complete, never batch-mark multiple tasks, so progress is always real-time visible.

## Rule 12

**Predict and prevent downstream breaks before making changes** - before modifying any file, trace its usage across the entire codebase to identify all dependencies, imports, function calls, and integrations that could break, then proactively update or test those points in the same operation rather than causing cascading failures discovered later - one coordinated change that considers the whole system is infinitely better than fixing 10 broken things separately afterward.

## Rule 13

â— **servers to Claude Code** - ALWAYS use the `-s user` flag to add to global user config. After adding ANY MCP server, IMMEDIATELY verify it's actually connecting by running `claude mcp list` to confirm it appears, then test the connection works from the current directory AND at least 2 other common paths (like home directory and a project folder) to ensure it's globally accessible everywhere - never assume adding succeeded, prove the MCP is live and responding before marking complete. This ensures: - Uses -s user flag for global config - Verifies server appears in claude mcp list - Tests connection from multiple paths - Confirms MCP is actually responding, not just "added" â— When adding MCP servers to Claude Code, ALWAYS use the `-s user` flag to add to global user config, after adding ANY MCP server IMMEDIATELY verify it's actually connecting by running `claude mcp list` to confirm it appears, then test the connection works from the current directory AND at least 2 other common paths (like home directory and a project folder) to ensure it's globally accessible everywhere, never assume adding succeeded, prove the MCP is live and responding before marking complete, this ensures uses -s user flag for global config, verifies server appears in claude mcp list, tests connection from multiple paths, confirms MCP is actually responding not just added, AND whenever adding MCP servers you MUST use the on-demand loading system to ensure 70-80% RAM savings by: (1) adding the server using command: claude mcp add --scope user <server-name> -- <command>, (2) IMMEDIATELY editing the dispatcher mapping file at F:\study\AI_ML\AI_and_Machine_Learning\Artificial_In telligence\MCP\claudecode\mcp_mapping.json and adding an entry with relevant keywords for the new server in format: {"mappings": {"server-name": ["keyword1", "keyword2", "common phrases that indicate this server"]}}, (3) verifying registration by running: python F:\study\AI_ML\AI_and_Machine_Le arning\Artificial_Intelligence\MCP\claudecode\mcp_di spatcher_universal.py --status and confirming total_discovered count increased, (4) informing me that the server is added with on-demand loading active and listing the keywords registered, this ensures all MCP servers load ONLY when needed rather than at startup maintaining the optimized RAM usage across all servers including future additions.

## Rule 14

Optimize for Minimal File Changes** - Before modifying anything, check if the goal can be achieved by changing fewer files, using existing utilities, or leveraging built-in features rather than adding new code - every new file/dependency is future maintenance debt, so always ask "can I solve this by modifying 1 file instead of 3, or using what already exists instead of building new?"

## Rule 15

F:/tovplay Zero-Touch Development Rule** - When working in F:/tovplay specifically, achieve all tasks WITHOUT modifying tovplay-backend or tovplay-frontend codebases whenever possible - prioritize solutions through: server configurations, environment variables, reverse proxy rules, middleware, API gateway settings, database changes, Docker configs, nginx/Apache rules, or external scripts - the tovplay team should notice ZERO code differences unless absolutely impossible, and even then make the absolute minimum surgical changes required - infrastructure solutions always beat code modifications for stealth deployments in this project.

## Rule 16

**Proactive Error Prevention and Edge Case Handling** - Before implementing any solution, mentally simulate failure scenarios, edge cases, and unusual inputs that could break it - then build defensive handling directly into the first implementation rather than waiting for errors to surface - ask "what if the file doesn't exist?", "what if the API times out?", "what if the input is empty/null/malformed?" and code for these scenarios upfront, because preventing 10 bugs costs less than debugging them later.

## Rule 17

**Aggressive Caching and Performance Optimization** - Whenever fetching, processing, or computing anything that could be reused, immediately implement intelligent caching with invalidation strategies - never repeat expensive operations (API calls, file parsing, complex calculations) when results can be cached - measure performance before and after every significant change using actual timing/profiling, and if something takes >100ms that runs frequently, optimize it immediately because slow accumulates into unusable.

## Rule 18

*whenever i ask you do do something related to claude code settings achieve it with this 2 files (without unneccerly removing things already there!!!!):  "C:\Users\micha\.claude.json"  "C:\Users\micha\.claude\settings.json"

## Rule 19

## Trigger: "fix"


