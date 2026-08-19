#!/usr/bin/env python3
"""Focused tests for the Python runtime embedded in setup_agent.ps1."""

from __future__ import annotations

import ast
from pathlib import Path
import re
import unittest


SETUP_SCRIPT = Path(__file__).resolve().parents[1] / "setup_agent.ps1"


def load_agent_source() -> str:
    setup_text = SETUP_SCRIPT.read_text(encoding="utf-8-sig")
    marker = "$agent = @'\n"
    start = setup_text.index(marker) + len(marker)
    end = setup_text.index("\n'@", start)
    return setup_text[start:end]


def load_intent_detector():
    agent_source = load_agent_source()
    module = ast.parse(agent_source)
    selected = []
    for node in module.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name)
            and target.id == "PREMATURE_ACTION_INTENT_PATTERNS"
            for target in node.targets
        ):
            selected.append(node)
        if (
            isinstance(node, ast.FunctionDef)
            and node.name == "_is_incomplete_action_intent"
        ):
            selected.append(node)
    namespace = {"re": re}
    exec(compile(ast.Module(selected, type_ignores=[]), str(SETUP_SCRIPT), "exec"), namespace)
    return namespace["_is_incomplete_action_intent"]


class AgentRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.is_incomplete_action_intent = staticmethod(load_intent_detector())

    def test_detects_observed_future_write_phrase(self) -> None:
        self.assertTrue(
            self.is_incomplete_action_intent(
                "Good. Now let me write the proof.json file with all "
                "the required information:"
            )
        )

    def test_does_not_reject_non_action_conversation(self) -> None:
        self.assertFalse(
            self.is_incomplete_action_intent(
                "The operation is complete. Let me know what you want to do next."
            )
        )

    def test_process_lifecycle_tools_are_embedded(self) -> None:
        source = load_agent_source()
        module = ast.parse(source)
        function_names = {
            node.name for node in module.body if isinstance(node, ast.FunctionDef)
        }
        self.assertIn("_process_is_running", function_names)
        self.assertIn("start_process", function_names)
        self.assertIn("stop_process", function_names)
        self.assertIn('"name": "start_process"', source)
        self.assertIn('"name": "stop_process"', source)
        self.assertIn('"start_process": start_process', source)
        self.assertIn('"stop_process": stop_process', source)
        self.assertIn("{FREE_TCP_PORT}", source)
        self.assertIn("_normalize_process_arguments", source)

    def test_download_install_and_unbounded_default_are_embedded(self) -> None:
        source = load_agent_source()
        self.assertIn("def install_windows_package(", source)
        self.assertIn("def download_and_install(", source)
        self.assertIn('"download_and_install": download_and_install', source)
        self.assertIn("default=0", source)
        self.assertNotIn("max(2, args.max_turns)", source)

    def test_progress_and_bounded_recovery_are_embedded(self) -> None:
        source = load_agent_source()
        self.assertIn("class ProgressReporter:", source)
        self.assertIn("PROGRESS_HEARTBEAT_SECONDS = 10", source)
        self.assertIn("MAX_CONSECUTIVE_MODEL_FAILURES = 12", source)
        self.assertIn("MAX_CONSECUTIVE_NO_PROGRESS_CYCLES = 12", source)
        self.assertIn('reporter.event("model", "waiting-response"', source)
        self.assertIn("execute_tool(name, arguments, reporter=reporter)", source)
        self.assertIn("TASK_STATUS: MODEL_RESPONSE_FAILURE_LIMIT", source)
        self.assertIn("TASK_STATUS: NO_PROGRESS_LIMIT", source)


if __name__ == "__main__":
    unittest.main()
