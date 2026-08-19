#!/usr/bin/env python3
"""Focused regression tests for the complex acceptance harness."""

from __future__ import annotations

import importlib.util
import base64
import hashlib
import json
import re
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock


HARNESS_PATH = Path(__file__).with_name("Run-ComplexAcceptance.py")


def load_harness():
    spec = importlib.util.spec_from_file_location("complex_acceptance_harness", HARNESS_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {HARNESS_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ComplexAcceptanceHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = load_harness()

    def test_console_text_replaces_unencodable_model_output(self) -> None:
        rendered = self.harness.console_text("model says PASS \u2705", "cp1252")
        self.assertEqual(rendered, "model says PASS ?")

    def test_every_prompt_names_an_exact_persistent_proof_path(self) -> None:
        tasks_root = Path(r"C:\validation\tasks")
        tasks = self.harness.build_tasks(tasks_root, "unit")
        self.assertEqual(len(tasks), 20)
        for task in tasks:
            proof_path = tasks_root / task.task_id / "proof.json"
            self.assertIn(str(proof_path), task.prompt)
            self.assertIn("persistent proof path", task.prompt)

    def test_tool_gates_require_explicit_audited_actions(self) -> None:
        tasks = {
            item.task_id: item
            for item in self.harness.build_tasks(Path(r"C:\validation\tasks"), "unit")
        }
        for task in tasks.values():
            if "make_directory" in task.required_tools:
                self.assertIn("MANDATORY FIRST TOOL ACTION", task.prompt)
                self.assertIn(f"`C:\\validation\\tasks\\{task.task_id}`", task.prompt)
        for task_id in ("04-data-pipeline", "05-python-cli-project", "07-archive-transaction"):
            self.assertIn("MANDATORY WRITE-FILE GATE", tasks[task_id].prompt)
            self.assertIn(f"WRITE_FILE_GATE_{task_id}", tasks[task_id].prompt)
        self.assertNotIn(
            "WRITE_FILE_GATE_13-sqlite-binary-workflow",
            tasks["13-sqlite-binary-workflow"].prompt,
        )

    def test_unicode_prompt_codepoints_match_the_validator_payload(self) -> None:
        tasks = self.harness.build_tasks(Path(r"C:\validation\tasks"), "unit")
        task = next(item for item in tasks if item.task_id == "15-unicode-encoding")
        match = re.search(
            r"Unicode code points in order: ([0-9,]+)\. Encode",
            task.prompt,
        )
        self.assertIsNotNone(match)
        codepoints = [int(value) for value in match.group(1).split(",")]
        text = "".join(chr(value) for value in codepoints)
        self.assertEqual(text, self.harness.UNICODE_TEXT)
        self.assertEqual(codepoints[4], 108)
        self.assertEqual(codepoints[7], 73)
        self.assertIn(
            "code_points = [76,111,99,97,108,32,65,73,58",
            task.prompt,
        )
        self.assertIn(
            "The fifth integer is 108 ('l'), never 104 ('h')",
            task.prompt,
        )
        self.assertIn(
            "decoded text must begin exactly 'Local AI:', never 'Locah AI:'",
            task.prompt,
        )
        self.assertIn(
            "proof hashes must come from the actual successful tool outputs",
            task.prompt,
        )
        self.assertIn(
            'target_path = task_root / "unicode.txt"',
            task.prompt,
        )
        self.assertIn(
            'target_path.write_bytes(text.encode("utf-8"))',
            task.prompt,
        )
        self.assertIn(
            "Do not create uuid.txt or use any alternate filename",
            task.prompt,
        )

    def test_local_http_prompt_requires_a_durable_detached_server(self) -> None:
        tasks = self.harness.build_tasks(Path(r"C:\validation\tasks"), "unit")
        task = next(item for item in tasks if item.task_id == "16-local-http-roundtrip")
        self.assertIn("start_process", task.required_tools)
        self.assertIn("stop_process", task.required_tools)
        self.assertNotIn("run_powershell", task.required_tools)
        self.assertIn("{FREE_TCP_PORT}", task.prompt)
        self.assertIn("allocate_free_tcp_port=true", task.prompt)
        self.assertIn("server.stdout.log", task.prompt)
        self.assertIn("server.stderr.log", task.prompt)
        self.assertIn(
            "<body><h1>LOCAL_SERVER_TASK_16</h1></body>",
            task.prompt,
        )
        self.assertIn("top-level url=http://127.0.0.1:PORT/", task.prompt)

    def test_ambiguous_first_run_contracts_are_explicit(self) -> None:
        tasks = {
            item.task_id: item
            for item in self.harness.build_tasks(Path(r"C:\validation\tasks"), "unit")
        }
        self.assertIn(
            r"tree\level-1\item-01.txt",
            tasks["03-recursive-search-index"].prompt,
        )
        self.assertIn(
            'filename = f"item-{index:02d}.txt"',
            tasks["03-recursive-search-index"].prompt,
        )
        self.assertIn(
            'relative_path = Path("tree") / f"level-{index % 3}" / filename',
            tasks["03-recursive-search-index"].prompt,
        )
        for path in (
            r"tree\level-0\item-03.txt",
            r"tree\level-0\item-06.txt",
            r"tree\level-0\item-09.txt",
            r"tree\level-0\item-12.txt",
        ):
            self.assertIn(path, tasks["03-recursive-search-index"].prompt)
        self.assertIn(
            "number 1 -> B, number 2 -> C, number 3 -> A",
            tasks["04-data-pipeline"].prompt,
        )
        self.assertIn(
            '"rows": 200, "total": 10016, "category_sums": {"A": 2772, "B": 3911, "C": 3333}',
            tasks["04-data-pipeline"].prompt,
        )
        self.assertIn(
            "subprocess.run([sys.executable, summarize.__file__, str(fixture_path)]",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "import summarize",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "result = summarize.summarize(str(fixture_path))",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "test_summarize.py must be a short linear assertion script",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "do not use try or except anywhere",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "FUNCTION_TEST_PASS",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "CLI_TEST_PASS",
            tasks["05-python-cli-project"].prompt,
        )
        self.assertIn(
            "ctypes.windll.user32.SetProcessDPIAware()",
            tasks["10-desktop-nonvisual-probe"].prompt,
        )
        self.assertIn(
            "virtual_left, virtual_top, virtual_width, virtual_height",
            tasks["10-desktop-nonvisual-probe"].prompt,
        )
        self.assertIn(
            "Do not call GetCursorPos",
            tasks["10-desktop-nonvisual-probe"].prompt,
        )
        self.assertIn(
            "aspect_ratio = round(width / height, 4)",
            tasks["10-desktop-nonvisual-probe"].prompt,
        )
        self.assertIn(
            "$lines = [System.IO.File]::ReadAllLines($resolved)",
            tasks["06-powershell-cli-project"].prompt,
        )
        self.assertIn(
            "$sha256 = -join ($hashBytes | ForEach-Object { $_.ToString('X2') })",
            tasks["06-powershell-cli-project"].prompt,
        )
        self.assertIn(
            "Do not count lines by splitting a trailing newline",
            tasks["06-powershell-cli-project"].prompt,
        )
        self.assertIn(
            "Keep extracted intact for independent validation",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "Use delete_path recursively on staging only",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "Do not move beta.txt or gamma.txt out of staging before compression",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "Compress-Archive -Path (Join-Path $staging '*')",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            r"staging=`C:\validation\tasks\07-archive-transaction\staging`",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "After that successful delete_path, do not issue any further operation against staging",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "copy-probe.txt",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "move-source.txt",
            tasks["07-archive-transaction"].prompt,
        )
        self.assertIn(
            "JSON key must be named exactly bytes",
            tasks["08-web-fetch-download-parse"].prompt,
        )
        self.assertIn(
            "paragraph_contains set exactly to the full first-paragraph text returned by browser_automation",
            tasks["09-browser-dom-verification"].prompt,
        )
        self.assertNotIn(
            "illustrative examples",
            tasks["09-browser-dom-verification"].prompt,
        )
        self.assertIn(
            '"action":"extract","selector":"p:nth-of-type(1)"',
            tasks["09-browser-dom-verification"].prompt,
        )
        self.assertEqual(
            tasks["09-browser-dom-verification"].minimum_successful_actions,
            4,
        )
        self.assertIn(
            r"target_directory exactly C:\validation\tasks\11-isolated-package-install\packages",
            tasks["11-isolated-package-install"].prompt,
        )
        self.assertIn(
            "Create that exact packages directory before calling install_python_package",
            tasks["11-isolated-package-install"].prompt,
        )
        self.assertIn(
            "Call write_file immediately after read_binary_file",
            tasks["13-sqlite-binary-workflow"].prompt,
        )
        self.assertIn(
            "category = ('A','B','C')[id % 3]",
            tasks["13-sqlite-binary-workflow"].prompt,
        )
        self.assertIn(
            "Do not merely say that you will write proof.json",
            tasks["13-sqlite-binary-workflow"].prompt,
        )
        self.assertIn(
            "Before any run_python call, use write_file to create task13-write-file-gate.txt",
            tasks["13-sqlite-binary-workflow"].prompt,
        )
        self.assertIn(
            'JSON key named exactly "sha256"',
            tasks["12-capability-discovery"].prompt,
        )
        self.assertIn(
            "Generate input.xml algorithmically in one run_python loop",
            tasks["14-xml-json-transform"].prompt,
        )
        self.assertIn(
            'Use an id attribute only: <record id="1"> through <record id="25">',
            tasks["14-xml-json-transform"].prompt,
        )
        self.assertIn(
            '<record id="1"><marker>TASK14_XML</marker><value>7</value></record>',
            tasks["14-xml-json-transform"].prompt,
        )
        self.assertIn(
            'ET.SubElement(root, "record", {"id": str(index)})',
            tasks["14-xml-json-transform"].prompt,
        )
        self.assertIn(
            "Call start_process exactly once",
            tasks["16-local-http-roundtrip"].prompt,
        )
        self.assertIn(
            '{"action":"extract","selector":"h1"}',
            tasks["16-local-http-roundtrip"].prompt,
        )
        self.assertIn(
            "mapping_count is the number of non-comment mapping lines, including duplicate hostnames",
            tasks["18-hosts-sanitized-summary"].prompt,
        )
        self.assertIn(
            "Start-Job -ArgumentList $first, $second",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "foreach ($worker in 0..3) {",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "$results = @($jobs | Wait-Job | Receive-Job)",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "one single run_powershell tool call with timeout_seconds at least 120",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "for index in range(1, 9)",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            'filename = f"worker-{index:02d}.txt"',
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "content = filename * index",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "Never split job creation, waiting, receiving, cleanup, or JSON writing across separate",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "use write_file, not run_python, to create proof.json as the final task action",
            tasks["19-concurrent-hash-workers"].prompt,
        )
        self.assertIn(
            "subprocess.run([sys.executable, str(task_root / 'tests.py')]",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "do not edit tests.py after the first red run",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "([-1,-2,0],[-6,-3,0])",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "Do not use unittest, pytest, or test discovery",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "PASS: 5/5",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "(Get-Command python.exe).Source",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "Do not use python -c",
            tasks["20-red-green-recovery"].prompt,
        )
        self.assertIn(
            "Do not create helper Python or PowerShell scripts",
            tasks["20-red-green-recovery"].prompt,
        )

    def test_python_cli_validator_rejects_suppressed_cli_failures(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "fixture.json").write_text(
                json.dumps([5, 7, 11, 13, 17]),
                encoding="utf-8",
            )
            (task_root / "summarize.py").write_text(
                "import json,sys\n"
                "def summarize(path):\n"
                "    values=json.load(open(path, encoding='utf-8'))\n"
                "    return {'count':len(values),'sum':sum(values),'mean':sum(values)/len(values),"
                "'minimum':min(values),'maximum':max(values)}\n"
                "if __name__ == '__main__':\n"
                "    print(json.dumps(summarize(sys.argv[1]), separators=(',', ':')))\n",
                encoding="utf-8",
            )
            (task_root / "test_summarize.py").write_text(
                "from pathlib import Path\n"
                "import sys\n"
                "sys.path.insert(0, str(Path(__file__).resolve().parent))\n"
                "import summarize\n"
                "print('FUNCTION_TEST_PASS')\n"
                "try:\n"
                "    raise RuntimeError('broken CLI test')\n"
                "except Exception:\n"
                "    print('CLI_TEST_SKIPPED')\n",
                encoding="utf-8",
            )
            (task_root / "proof.json").write_text(
                json.dumps({"status": "PASS"}),
                encoding="utf-8",
            )

            with self.assertRaises(self.harness.ValidationError):
                self.harness.validate_05(task_root, [])

    def test_sqlite_validator_requires_gate_order_and_real_binary_proof(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            database = task_root / "records.db"
            connection = sqlite3.connect(database)
            try:
                connection.execute(
                    "create table records(id integer primary key, category text, amount integer)"
                )
                connection.executemany(
                    "insert into records(id, category, amount) values (?, ?, ?)",
                    [
                        (index, ("A", "B", "C")[index % 3], (index * 19) % 97)
                        for index in range(1, 51)
                    ],
                )
                connection.commit()
            finally:
                connection.close()

            expected_groups = {"A": 0, "B": 0, "C": 0}
            for index in range(1, 51):
                expected_groups[("A", "B", "C")[index % 3]] += (index * 19) % 97
            prefix = base64.b64encode(database.read_bytes()[:100]).decode("ascii")
            proof = {
                "status": "PASS",
                "rows": 50,
                "total": sum((index * 19) % 97 for index in range(1, 51)),
                "category_totals": expected_groups,
                "binary_prefix_base64": prefix,
            }
            (task_root / "proof.json").write_text(json.dumps(proof), encoding="utf-8")
            gate_path = task_root / "task13-write-file-gate.txt"
            gate_path.write_text("TASK13_WRITE_FILE_GATE", encoding="utf-8")
            actions = [
                {
                    "tool": "write_file",
                    "arguments": {
                        "path": str(gate_path),
                        "content": "TASK13_WRITE_FILE_GATE",
                    },
                    "result": json.dumps({"ok": True}),
                },
                {
                    "tool": "run_python",
                    "arguments": {"code": "import sqlite3"},
                    "result": json.dumps({"ok": True, "exit_code": 0}),
                },
                {
                    "tool": "read_binary_file",
                    "arguments": {"path": str(database), "max_bytes": 100},
                    "result": json.dumps(
                        {
                            "ok": True,
                            "bytes": 100,
                            "data_base64": prefix,
                        }
                    ),
                },
                {
                    "tool": "write_file",
                    "arguments": {
                        "path": str(task_root / "proof.json"),
                        "content": json.dumps(proof),
                    },
                    "result": json.dumps({"ok": True}),
                },
            ]

            verification = self.harness.validate_13(task_root, actions)
            self.assertEqual(verification["groups"], expected_groups)

            actions_without_gate = actions[1:]
            with self.assertRaisesRegex(
                self.harness.ValidationError,
                "SQLite write_file gate",
            ):
                self.harness.validate_13(task_root, actions_without_gate)

            actions_wrong_order = [actions[1], actions[0], *actions[2:]]
            with self.assertRaisesRegex(
                self.harness.ValidationError,
                "before run_python",
            ):
                self.harness.validate_13(task_root, actions_wrong_order)

    def test_desktop_validator_accepts_cursor_on_a_secondary_monitor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "proof.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "width": 3840,
                        "height": 2160,
                        "cursor_x": 4964,
                        "cursor_y": 1764,
                        "aspect_ratio": 1.7778,
                        "virtual_left": 0,
                        "virtual_top": 0,
                        "virtual_width": 10560,
                        "virtual_height": 2160,
                    }
                ),
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "desktop_automation",
                    "arguments": {
                        "actions": [
                            {"action": "screen_size"},
                            {"action": "position"},
                        ]
                    },
                    "result": json.dumps(
                        {
                            "ok": True,
                            "actions": [
                                {
                                    "index": 0,
                                    "action": "screen_size",
                                    "result": {"width": 3840, "height": 2160},
                                },
                                {
                                    "index": 1,
                                    "action": "position",
                                    "result": {"x": 4964, "y": 1764},
                                },
                            ],
                        }
                    ),
                }
            ]
            metrics = {
                "virtual_left": 0,
                "virtual_top": 0,
                "virtual_width": 10560,
                "virtual_height": 2160,
            }

            with mock.patch.object(
                self.harness,
                "current_virtual_desktop_metrics",
                return_value=metrics,
            ):
                verification = self.harness.validate_10(task_root, actions)

            self.assertEqual(
                verification,
                {
                    "width": 3840,
                    "height": 2160,
                    "aspect_ratio": 1.7778,
                    **metrics,
                },
            )

    def test_browser_validator_compares_proof_to_extracted_dom_text(self) -> None:
        paragraph = (
            "This domain is for use in documentation examples without needing permission. "
            "Avoid use in operations."
        )
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "proof.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "title": "Example Domain",
                        "h1": "Example Domain",
                        "paragraph_contains": paragraph,
                    }
                ),
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "browser_automation",
                    "arguments": {
                        "actions": [
                            {"action": "extract", "selector": "p:nth-of-type(1)"}
                        ]
                    },
                    "result": json.dumps(
                        {
                            "ok": True,
                            "actions": [
                                {"index": 0, "action": "extract", "result": paragraph}
                            ],
                        }
                    ),
                }
            ]

            verification = self.harness.validate_09(task_root, actions)

            self.assertEqual(
                verification,
                {
                    "title": "Example Domain",
                    "h1": "Example Domain",
                    "paragraph": paragraph,
                },
            )

    def test_browser_validator_accepts_evaluated_first_paragraph_dom_text(self) -> None:
        paragraph = (
            "This domain is for use in documentation examples without needing permission. "
            "Avoid use in operations."
        )
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "proof.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "title": "Example Domain",
                        "h1": "Example Domain",
                        "paragraph_contains": paragraph,
                    }
                ),
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "browser_automation",
                    "arguments": {
                        "actions": [
                            {
                                "action": "evaluate",
                                "value": "document.querySelector('p').textContent",
                            }
                        ]
                    },
                    "result": json.dumps(
                        {
                            "ok": True,
                            "actions": [
                                {"index": 0, "action": "evaluate", "result": paragraph}
                            ],
                        }
                    ),
                }
            ]

            verification = self.harness.validate_09(task_root, actions)

            self.assertEqual(verification["paragraph"], paragraph)

    def test_browser_extracted_text_accepts_a_generic_selector_evaluation(self) -> None:
        marker = "LOCAL_SERVER_TASK_16"
        actions = [
            {
                "tool": "browser_automation",
                "arguments": {
                    "actions": [
                        {
                            "action": "evaluate",
                            "value": "document.querySelector('h1').textContent",
                        }
                    ]
                },
                "result": json.dumps(
                    {
                        "ok": True,
                        "actions": [
                            {"index": 0, "action": "evaluate", "result": marker}
                        ],
                    }
                ),
            }
        ]

        self.assertEqual(
            self.harness.browser_extracted_text(actions, "h1"),
            marker,
        )

    def test_browser_validator_accepts_first_paragraph_from_browser_html(self) -> None:
        paragraph = (
            "This domain is for use in documentation examples without needing permission. "
            "Avoid use in operations."
        )
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "proof.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "title": "Example Domain",
                        "h1": "Example Domain",
                        "paragraph_contains": paragraph,
                    }
                ),
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "browser_automation",
                    "arguments": {
                        "url": "https://example.com",
                        "actions": [{"action": "goto", "url": "https://example.com"}],
                    },
                    "result": json.dumps(
                        {
                            "ok": True,
                            "title": "Example Domain",
                            "content": (
                                "<html><head><title>Example Domain</title></head>"
                                "<body><h1>Example Domain</h1>"
                                f"<p>{paragraph}</p></body></html>"
                            ),
                            "actions": [{"index": 0, "action": "goto", "ok": True}],
                        }
                    ),
                }
            ]

            verification = self.harness.validate_09(task_root, actions)

            self.assertEqual(verification["paragraph"], paragraph)

    def test_xml_validator_rejects_a_corrupt_input_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            records = []
            filtered = []
            for index in range(1, 26):
                marker = "CORRUPT" if index == 13 else "TASK14_XML"
                records.append(
                    f'<record id="{index}"><marker>{marker}</marker>'
                    f"<value>{index * 7}</value></record>"
                )
                if index % 2 == 0:
                    filtered.append(
                        {"id": index, "marker": "TASK14_XML", "value": index * 7}
                    )
            (task_root / "input.xml").write_text(
                "<records>" + "".join(records) + "</records>",
                encoding="utf-8",
            )
            (task_root / "filtered.json").write_text(
                json.dumps(filtered),
                encoding="utf-8",
            )
            (task_root / "proof.json").write_text(
                json.dumps(
                    {"status": "PASS", "input_records": 25, "output_records": 12}
                ),
                encoding="utf-8",
            )
            with self.assertRaises(self.harness.ValidationError):
                self.harness.validate_14(task_root, [])

    def test_xml_validator_accepts_ids_as_child_elements(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            records = []
            filtered = []
            for index in range(1, 26):
                records.append(
                    f"<record><id>{index}</id><marker>TASK14_XML</marker>"
                    f"<value>{index * 7}</value></record>"
                )
                if index % 2 == 0:
                    filtered.append(
                        {"id": index, "marker": "TASK14_XML", "value": index * 7}
                    )
            (task_root / "input.xml").write_text(
                "<records>" + "".join(records) + "</records>",
                encoding="utf-8",
            )
            (task_root / "filtered.json").write_text(
                json.dumps(filtered),
                encoding="utf-8",
            )
            (task_root / "proof.json").write_text(
                json.dumps(
                    {"status": "PASS", "input_records": 25, "output_records": 12}
                ),
                encoding="utf-8",
            )

            verification = self.harness.validate_14(task_root, [])

            self.assertEqual(
                verification,
                {"input_records": 25, "output_records": 12},
            )

    def test_concurrent_validator_accepts_a_successfully_executed_ps1(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            inputs = task_root / "inputs"
            inputs.mkdir()
            manifest = {}
            for index in range(1, 9):
                path = inputs / f"worker-{index:02d}.txt"
                path.write_text(path.name * index, encoding="utf-8")
                manifest[path.name] = hashlib.sha256(path.read_bytes()).hexdigest().upper()
            (task_root / "hashes.json").write_text(
                json.dumps(manifest),
                encoding="utf-8",
            )
            (task_root / "proof.json").write_text(
                json.dumps(
                    {
                        "status": "PASS",
                        "worker_count": 4,
                        "file_count": 8,
                        "hashes_match": True,
                    }
                ),
                encoding="utf-8",
            )
            script = task_root / "compute_hashes.ps1"
            script.write_text(
                "$jobs = foreach ($worker in 0..3) { Start-Job { 1 } }\n"
                "$results = @($jobs | Wait-Job | Receive-Job)\n"
                "$jobs | Remove-Job -Force\n",
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "run_powershell",
                    "arguments": {
                        "command": (
                            "powershell.exe -NoProfile -ExecutionPolicy Bypass "
                            f'-File "{script}"'
                        )
                    },
                    "result": json.dumps({"ok": True, "exit_code": 0}),
                }
            ]

            verification = self.harness.validate_19(task_root, actions)

            self.assertEqual(verification, {"files": 8, "workers": 4})

    def test_red_green_validator_rejects_rewriting_tests_after_red(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            task_root = Path(directory)
            (task_root / "app.py").write_text(
                "def normalize(values):\n"
                "    return sorted(set(int(value * 3) for value in values))\n",
                encoding="utf-8",
            )
            (task_root / "config.json").write_text(
                json.dumps({"multiplier": 3}),
                encoding="utf-8",
            )
            (task_root / "tests.py").write_text(
                "import app\n"
                "assert app.normalize([-1, -2, 0]) == [-6, -3, 0]\n"
                "print('PASS')\n",
                encoding="utf-8",
            )
            (task_root / "red.txt").write_text(
                "CHECK 5: actual=[2, 4] expected=[4, 7]\nFAIL: 4 mismatches\n",
                encoding="utf-8",
            )
            (task_root / "green.txt").write_text(
                "CHECK 5: actual=[4, 7] expected=[4, 7]\nPASS: 5/5\n",
                encoding="utf-8",
            )
            (task_root / "proof.json").write_text(
                json.dumps({"status": "PASS"}),
                encoding="utf-8",
            )
            actions = [
                {
                    "tool": "write_file",
                    "arguments": {"path": str(task_root / "tests.py")},
                    "result": json.dumps({"ok": True}),
                },
                {
                    "tool": "run_python",
                    "arguments": {"code": "raise AssertionError"},
                    "result": json.dumps(
                        {
                            "ok": False,
                            "exit_code": 1,
                            "stdout": "CHECK 5: actual=[2, 4] expected=[4, 7]\nFAIL: 4 mismatches\n",
                            "stderr": "",
                        }
                    ),
                },
                {
                    "tool": "write_file",
                    "arguments": {"path": str(task_root / "tests.py")},
                    "result": json.dumps({"ok": True}),
                },
                {
                    "tool": "run_python",
                    "arguments": {"code": "print('PASS')"},
                    "result": json.dumps(
                        {
                            "ok": True,
                            "exit_code": 0,
                            "stdout": "CHECK 5: actual=[4, 7] expected=[4, 7]\nPASS: 5/5\n",
                            "stderr": "",
                        }
                    ),
                },
            ]

            with self.assertRaisesRegex(
                self.harness.ValidationError,
                "tests.py must be written exactly once",
            ):
                self.harness.validate_20(task_root, actions)


if __name__ == "__main__":
    unittest.main()
