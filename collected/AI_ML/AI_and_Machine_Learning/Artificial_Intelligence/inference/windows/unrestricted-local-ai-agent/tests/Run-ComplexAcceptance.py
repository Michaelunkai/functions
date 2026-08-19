#!/usr/bin/env python3
"""Run 20 model-driven, independently verified local-agent acceptance tasks."""

from __future__ import annotations

import argparse
import ast
import base64
import csv
from dataclasses import dataclass
from datetime import datetime
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import queue
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from typing import Any, Callable
import xml.etree.ElementTree as ET
import zipfile


DEFAULT_DEPLOYED_ROOT = Path.home() / "UnrestrictedAgent"
DEPLOYED_ROOT = DEFAULT_DEPLOYED_ROOT
LAUNCHER = DEPLOYED_ROOT / "run_agent.ps1"
AGENT_PYTHON = DEPLOYED_ROOT / "runtime" / "python" / "python.exe"
ACTION_LOG = DEPLOYED_ROOT / "logs" / "agent-actions.jsonl"
DEFAULT_VALIDATION_ROOT = DEPLOYED_ROOT / "validation"
POWERSHELL = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"

BINARY_PAYLOAD = bytes(range(256)) + b"LOCAL-AI-BINARY-ROUNDTRIP"
BINARY_BASE64 = base64.b64encode(BINARY_PAYLOAD).decode("ascii")
BINARY_SHA256 = hashlib.sha256(BINARY_PAYLOAD).hexdigest().upper()
UNICODE_CODEPOINTS = [
    0x004C, 0x006F, 0x0063, 0x0061, 0x006C, 0x0020, 0x0041, 0x0049, 0x003A, 0x0020,
    0x05E9, 0x05DC, 0x05D5, 0x05DD, 0x0020,
    0x0645, 0x0631, 0x062D, 0x0628, 0x0627, 0x0020,
    0x4E16, 0x754C, 0x0020, 0x1F680, 0x000A,
]
UNICODE_TEXT = "".join(chr(value) for value in UNICODE_CODEPOINTS)
UNICODE_SHA256 = hashlib.sha256(UNICODE_TEXT.encode("utf-8")).hexdigest().upper()


class ValidationError(RuntimeError):
    pass


def configure_deployment_root(root: Path) -> None:
    global DEPLOYED_ROOT, LAUNCHER, AGENT_PYTHON, ACTION_LOG, DEFAULT_VALIDATION_ROOT
    DEPLOYED_ROOT = root.expanduser().resolve()
    LAUNCHER = DEPLOYED_ROOT / "run_agent.ps1"
    AGENT_PYTHON = DEPLOYED_ROOT / "runtime" / "python" / "python.exe"
    ACTION_LOG = DEPLOYED_ROOT / "logs" / "agent-actions.jsonl"
    DEFAULT_VALIDATION_ROOT = DEPLOYED_ROOT / "validation"


Validator = Callable[[Path, list[dict[str, Any]]], dict[str, Any]]


@dataclass(frozen=True)
class Task:
    task_id: str
    title: str
    prompt: str
    required_tools: tuple[str, ...]
    minimum_successful_actions: int
    validator: Validator


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def console_text(value: str, encoding: str | None = None) -> str:
    target_encoding = encoding or getattr(sys.stdout, "encoding", None) or "utf-8"
    try:
        return value.encode(target_encoding, errors="replace").decode(
            target_encoding, errors="replace"
        )
    except LookupError:
        return value


def read_json(path: Path) -> Any:
    require(path.is_file(), f"Missing JSON file: {path}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def successful_actions(actions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    successful: list[dict[str, Any]] = []
    for action in actions:
        try:
            result = json.loads(str(action.get("result", "")))
        except (TypeError, ValueError, json.JSONDecodeError):
            continue
        if result.get("ok") is True:
            successful.append(action)
    return successful


def action_result(action: dict[str, Any]) -> dict[str, Any]:
    try:
        value = json.loads(str(action.get("result", "")))
    except (TypeError, ValueError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def browser_extracted_text(actions: list[dict[str, Any]], selector: str) -> str:
    for action in successful_actions(actions):
        if action.get("tool") != "browser_automation":
            continue
        requested = action.get("arguments", {}).get("actions", [])
        if isinstance(requested, str):
            try:
                requested = json.loads(requested)
            except json.JSONDecodeError:
                continue
        completed = action_result(action).get("actions", [])
        if not isinstance(requested, list) or not isinstance(completed, list):
            continue
        completed_by_index = {
            item.get("index"): item
            for item in completed
            if isinstance(item, dict) and isinstance(item.get("index"), int)
        }
        for index, request in enumerate(requested):
            if not isinstance(request, dict):
                continue
            is_selector_extract = (
                request.get("action") == "extract"
                and request.get("selector") == selector
            )
            expression = re.sub(
                r"\s+",
                "",
                str(request.get("value", "")).lower().replace('"', "'"),
            )
            selector_candidates = [selector.lower()]
            if selector == "p:nth-of-type(1)":
                selector_candidates.append("p")
            is_selector_evaluate = (
                request.get("action") == "evaluate"
                and any(
                    (
                        f"document.queryselector('{candidate}').textcontent"
                        in expression
                        or f"document.queryselector('{candidate}').innertext"
                        in expression
                    )
                    for candidate in selector_candidates
                )
            )
            if not is_selector_extract and not is_selector_evaluate:
                continue
            response = completed_by_index.get(index)
            if response is None and index < len(completed) and isinstance(completed[index], dict):
                response = completed[index]
            if isinstance(response, dict) and isinstance(response.get("result"), str):
                return response["result"]
    return ""


def current_virtual_desktop_metrics() -> dict[str, int]:
    probe_code = (
        "import ctypes,json;"
        "user32=ctypes.windll.user32;"
        "user32.SetProcessDPIAware();"
        "print(json.dumps({"
        "'virtual_left':user32.GetSystemMetrics(76),"
        "'virtual_top':user32.GetSystemMetrics(77),"
        "'virtual_width':user32.GetSystemMetrics(78),"
        "'virtual_height':user32.GetSystemMetrics(79)"
        "}))"
    )
    completed = subprocess.run(
        [str(AGENT_PYTHON), "-c", probe_code],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=30,
    )
    require(
        completed.returncode == 0,
        f"Unable to inspect the virtual desktop: {completed.stderr}",
    )
    metrics = json.loads(completed.stdout)
    return {key: int(value) for key, value in metrics.items()}


class BrowserContentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._active_tag = ""
        self._active_depth = 0
        self._parts: list[str] = []
        self._values = {"title": "", "h1": "", "p": ""}

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        del attrs
        normalized = tag.lower()
        if self._active_tag:
            self._active_depth += 1
            return
        if normalized in self._values and not self._values[normalized]:
            self._active_tag = normalized
            self._active_depth = 1
            self._parts = []

    def handle_endtag(self, tag: str) -> None:
        if not self._active_tag:
            return
        self._active_depth -= 1
        if self._active_depth != 0:
            return
        if tag.lower() == self._active_tag:
            self._values[self._active_tag] = " ".join(
                "".join(self._parts).split()
            )
        self._active_tag = ""
        self._parts = []

    def handle_data(self, data: str) -> None:
        if self._active_tag:
            self._parts.append(data)

    @property
    def values(self) -> dict[str, str]:
        return dict(self._values)


def browser_observed_dom(actions: list[dict[str, Any]]) -> dict[str, str]:
    for action in successful_actions(actions):
        if action.get("tool") != "browser_automation":
            continue
        result = action_result(action)
        content = result.get("content")
        if not isinstance(content, str) or not content.strip():
            continue
        parser = BrowserContentParser()
        parser.feed(content)
        parser.close()
        values = parser.values
        result_title = result.get("title")
        if isinstance(result_title, str) and result_title.strip():
            values["title"] = " ".join(result_title.split())
        if any(values.values()):
            return values
    return {"title": "", "h1": "", "p": ""}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def proof_pass(task_root: Path) -> dict[str, Any]:
    proof = read_json(task_root / "proof.json")
    require(proof.get("status") == "PASS", "proof.json does not report PASS")
    return proof


def validate_01(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    proof = proof_pass(task_root)
    token = "LOCAL_AI_PRIVILEGED_TASK_01"
    require(proof.get("token") == token, "Privileged token mismatch")
    require(proof.get("administrator") is True, "Administrator proof is not true")
    require(proof.get("cleaned") is True, "Privileged temporary directory was not reported cleaned")
    temp_prefix = r"C:\Windows\Temp\local-ai-acceptance-"
    writes = [
        action for action in successful_actions(actions)
        if action.get("tool") == "write_file"
        and str(action.get("arguments", {}).get("path", "")).lower().startswith(temp_prefix.lower())
    ]
    require(writes, "No successful privileged write_file action was logged")
    require(not any(Path(str(item["arguments"]["path"])).exists() for item in writes), "Privileged probe still exists")
    return {"token": token, "privileged_writes": len(writes)}


def validate_02(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    target = task_root / "payload.bin"
    require(target.is_file(), "payload.bin is missing")
    require(target.read_bytes() == BINARY_PAYLOAD, "Binary payload does not round-trip exactly")
    proof = proof_pass(task_root)
    require(str(proof.get("sha256", "")).upper() == BINARY_SHA256, "Binary proof hash mismatch")
    require(proof.get("bytes") == len(BINARY_PAYLOAD), "Binary proof byte count mismatch")
    return {"bytes": len(BINARY_PAYLOAD), "sha256": BINARY_SHA256}


def expected_task03_files(task_root: Path) -> dict[Path, str]:
    expected: dict[Path, str] = {}
    for index in range(1, 13):
        path = task_root / "tree" / f"level-{index % 3}" / f"item-{index:02d}.txt"
        expected[path] = f"TASK03_MARKER item={index} square={index * index}\n"
    return expected


def validate_03(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    expected = expected_task03_files(task_root)
    for path, content in expected.items():
        require(path.read_text(encoding="utf-8") == content, f"Unexpected content in {path}")
    index = read_json(task_root / "index.json")
    require(index.get("marker_count") == 12, "Search index marker_count is not 12")
    require(index.get("file_count") == 12, "Search index file_count is not 12")
    return {"files": 12, "marker_count": 12}


def expected_task04() -> tuple[int, dict[str, int], int]:
    category_sums = {"A": 0, "B": 0, "C": 0}
    total = 0
    categories = ("A", "B", "C")
    for number in range(1, 201):
        value = (number * 17) % 101
        category = categories[number % 3]
        category_sums[category] += value
        total += value
    return total, category_sums, 200


def validate_04(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    csv_path = task_root / "dataset.csv"
    require(csv_path.is_file(), "dataset.csv is missing")
    with csv_path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    total, category_sums, row_count = expected_task04()
    require(len(rows) == row_count, "CSV row count mismatch")
    actual_total = sum(int(row["value"]) for row in rows)
    require(actual_total == total, "CSV total mismatch")
    summary = read_json(task_root / "summary.json")
    require(summary.get("rows") == row_count, "Summary rows mismatch")
    require(summary.get("total") == total, "Summary total mismatch")
    require(summary.get("category_sums") == category_sums, "Summary category sums mismatch")
    proof_pass(task_root)
    return {"rows": row_count, "total": total, "category_sums": category_sums}


def validate_05(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    expected = {"count": 5, "sum": 53, "mean": 10.6, "minimum": 5, "maximum": 17}
    test_path = task_root / "test_summarize.py"
    test_source = test_path.read_text(encoding="utf-8")
    require(
        re.search(r"\b(skip|skipped|xfail)\b", test_source, flags=re.IGNORECASE) is None,
        "Generated Python tests suppress or skip a failure",
    )
    try:
        test_tree = ast.parse(test_source, filename=str(test_path))
    except SyntaxError as exc:
        raise ValidationError(f"Generated Python tests do not parse: {exc}") from exc

    direct_cli_calls: list[ast.Call] = []
    exercises_function = False
    for node in ast.walk(test_tree):
        if (
            isinstance(node, ast.Attribute)
            and node.attr == "summarize"
            and isinstance(node.value, ast.Name)
            and node.value.id == "summarize"
        ):
            exercises_function = True
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if (
            node.func.attr != "run"
            or not isinstance(node.func.value, ast.Name)
            or node.func.value.id != "subprocess"
            or not node.args
            or not isinstance(node.args[0], (ast.List, ast.Tuple))
        ):
            continue
        command_items = node.args[0].elts
        has_python = any(
            isinstance(item, ast.Attribute)
            and item.attr == "executable"
            and isinstance(item.value, ast.Name)
            and item.value.id == "sys"
            for item in command_items
        )
        has_script = any(
            isinstance(item, ast.Attribute)
            and item.attr == "__file__"
            and isinstance(item.value, ast.Name)
            and item.value.id == "summarize"
            for item in command_items
        )
        if has_python and has_script:
            direct_cli_calls.append(node)

    require(exercises_function, "Generated tests do not exercise summarize.summarize")
    require(direct_cli_calls, "Generated tests do not launch summarize.py directly")
    cli_call = direct_cli_calls[0]
    keywords = {item.arg: item.value for item in cli_call.keywords if item.arg}
    for keyword in ("capture_output", "text"):
        require(
            isinstance(keywords.get(keyword), ast.Constant)
            and keywords[keyword].value is True,
            f"Generated CLI test must set {keyword}=True",
        )
    require(
        isinstance(keywords.get("encoding"), ast.Constant)
        and str(keywords["encoding"].value).lower().replace("_", "-") == "utf-8",
        "Generated CLI test must set encoding='utf-8'",
    )

    command = [str(AGENT_PYTHON), str(task_root / "summarize.py"), str(task_root / "fixture.json")]
    completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=60)
    require(completed.returncode == 0, f"Generated Python CLI failed: {completed.stderr}")
    require(json.loads(completed.stdout) == expected, "Generated Python CLI returned unexpected JSON")
    bootstrap = (
        "import runpy,sys;"
        "sys.path.insert(0,sys.argv[1]);"
        "runpy.run_path(sys.argv[2],run_name='__main__')"
    )
    tests = subprocess.run(
        [
            str(AGENT_PYTHON),
            "-c",
            bootstrap,
            str(task_root),
            str(task_root / "test_summarize.py"),
        ],
        cwd=task_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    require(tests.returncode == 0, f"Generated Python tests failed: {tests.stdout}\n{tests.stderr}")
    require("FUNCTION_TEST_PASS" in tests.stdout, "Generated tests did not prove the importable function")
    require("CLI_TEST_PASS" in tests.stdout, "Generated tests did not prove the direct CLI subprocess")
    proof_pass(task_root)
    return {"cli": expected, "tests_exit_code": tests.returncode}


def validate_06(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    script = task_root / "Get-InventoryDigest.ps1"
    fixture = task_root / "fixture.txt"
    require(script.is_file() and fixture.is_file(), "PowerShell task files are missing")
    completed = subprocess.run(
        [
            str(POWERSHELL), "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(script), "-InputPath", str(fixture),
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    require(completed.returncode == 0, f"Generated PowerShell script failed: {completed.stderr}")
    output = json.loads(completed.stdout.strip())
    require(output.get("lineCount") == 3, "PowerShell lineCount mismatch")
    require(str(output.get("sha256", "")).upper() == sha256_file(fixture), "PowerShell hash mismatch")
    proof_pass(task_root)
    return output


def validate_07(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    archive = task_root / "bundle.zip"
    require(archive.is_file() and archive.stat().st_size > 0, "bundle.zip is missing or empty")
    with zipfile.ZipFile(archive, "r") as handle:
        names = sorted(name.replace("\\", "/") for name in handle.namelist() if not name.endswith("/"))
        require(names == ["alpha.txt", "nested/beta.txt", "nested/gamma.txt"], f"Unexpected archive entries: {names}")
    extracted = task_root / "extracted"
    require((extracted / "alpha.txt").read_text(encoding="utf-8-sig").strip() == "alpha-07", "alpha extraction mismatch")
    require((extracted / "nested" / "beta.txt").read_text(encoding="utf-8-sig").strip() == "beta-07", "beta extraction mismatch")
    require((extracted / "nested" / "gamma.txt").read_text(encoding="utf-8-sig").strip() == "gamma-07", "gamma extraction mismatch")
    require(not (task_root / "staging").exists(), "Staging directory was not deleted")
    proof_pass(task_root)
    return {"archive_entries": names, "staging_deleted": True}


def validate_08(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    html = (task_root / "example.html").read_text(encoding="utf-8")
    require("Example Domain" in html, "Downloaded HTML does not contain Example Domain")
    proof = proof_pass(task_root)
    require(proof.get("title") == "Example Domain", "Parsed title mismatch")
    require(proof.get("h1") == "Example Domain", "Parsed h1 mismatch")
    require(int(proof.get("bytes", 0)) > 100, "Downloaded byte count is too small")
    return {"title": "Example Domain", "bytes": proof["bytes"]}


def validate_09(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    proof = proof_pass(task_root)
    require(proof.get("title") == "Example Domain", "Browser title mismatch")
    require(proof.get("h1") == "Example Domain", "Browser h1 mismatch")
    observed = browser_observed_dom(actions)
    if observed["title"]:
        require(observed["title"] == "Example Domain", "Observed browser title mismatch")
        require(proof.get("title") == observed["title"], "Browser title proof mismatch")
    if observed["h1"]:
        require(observed["h1"] == "Example Domain", "Observed browser h1 mismatch")
        require(proof.get("h1") == observed["h1"], "Browser h1 proof mismatch")
    extracted = browser_extracted_text(actions, "p:nth-of-type(1)") or observed["p"]
    require(extracted, "No successful first-paragraph browser observation was logged")
    require(len(extracted) >= 20, "Extracted browser paragraph is implausibly short")
    require(
        proof.get("paragraph_contains") == extracted,
        "Browser paragraph proof does not match the extracted DOM text",
    )
    return {"title": proof["title"], "h1": proof["h1"], "paragraph": extracted}


def validate_10(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    proof = proof_pass(task_root)
    width = int(proof.get("width", 0))
    height = int(proof.get("height", 0))
    require(width >= 640 and height >= 480, "Desktop screen size is implausible")
    cursor_x = int(proof.get("cursor_x", -1))
    cursor_y = int(proof.get("cursor_y", -1))

    observed_size: dict[str, Any] = {}
    observed_position: dict[str, Any] = {}
    for action in successful_actions(actions):
        if action.get("tool") != "desktop_automation":
            continue
        completed = action_result(action).get("actions", [])
        if not isinstance(completed, list):
            continue
        for item in completed:
            if not isinstance(item, dict) or not isinstance(item.get("result"), dict):
                continue
            if item.get("action") == "screen_size":
                observed_size = item["result"]
            elif item.get("action") == "position":
                observed_position = item["result"]

    require(observed_size, "No successful desktop screen_size result was logged")
    require(observed_position, "No successful desktop position result was logged")
    require(int(observed_size.get("width", 0)) == width, "Desktop width proof mismatch")
    require(int(observed_size.get("height", 0)) == height, "Desktop height proof mismatch")
    require(int(observed_position.get("x", -1)) == cursor_x, "Cursor X proof mismatch")
    require(int(observed_position.get("y", -1)) == cursor_y, "Cursor Y proof mismatch")

    metrics = current_virtual_desktop_metrics()
    for key, expected in metrics.items():
        require(int(proof.get(key, 0)) == expected, f"{key} proof mismatch")
    require(metrics["virtual_width"] >= width, "Virtual desktop width is smaller than the primary screen")
    require(metrics["virtual_height"] >= height, "Virtual desktop height is smaller than the primary screen")
    require(
        metrics["virtual_left"] <= cursor_x < metrics["virtual_left"] + metrics["virtual_width"],
        "Cursor X is outside the virtual desktop",
    )
    require(
        metrics["virtual_top"] <= cursor_y < metrics["virtual_top"] + metrics["virtual_height"],
        "Cursor Y is outside the virtual desktop",
    )
    ratio = float(proof.get("aspect_ratio", 0))
    require(abs(ratio - round(width / height, 4)) < 0.001, "Aspect ratio mismatch")
    return {"width": width, "height": height, "aspect_ratio": ratio, **metrics}


def validate_11(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    package_root = task_root / "packages"
    require(any(package_root.glob("humanize*")), "humanize package was not installed into the target")
    proof = proof_pass(task_root)
    require(proof.get("formatted") == "1,234,567", "humanize.intcomma output mismatch")
    require(str(proof.get("version")) == "4.12.3", "Installed humanize version mismatch")
    return {"package": "humanize==4.12.3", "formatted": proof["formatted"]}


def validate_12(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    fixture = task_root / "capability.txt"
    proof = proof_pass(task_root)
    discovered_names: set[str] = set()
    for action in successful_actions(actions):
        if action.get("tool") != "discover_capabilities":
            continue
        result = action_result(action)
        for item in result.get("powershell_commands", []):
            if isinstance(item, dict):
                discovered_names.add(str(item.get("name", "")).casefold())
    require(
        {"get-filehash", "convertto-json"}.issubset(discovered_names),
        "Capability discovery tool output did not contain both requested cmdlets",
    )
    require(proof.get("discovered_get_file_hash") is True, "Get-FileHash was not reported discovered")
    require(proof.get("discovered_convert_to_json") is True, "ConvertTo-Json was not reported discovered")
    observed_hash = proof.get("sha256", proof.get("sha256_uppercase", ""))
    require(str(observed_hash).upper() == sha256_file(fixture), "Capability task hash mismatch")
    return {"sha256": observed_hash, "capabilities": 2}


def validate_13(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    database = task_root / "records.db"
    require(database.is_file() and database.stat().st_size > 0, "SQLite database is missing")
    connection = sqlite3.connect(database)
    try:
        row_count, total = connection.execute("select count(*), sum(amount) from records").fetchone()
        group_rows = connection.execute(
            "select category, sum(amount) from records group by category order by category"
        ).fetchall()
    finally:
        connection.close()
    require(row_count == 50, "SQLite row count mismatch")
    expected_total = sum((index * 19) % 97 for index in range(1, 51))
    require(total == expected_total, "SQLite total mismatch")
    expected_groups = {"A": 0, "B": 0, "C": 0}
    for index in range(1, 51):
        expected_groups[("A", "B", "C")[index % 3]] += (index * 19) % 97
    observed_groups = {str(category): int(amount) for category, amount in group_rows}
    require(observed_groups == expected_groups, "SQLite category totals mismatch")
    proof = proof_pass(task_root)
    require(proof.get("rows") == 50 and proof.get("total") == expected_total, "SQLite proof mismatch")
    require(proof.get("category_totals") == expected_groups, "SQLite proof category totals mismatch")
    proof_path = (task_root / "proof.json").resolve()
    gate_path = (task_root / "task13-write-file-gate.txt").resolve()
    require(
        gate_path.read_text(encoding="utf-8") == "TASK13_WRITE_FILE_GATE",
        "SQLite write_file gate content mismatch",
    )
    gate_indices = [
        index
        for index, action in enumerate(actions)
        if action in successful_actions([action])
        and action.get("tool") == "write_file"
        and Path(str(action.get("arguments", {}).get("path", ""))).resolve() == gate_path
        and str(action.get("arguments", {}).get("content", "")) == "TASK13_WRITE_FILE_GATE"
    ]
    require(gate_indices, "SQLite write_file gate was not created by successful write_file")
    python_indices = [
        index
        for index, action in enumerate(actions)
        if action in successful_actions([action]) and action.get("tool") == "run_python"
    ]
    require(python_indices and gate_indices[0] < python_indices[0], "SQLite gate was not written before run_python")
    binary_indices = [
        index
        for index, action in enumerate(actions)
        if action in successful_actions([action])
        and action.get("tool") == "read_binary_file"
        and Path(str(action.get("arguments", {}).get("path", ""))).resolve() == database.resolve()
    ]
    require(binary_indices, "SQLite database was not inspected with successful read_binary_file")
    proof_indices = [
        index
        for index, action in enumerate(actions)
        if action in successful_actions([action])
        and action.get("tool") == "write_file"
        and Path(str(action.get("arguments", {}).get("path", ""))).resolve() == proof_path
    ]
    require(proof_indices, "SQLite proof.json was not created by successful write_file")
    binary_index = binary_indices[-1]
    proof_index = proof_indices[-1]
    require(
        proof_index == binary_index + 1,
        "SQLite proof.json was not written immediately after successful read_binary_file",
    )
    binary_result = action_result(actions[binary_index])
    binary_prefix = str(binary_result.get("data_base64", ""))
    require(binary_prefix, "SQLite binary read returned no base64 data")
    reported_bytes = int(binary_result.get("bytes", 0))
    require(reported_bytes > 0, "SQLite binary read reported no bytes")
    expected_binary_prefix = base64.b64encode(database.read_bytes()[:reported_bytes]).decode("ascii")
    require(
        binary_prefix == expected_binary_prefix,
        "SQLite binary read result does not match records.db",
    )
    require(
        proof.get("binary_prefix_base64") == binary_prefix,
        "SQLite proof binary prefix does not match the successful binary read",
    )
    return {"rows": row_count, "total": total, "groups": observed_groups}


def validate_14(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    input_root = ET.parse(task_root / "input.xml").getroot()
    input_records = input_root.findall("record")
    require(len(input_records) == 25, "XML source does not contain exactly 25 records")
    for expected_id, record in enumerate(input_records, 1):
        observed_id = record.get("id") or record.findtext("id", "0")
        require(int(observed_id) == expected_id, "XML source IDs are not exactly 1..25")
        require(record.findtext("marker") == "TASK14_XML", f"XML source marker mismatch at id {expected_id}")
        require(int(record.findtext("value", "0")) == expected_id * 7, f"XML source value mismatch at id {expected_id}")
    transformed = read_json(task_root / "filtered.json")
    expected_ids = [index for index in range(1, 26) if index % 2 == 0]
    require([item["id"] for item in transformed] == expected_ids, "XML transform IDs mismatch")
    require(all(item["marker"] == "TASK14_XML" for item in transformed), "XML transform marker mismatch")
    proof = proof_pass(task_root)
    require(proof.get("input_records") == 25, "XML input count mismatch")
    require(proof.get("output_records") == len(expected_ids), "XML output count mismatch")
    return {"input_records": 25, "output_records": len(expected_ids)}


def validate_15(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    target = task_root / "unicode.txt"
    require(target.is_file(), "unicode.txt is missing")
    require(not (task_root / "uuid.txt").exists(), "Alternate uuid.txt output is not allowed")
    require(target.read_text(encoding="utf-8") == UNICODE_TEXT, "Unicode content mismatch")
    proof = proof_pass(task_root)
    require(str(proof.get("python_sha256", "")).upper() == UNICODE_SHA256, "Python Unicode hash mismatch")
    require(str(proof.get("powershell_sha256", "")).upper() == UNICODE_SHA256, "PowerShell Unicode hash mismatch")
    require(proof.get("roundtrip_equal") is True, "Unicode round-trip was not reported equal")
    return {"sha256": UNICODE_SHA256, "characters": len(UNICODE_TEXT)}


def validate_16(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    successful = successful_actions(actions)
    starts = [action for action in successful if action.get("tool") == "start_process"]
    require(len(starts) == 1, "Expected exactly one successful start_process action")
    start = starts[0]
    start_arguments = start.get("arguments", {})
    start_result = action_result(start)
    executable = Path(str(start_result.get("executable", "")))
    require(
        executable.samefile(DEPLOYED_ROOT / "runtime" / "python" / "python.exe"),
        "Local HTTP server used the wrong executable",
    )
    require(
        start_arguments.get("allocate_free_tcp_port") is True,
        "start_process did not allocate a free TCP port",
    )
    requested_arguments = start_arguments.get("arguments", [])
    require(
        isinstance(requested_arguments, list)
        and "{FREE_TCP_PORT}" in requested_arguments,
        "start_process did not receive the free-port token",
    )
    port = int(start_result.get("tcp_port", 0))
    pid = int(start_result.get("pid", 0))
    require(1024 <= port <= 65535, "Local server port is invalid")
    require(pid > 0 and start_result.get("running") is True, "Local server did not start")
    resolved_arguments = start_result.get("arguments", [])
    require(
        isinstance(resolved_arguments, list)
        and resolved_arguments[:3] == ["-m", "http.server", str(port)],
        "Local server arguments did not use the allocated port",
    )
    web_root = (task_root / "web").resolve()
    require(
        "--bind" in resolved_arguments
        and "127.0.0.1" in resolved_arguments
        and "--directory" in resolved_arguments
        and str(web_root) in resolved_arguments,
        "Local server arguments did not bind and serve the expected directory",
    )
    require(
        Path(str(start_result.get("working_directory", ""))).resolve() == web_root,
        "Local server working directory mismatch",
    )
    require(
        Path(str(start_result.get("stdout_path", ""))).resolve()
        == (task_root / "server.stdout.log").resolve(),
        "Local server stdout log path mismatch",
    )
    require(
        Path(str(start_result.get("stderr_path", ""))).resolve()
        == (task_root / "server.stderr.log").resolve(),
        "Local server stderr log path mismatch",
    )
    require(
        Path(str(start_result.get("pid_path", ""))).resolve()
        == (task_root / "server.pid").resolve(),
        "Local server PID path mismatch",
    )

    expected_url = f"http://127.0.0.1:{port}/"
    fetches = [
        action
        for action in successful
        if action.get("tool") == "web_fetch"
        and action.get("arguments", {}).get("url") == expected_url
        and "LOCAL_SERVER_TASK_16" in str(action_result(action).get("content", ""))
    ]
    require(fetches, "No successful web_fetch proved the local server marker")
    observed_h1 = browser_extracted_text(actions, "h1")
    require(observed_h1 == "LOCAL_SERVER_TASK_16", "Browser did not extract the local h1")

    stops = [
        action
        for action in successful
        if action.get("tool") == "stop_process"
        and int(action.get("arguments", {}).get("pid", 0)) == pid
        and action_result(action).get("stopped") is True
    ]
    require(stops, "The exact local server PID was not stopped")

    proof = proof_pass(task_root)
    require(
        proof.get("web_fetch_marker") == "LOCAL_SERVER_TASK_16",
        "Local web_fetch marker mismatch",
    )
    require(proof.get("browser_h1") == observed_h1, "Local browser h1 mismatch")
    require(int(proof.get("port", 0)) == port, "Proof port does not match start_process")
    require(proof.get("server_stopped") is True, "Proof did not report server shutdown")
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(1)
        require(probe.connect_ex(("127.0.0.1", port)) != 0, "Local HTTP server was not stopped")
    require(not (task_root / "server.pid").exists(), "server.pid was not removed")
    require((task_root / "server.stdout.log").is_file(), "Missing server stdout log")
    stderr_path = task_root / "server.stderr.log"
    require(stderr_path.is_file(), "Missing server stderr log")
    require(
        "GET /" in stderr_path.read_text(encoding="utf-8", errors="replace"),
        "Server stderr log does not contain a readable HTTP request",
    )
    return {"port": port, "pid": pid, "server_stopped": True}


def validate_17(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    proof = proof_pass(task_root)
    require(str(proof.get("ollama_version", "")).strip(), "Ollama version is missing")
    require(proof.get("processor") == "100% GPU", "Ollama is not reported as 100% GPU")
    require(int(proof.get("context", 0)) == 32768, "Ollama context is not 32768")
    executable = Path(str(proof.get("executable", "")))
    require(executable.samefile(DEPLOYED_ROOT / "runtime" / "ollama" / "ollama.exe"), "Ollama executable path mismatch")
    require(str(proof.get("sha256", "")).upper() == sha256_file(executable), "Ollama executable hash mismatch")
    return {
        "ollama_version": proof["ollama_version"],
        "processor": proof["processor"],
        "context": proof["context"],
    }


def parse_hosts() -> list[tuple[str, list[str]]]:
    hosts_path = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "drivers" / "etc" / "hosts"
    records: list[tuple[str, list[str]]] = []
    for raw_line in hosts_path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) >= 2:
            records.append((fields[0], fields[1:]))
    return records


def validate_18(task_root: Path, _: list[dict[str, Any]]) -> dict[str, Any]:
    records = parse_hosts()
    expected_hosts = sorted({host for _, hosts in records for host in hosts})
    summary = read_json(task_root / "hosts-summary.json")
    require(summary.get("mapping_count") == len(records), "Hosts mapping count mismatch")
    observed_hosts = summary.get("hostnames", summary.get("unique_hostnames"))
    require(observed_hosts == expected_hosts, "Hosts hostname list mismatch")
    require("raw_lines" not in summary and "raw_content" not in summary, "Hosts report contains raw content")
    proof_pass(task_root)
    return {"mapping_count": len(records), "hostnames": expected_hosts}


def validate_19(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    manifest = read_json(task_root / "hashes.json")
    require(len(manifest) == 8, "Concurrent hash manifest does not contain 8 files")
    for index in range(1, 9):
        path = task_root / "inputs" / f"worker-{index:02d}.txt"
        expected = sha256_file(path)
        require(str(manifest[path.name]).upper() == expected, f"Hash mismatch for {path.name}")
    proof = proof_pass(task_root)
    successful_commands: list[str] = []
    script_pattern = re.compile(
        r"""(?ix)
        (?:-File\s+|&\s*)
        (?:
            "([^"]+\.ps1)"
            |
            '([^']+\.ps1)'
            |
            ([^\s;]+\.ps1)
        )
        """
    )
    resolved_task_root = task_root.resolve()
    for action in successful_actions(actions):
        if action.get("tool") != "run_powershell":
            continue
        command = str(action.get("arguments", {}).get("command", ""))
        successful_commands.append(command)
        for match in script_pattern.finditer(command):
            candidate_text = next(value for value in match.groups() if value)
            candidate = Path(candidate_text).resolve()
            if resolved_task_root not in candidate.parents or not candidate.is_file():
                continue
            successful_commands.append(
                candidate.read_text(encoding="utf-8-sig", errors="replace")
            )
    require(
        any(
            "Start-Job" in command
            and "0..3" in command
            and "Wait-Job" in command
            and "Receive-Job" in command
            for command in successful_commands
        ),
        "No successful PowerShell action proves the four-job worker implementation",
    )
    require(proof.get("worker_count") == 4, "Worker count is not 4")
    require(proof.get("hashes_match") is True, "PowerShell/Python hash comparison failed")
    return {"files": 8, "workers": 4}


def validate_20(task_root: Path, actions: list[dict[str, Any]]) -> dict[str, Any]:
    red = (task_root / "red.txt").read_text(encoding="utf-8", errors="replace")
    green = (task_root / "green.txt").read_text(encoding="utf-8", errors="replace")
    require("CHECK 5:" in red and "FAIL:" in red, "Red-phase log does not show all five checks and a failure")
    require("PASS: 5/5" in green, "Green-phase log does not show all five checks passing")
    tests_path = (task_root / "tests.py").resolve()
    tests_writes = []
    for action in actions:
        if action.get("tool") != "write_file" or action_result(action).get("ok") is not True:
            continue
        raw_path = action.get("arguments", {}).get("path")
        if raw_path and Path(str(raw_path)).resolve() == tests_path:
            tests_writes.append(action)
    require(
        len(tests_writes) == 1,
        f"tests.py must be written exactly once before the red run; observed {len(tests_writes)} successful writes",
    )
    bootstrap = (
        "import runpy,sys;"
        "sys.path.insert(0,sys.argv[1]);"
        "runpy.run_path(sys.argv[2],run_name='__main__')"
    )
    tests = subprocess.run(
        [
            str(AGENT_PYTHON),
            "-c",
            bootstrap,
            str(task_root),
            str(task_root / "tests.py"),
        ],
        cwd=task_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    require(tests.returncode == 0, f"Recovered project tests fail: {tests.stdout}\n{tests.stderr}")
    behavior_probe = subprocess.run(
        [
            str(AGENT_PYTHON),
            "-c",
            (
                "import json,sys;"
                "sys.path.insert(0,sys.argv[1]);"
                "import app;"
                "cases=[[1,2,3,4],[1,1,2,2,3],[],[-1,-2,0],[1.5,2.5]];"
                "print(json.dumps([app.normalize(case) for case in cases]))"
            ),
            str(task_root),
        ],
        cwd=task_root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
    )
    require(
        behavior_probe.returncode == 0,
        f"Independent normalize probe failed: {behavior_probe.stdout}\n{behavior_probe.stderr}",
    )
    observed = json.loads(behavior_probe.stdout)
    expected = [[3, 6, 9, 12], [3, 6, 9], [], [-6, -3, 0], [4, 7]]
    require(observed == expected, f"Independent normalize results mismatch: {observed!r}")
    failed_python = [
        action for action in actions
        if action.get("tool") == "run_python" and action_result(action).get("ok") is False
    ]
    passed_python = [
        action for action in actions
        if action.get("tool") == "run_python" and action_result(action).get("ok") is True
    ]
    require(failed_python, "No failed run_python action proves the red phase")
    require(passed_python, "No successful run_python action proves the green phase")
    failed_outputs = [
        f"{action_result(action).get('stdout', '')}\n{action_result(action).get('stderr', '')}"
        for action in failed_python
    ]
    require(
        any("CHECK 5:" in output and "FAIL:" in output and "Traceback" not in output for output in failed_outputs),
        "The failed run_python action did not prove a five-case behavioral red phase",
    )
    passed_outputs = [
        f"{action_result(action).get('stdout', '')}\n{action_result(action).get('stderr', '')}"
        for action in passed_python
    ]
    require(
        any("PASS: 5/5" in output for output in passed_outputs),
        "The successful run_python action did not prove all five behavioral checks passed",
    )
    proof_pass(task_root)
    return {"red_phase_logged": True, "green_phase_logged": True, "tests_exit_code": 0}


def common_prompt(task_root: Path, task_id: str, required_tools: tuple[str, ...]) -> str:
    tool_text = ", ".join(required_tools)
    proof_path = task_root / "proof.json"
    tool_gate = task_root / ".required-write-file-gate.txt"
    mandatory_gates: list[str] = []
    if "make_directory" in required_tools:
        mandatory_gates.append(
            "MANDATORY FIRST TOOL ACTION: call make_directory on the exact task root "
            f"`{task_root}` before using run_python, run_powershell, or native code to create it. "
            "This explicit tool call is audited and cannot be replaced by code."
        )
    if "write_file" in required_tools and task_id != "13-sqlite-binary-workflow":
        mandatory_gates.append(
            "MANDATORY WRITE-FILE GATE: before any run_python or run_powershell call, use write_file "
            f"to create `{tool_gate}` with exact UTF-8 content `WRITE_FILE_GATE_{task_id}`. "
            "This explicit tool call is audited; code or shell redirection is not a substitute."
        )
    return (
        "Act autonomously and complete this acceptance task on the real Windows machine. "
        "Do not give me commands or instructions. Use tools, inspect every result, retry reasonable "
        "failures, and verify the final state yourself. Work only inside "
        f"{task_root} except for explicitly named read-only system paths or temporary probes. "
        f"Use every one of these tools successfully at least once: {tool_text}. "
        f"Task identifier: {task_id}. Create the task root before other durable output. "
        + " ".join(mandatory_gates)
        + " "
        f"The persistent proof path is exactly {proof_path}; write final proof only there, after all "
        "other task steps and cleanup have been verified. "
    )


def build_tasks(tasks_root: Path, suite_id: str) -> list[Task]:
    tasks: list[Task] = []

    def add(
        task_id: str,
        title: str,
        required_tools: tuple[str, ...],
        minimum_actions: int,
        validator: Validator,
        instructions: str,
    ) -> None:
        root = tasks_root / task_id
        prompt = common_prompt(root, task_id, required_tools) + instructions.replace(
            "{TASK_ROOT}", str(root)
        )
        tasks.append(Task(task_id, title, prompt, required_tools, minimum_actions, validator))

    privileged = Path(r"C:\Windows\Temp") / f"local-ai-acceptance-{suite_id}-01"
    add(
        "01-privileged-system-probe",
        "Privileged filesystem, identity, verification, and cleanup",
        ("make_directory", "write_file", "read_file", "run_powershell", "delete_path"),
        6,
        validate_01,
        (
            f"Create the task root, then create the exact protected directory {privileged} with "
            f"make_directory. Use write_file on the exact path {privileged}\\probe.txt and write "
            "exactly LOCAL_AI_PRIVILEGED_TASK_01. Read that exact protected file back with "
            "read_file. Use run_powershell to run C:\\Windows\\System32\\whoami.exe and use this "
            "administrator check: $identity=[Security.Principal.WindowsIdentity]::GetCurrent(); "
            "$principal=New-Object Security.Principal.WindowsPrincipal($identity); "
            "$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator). "
            "Use delete_path recursively on "
            f"{privileged} and verify it no longer exists. Only then write the persistent proof.json "
            "with status PASS, token exactly 'LOCAL_AI_PRIVILEGED_TASK_01', identity, "
            "administrator=true, and cleaned=true."
        ),
    )
    add(
        "02-binary-roundtrip",
        "Deterministic binary creation, decoding, and hashing",
        ("make_directory", "write_binary_file", "read_binary_file", "run_python", "write_file"),
        6,
        validate_02,
        (
            f"Create the task directory. Use write_binary_file to create payload.bin from this exact "
            f"base64 payload: {BINARY_BASE64}. Read it back with read_binary_file. Use run_python to "
            f"decode and verify the bytes and SHA-256 {BINARY_SHA256}. Write proof.json with status "
            f"PASS, bytes={len(BINARY_PAYLOAD)}, and sha256={BINARY_SHA256}."
        ),
    )
    add(
        "03-recursive-search-index",
        "Nested file generation, recursive search, and indexing",
        ("make_directory", "run_python", "search_files", "list_directory", "write_file"),
        6,
        validate_03,
        (
            "Create the task directory with make_directory. Use run_python to generate exactly 12 "
            "UTF-8 files for i=1..12. The exact relative paths are "
            "tree\\level-1\\item-01.txt, tree\\level-2\\item-02.txt, "
            "tree\\level-0\\item-03.txt, tree\\level-1\\item-04.txt, "
            "tree\\level-2\\item-05.txt, tree\\level-0\\item-06.txt, "
            "tree\\level-1\\item-07.txt, tree\\level-2\\item-08.txt, "
            "tree\\level-0\\item-09.txt, tree\\level-1\\item-10.txt, "
            "tree\\level-2\\item-11.txt, and tree\\level-0\\item-12.txt. Each file must "
            "contain exactly TASK03_MARKER item={i} square={i*i} followed by one LF. Do not create "
            "an extra tree directory under any level directory. In the run_python generation loop, "
            'use this exact zero-padding scaffold: filename = f"item-{index:02d}.txt"; '
            'relative_path = Path("tree") / f"level-{index % 3}" / filename. Use index=1..12, '
            "create relative_path.parent, and write the marker content to task_root / relative_path. "
            "Use search_files to find "
            "TASK03_MARKER recursively and list_directory recursively to inventory the tree. Use "
            "write_file to create index.json with marker_count=12, file_count=12, and a sorted file "
            "list, then write proof.json with status PASS."
        ),
    )
    add(
        "04-data-pipeline",
        "Deterministic CSV generation and independently checkable aggregation",
        ("make_directory", "run_python", "read_file", "write_file"),
        5,
        validate_04,
        (
            "Create dataset.csv with columns number,category,value and 200 rows. For number 1..200, "
            "category is tuple (A,B,C)[number % 3], so number 1 -> B, number 2 -> C, number 3 -> A, "
            "and value is (number*17) modulo 101. Use run_python to generate and aggregate it, "
            "read_file to inspect the generated CSV, and write summary.json with this exact schema "
            "and values: "
            '"rows": 200, "total": 10016, "category_sums": {"A": 2772, "B": 3911, "C": 3333}. '
            "Do not rename any key and do not rotate the category mapping. Write "
            "proof.json with status PASS only after checking the summary against a second calculation."
        ),
    )
    add(
        "05-python-cli-project",
        "Generate and test a real Python JSON statistics CLI",
        ("make_directory", "write_file", "run_python", "search_files"),
        7,
        validate_05,
        (
            "Build summarize.py, fixture.json, and test_summarize.py. summarize.py must accept a JSON "
            "file containing a numeric list and print one compact JSON object with count, sum, mean, "
            "minimum, and maximum. fixture.json must contain [5,7,11,13,17]. Tests must exercise the "
            "CLI and its importable function. In test_summarize.py set "
            "task_root = Path(__file__).resolve().parent and insert str(task_root) at sys.path[0] "
            "before importing summarize so the tests work with the embedded portable Python. Then use "
            "the exact module import `import summarize`; do not use `from summarize import summarize`. "
            "Set fixture_path = task_root / 'fixture.json'. Test the importable function with the exact "
            "call `result = summarize.summarize(str(fixture_path))` and print FUNCTION_TEST_PASS only "
            "after all exact-result assertions pass. Test the real CLI using "
            "this direct scaffold: completed = subprocess.run([sys.executable, summarize.__file__, "
            "str(fixture_path)], cwd=task_root, capture_output=True, text=True, encoding='utf-8'). "
            "Assert returncode is zero, parse completed.stdout with json.loads, compare it with the exact "
            "expected object, and execute `print('CLI_TEST_PASS')` only after those assertions pass. "
            "test_summarize.py must be a short linear assertion script: do not define recovery helpers, "
            "do not use try or except anywhere, and do not include the words skip, skipped, or xfail "
            "anywhere in its source, including comments and strings. Any failed assertion or subprocess "
            "must terminate the script with a nonzero exit. Do not use python -c or -m. "
            "The tests must pass when launched with the task root as the current working directory. Use "
            "run_python to execute test_summarize.py as a real script through subprocess.run and separately "
            "execute summarize.py with fixture.json. Both executions must return code zero. Use search_files "
            "to verify no TODO, placeholder, SKIP, or XFAIL remains. Write proof.json with status PASS."
        ),
    )
    add(
        "06-powershell-cli-project",
        "Generate and execute a PowerShell 5.1 digest tool",
        ("make_directory", "write_file", "run_powershell", "read_file"),
        6,
        validate_06,
        (
            "Create fixture.txt with exactly three lines: alpha, beta, gamma. Create "
            "Get-InventoryDigest.ps1 compatible with Windows PowerShell 5.1. It must accept -InputPath "
            "and emit compact JSON containing lineCount and uppercase SHA-256 with no separators. "
            "Use this exact PS5-safe core in the script: $resolved = (Resolve-Path -LiteralPath "
            "$InputPath).Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); "
            "$lines = [System.IO.File]::ReadAllLines($resolved); "
            "$sha = [System.Security.Cryptography.SHA256]::Create(); "
            "try { $hashBytes = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }; "
            "$sha256 = -join ($hashBytes | ForEach-Object { $_.ToString('X2') }); "
            "[ordered]@{ lineCount = $lines.Count; sha256 = $sha256 } | ConvertTo-Json -Compress. "
            "Do not count lines by splitting a trailing newline, do not put hyphens in the hash, and "
            "do not place -join after ForEach-Object without parentheses. Use run_powershell first to "
            "parse the script with [scriptblock]::Create((Get-Content -LiteralPath "
            "'.\\Get-InventoryDigest.ps1' -Raw)) and then execute it under Windows PowerShell 5.1. "
            "Parse the emitted JSON and verify lineCount is 3 and sha256 is 64 uppercase hexadecimal "
            "characters. Then read_file to inspect the fixture. Write proof.json with status PASS and "
            "the observed result."
        ),
    )
    add(
        "07-archive-transaction",
        "Copy, move, archive, extract, inventory, and cleanup transaction",
        ("make_directory", "run_powershell", "copy_path", "move_path", "list_directory", "delete_path", "write_file"),
        9,
        validate_07,
        (
            "Use these exact distinct paths: staging=`{TASK_ROOT}\\staging`, archive=`{TASK_ROOT}\\bundle.zip`, "
            "and extracted=`{TASK_ROOT}\\extracted`. Create staging with alpha.txt='alpha-07', nested\\beta.txt='beta-07', and "
            "nested\\gamma.txt='gamma-07'. Keep all three staging files in place until bundle.zip has "
            "been created. Do not move beta.txt or gamma.txt out of staging before compression. To "
            "exercise copy_path without changing staging, copy staging\\alpha.txt to copy-probe.txt. "
            "To exercise move_path without changing staging, create move-source.txt containing move-07 "
            "and move it to move-proof.txt. Use run_powershell with this archive sequence: set $staging "
            "to the exact staging path above; then run Compress-Archive -Path (Join-Path $staging '*') "
            "to create the exact archive path above; then run Expand-Archive from that archive to the exact "
            "extracted path above, never to task root or staging. Use list_directory recursively to "
            "verify extracted contains all three files. "
            "The ZIP must contain exactly alpha.txt, nested/beta.txt, and nested/gamma.txt, preserving "
            "the nested directory rather than flattening it. Use delete_path recursively on staging only. "
            "After that successful delete_path, do not issue any further operation against staging, nested, "
            "alpha.txt, beta.txt, or gamma.txt. Keep extracted intact for independent validation; do not delete "
            "or move extracted or any file below it. Write proof.json with status PASS and those three sorted archive entries."
        ),
    )
    add(
        "08-web-fetch-download-parse",
        "HTTPS fetch, download, HTML parsing, and persisted proof",
        ("make_directory", "web_fetch", "download_file", "run_python", "write_file"),
        6,
        validate_08,
        (
            "Fetch https://example.com with web_fetch and download the same URL to example.html with "
            "download_file. Use run_python with an HTML parser to independently extract the title and "
            "h1 from the downloaded file. Write proof.json with status PASS, title='Example Domain', "
            "h1='Example Domain', HTTP status, and downloaded byte count. The downloaded byte-count "
            "JSON key must be named exactly bytes."
        ),
    )
    add(
        "09-browser-dom-verification",
        "Real browser navigation and DOM extraction",
        ("make_directory", "browser_automation", "write_file", "read_file"),
        4,
        validate_09,
        (
            "Use one browser_automation call with top-level url https://example.com and actions exactly "
            '[{"action":"goto","url":"https://example.com"},{"action":"wait_for_selector","selector":"h1"},'
            '{"action":"extract","selector":"h1"},{"action":"extract","selector":"p:nth-of-type(1)"}]. '
            "Capture the page title from the same browser result. Do not take a screenshot. Write proof.json with "
            "status PASS, title='Example Domain', h1='Example Domain', and paragraph_contains set exactly "
            "to the full first-paragraph text returned by browser_automation. Do not substitute a keyword "
            "or remembered website wording. Read proof.json back with read_file."
        ),
    )
    add(
        "10-desktop-nonvisual-probe",
        "Safe desktop geometry inspection without screenshots",
        ("make_directory", "desktop_automation", "run_python", "write_file"),
        5,
        validate_10,
        (
            "Use one desktop_automation call containing screen_size and position actions. Do not click, "
            "type, move the pointer, or take a screenshot. The cursor may be on a secondary monitor, so "
            "do not assume its coordinates fit inside the primary screen_size result. Use run_python with "
            "ctypes and call exactly `ctypes.windll.user32.SetProcessDPIAware()` before reading metrics. "
            "Read virtual_left, virtual_top, virtual_width, virtual_height from GetSystemMetrics indexes "
            "76, 77, 78, and 79 respectively. Copy width, height, cursor_x, and cursor_y exactly from the "
            "successful desktop_automation result into the run_python calculation. Do not call GetCursorPos "
            "or replace the observed cursor coordinates. Calculate the primary-screen ratio with the exact "
            "expression `aspect_ratio = round(width / height, 4)`, not virtual_width / virtual_height. "
            "Use run_python to verify the observed cursor is inside the virtual desktop bounds. Write "
            "proof.json with status PASS, width, height, cursor_x, cursor_y, aspect_ratio, virtual_left, "
            "virtual_top, virtual_width, and virtual_height."
        ),
    )
    package_target = tasks_root / "11-isolated-package-install" / "packages"
    add(
        "11-isolated-package-install",
        "Online package installation into an isolated task target",
        ("make_directory", "install_python_package", "run_python", "write_file"),
        5,
        validate_11,
        (
            f"Create that exact packages directory before calling install_python_package, then install "
            f"exactly humanize==4.12.3 with target_directory exactly {package_target}. Do not install "
            "into the task root or any environment-wide site-packages directory. Use run_python with "
            "that exact packages target prepended to sys.path to import "
            "humanize, verify version 4.12.3, and compute humanize.intcomma(1234567). Write proof.json "
            "with status PASS, version='4.12.3', and formatted='1,234,567'."
        ),
    )
    add(
        "12-capability-discovery",
        "Discover installed commands, then use them for a verified digest",
        ("make_directory", "write_file", "discover_capabilities", "run_powershell"),
        6,
        validate_12,
        (
            "Write capability.txt containing exactly LOCAL_AI_CAPABILITY_12. Call discover_capabilities "
            "for PowerShell hashing and JSON commands and confirm Get-FileHash and ConvertTo-Json are "
            "available. Then use run_powershell with those commands to hash capability.txt and emit "
            "JSON. Use the hash returned directly by Get-FileHash without reimplementing SHA-256. "
            "Write proof.json with status PASS, discovered_get_file_hash=true, "
            'discovered_convert_to_json=true, and the uppercase SHA-256 under a JSON key named exactly "sha256".'
        ),
    )
    add(
        "13-sqlite-binary-workflow",
        "Create, query, and inspect a binary SQLite database",
        ("make_directory", "run_python", "read_binary_file", "write_file"),
        5,
        validate_13,
        (
            "Before any run_python call, use write_file to create task13-write-file-gate.txt containing "
            "exactly TASK13_WRITE_FILE_GATE and inspect the successful tool result. The successful gate "
            "write must occur before every run_python action. Then use run_python "
            "and sqlite3 to create records.db with table records(id,category,amount) and "
            "50 rows. Use this exact category expression: category = ('A','B','C')[id % 3]. Never use "
            "(id - 1) % 3. amount=(id*19) modulo 97. The exact category totals must be A=768, B=800, "
            "C=832 and the grand total must be 2400. Query row "
            "count, total, and category totals. Use read_binary_file on records.db and retain a short "
            "base64 prefix as proof that it is binary. Call write_file immediately after "
            "read_binary_file to create proof.json with status PASS, rows, total, category_totals, "
            "and binary_prefix_base64. Do not merely say that you will write proof.json; execute the "
            "write_file tool call and inspect its successful result before answering. The task cannot "
            "pass without a successful write_file action whose path is exactly proof.json, and the "
            "proof binary prefix must exactly equal the data_base64 returned by read_binary_file."
        ),
    )
    add(
        "14-xml-json-transform",
        "Build XML, transform filtered records to JSON, and search results",
        ("make_directory", "write_file", "run_python", "read_file", "search_files"),
        7,
        validate_14,
        (
            "Generate input.xml algorithmically in one run_python loop with exactly 25 record "
            'elements, ids 1..25. Use an id attribute only: <record id="1"> through <record id="25">; '
            "do not create <id> child elements. Do not build XML with string concatenation. Create a "
            '<records> root with xml.etree.ElementTree, create each record with '
            'ET.SubElement(root, "record", {"id": str(index)}), add marker and value children with '
            "ET.SubElement, and serialize once with ElementTree.write so attributes are quoted and there "
            "is exactly one document root. Every record must have this exact child structure: "
            '<record id="1"><marker>TASK14_XML</marker><value>7</value></record>, with the id and value '
            "adjusted for each record. Do not store TASK14_XML as bare record text. Before writing, "
            "assert that the generated ids are "
            "exactly list(range(1, 26)), every marker is TASK14_XML, and every value equals its record "
            "id times 7. Every record marker must be exactly TASK14_XML; do not introduce test variants "
            "or alternate marker text. Use run_python XML parsing to select even ids, sort ascending, and write "
            "filtered.json as a JSON array of objects with id, marker, value. Read filtered.json and "
            "use search_files to find TASK14_XML in the task tree. Write proof.json with status PASS, "
            "input_records=25, and output_records=12."
        ),
    )
    codepoints = ",".join(str(value) for value in UNICODE_CODEPOINTS)
    unicode_task_root = tasks_root / "15-unicode-encoding"
    add(
        "15-unicode-encoding",
        "UTF-8 multilingual round-trip with independent hash implementations",
        ("make_directory", "run_python", "read_file", "run_powershell", "write_file"),
        7,
        validate_15,
        (
            f"Use run_python to construct unicode.txt from these Unicode code points in order: "
            f"{codepoints}. Encode as UTF-8 without a BOM. Copy this exact Python assignment without "
            f"retyping or changing any number: code_points = [{codepoints}]. The fifth integer is "
            "108 ('l'), never 104 ('h'), and the decoded text must begin exactly 'Local AI:', never "
            "'Locah AI:'. Use this exact path and write scaffold: `"
            f'from pathlib import Path; task_root = Path(r"{unicode_task_root}"); '
            'target_path = task_root / "unicode.txt"; '
            'text = "".join(chr(value) for value in code_points); '
            'target_path.write_bytes(text.encode("utf-8"))`. '
            "Do not create uuid.txt or use any alternate filename. Writing the bytes is mandatory; "
            "do not stop after assigning utf8_bytes. This binary write keeps code point 10 as LF. "
            "Use read_file to verify the visible content and explicitly reject any result beginning "
            "with Locah. Use run_python and run_powershell Get-FileHash independently to compute "
            f"SHA-256. Both actual hashes must equal {UNICODE_SHA256}; if either differs, fix the file "
            "and recompute instead of continuing. The proof hashes must come from the actual successful "
            "tool outputs; never copy the expected hash as a substitute for an observed result. Write "
            "proof.json with status PASS, the actual python_sha256, the actual powershell_sha256, and "
            "roundtrip_equal=true. The final proof.json must be created with write_file, not run_python."
        ),
    )
    add(
        "16-local-http-roundtrip",
        "Create a private local web service, test it twice, then stop it",
        (
            "make_directory",
            "write_file",
            "start_process",
            "web_fetch",
            "browser_automation",
            "stop_process",
            "delete_path",
        ),
        9,
        validate_16,
        (
            "Create web\\index.html with exactly this structural body and only one h1: "
            "<html><head><title>LOCAL_SERVER_TASK_16</title></head>"
            "<body><h1>LOCAL_SERVER_TASK_16</h1></body></html>. Call start_process "
            f"exactly once with executable={AGENT_PYTHON}, "
            "arguments=['-m','http.server','{FREE_TCP_PORT}','--bind','127.0.0.1','--directory',WEB_PATH], "
            "working_directory=WEB_PATH, stdout_path=TASK_ROOT\\server.stdout.log, "
            "stderr_path=TASK_ROOT\\server.stderr.log, pid_path=TASK_ROOT\\server.pid, "
            "allocate_free_tcp_port=true, and wait_seconds=2. Do not use run_python or run_powershell "
            "to launch the server. Read the successful start_process result and use its exact pid and "
            "tcp_port. Use web_fetch on http://127.0.0.1:PORT/. Then use one browser_automation call "
            "with top-level url=http://127.0.0.1:PORT/ and actions exactly "
            '[{"action":"goto"},{"action":"wait_for_selector","selector":"h1"},'
            '{"action":"extract","selector":"h1"}] to verify the marker and DOM. '
            "Do not add attribute or value fields to the extract action. Then call stop_process with the exact returned pid, "
            "timeout_seconds=10, and include_children=true. Require its stopped result to be true, use "
            "delete_path on server.pid, and write proof.json with status PASS, the returned tcp_port as port, "
            "web_fetch_marker='LOCAL_SERVER_TASK_16', "
            "browser_h1='LOCAL_SERVER_TASK_16', and server_stopped=true."
        ),
    )
    add(
        "17-ollama-runtime-inspection",
        "Inspect the live private model service, process, executable, GPU, and context",
        ("make_directory", "path_info", "run_powershell", "web_fetch", "write_file"),
        7,
        validate_17,
        (
            "Use path_info on the deployed Ollama executable. Use web_fetch on "
            "http://127.0.0.1:11435/api/version. Use run_powershell to identify the listener PID, "
            "confirm its executable path, compute its SHA-256, and run the private ollama.exe ps. "
            "Parse the qwen3.5:9b row and write proof.json with status PASS, ollama_version, PID, "
            "executable, sha256, processor exactly '100% GPU', and context=32768."
        ),
    )
    add(
        "18-hosts-sanitized-summary",
        "Read a protected system file and produce a sanitized structural summary",
        ("make_directory", "read_file", "run_python", "write_file", "search_files"),
        6,
        validate_18,
        (
            "Read C:\\Windows\\System32\\drivers\\etc\\hosts with read_file. Use run_python to parse "
            "non-comment mappings. Write hosts-summary.json with exactly the keys mapping_count and "
            "hostnames, where mapping_count is the number of non-comment mapping lines, including "
            "duplicate hostnames, and hostnames is the sorted unique hostname list. Do not include raw lines "
            "or raw content in hosts-summary.json or proof.json. Use search_files to verify "
            "localhost appears in the sanitized report. Write proof.json with status PASS. Do not "
            "create any other file containing the raw hosts content."
        ),
    )
    add(
        "19-concurrent-hash-workers",
        "Parallel PowerShell workers cross-checked by Python",
        ("make_directory", "run_python", "run_powershell", "read_file", "write_file"),
        7,
        validate_19,
        (
            "Use run_python to generate 8 deterministic UTF-8 files inputs\\worker-01.txt through "
            "worker-08.txt, each containing its filename repeated its index times. In that generation "
            'code use exactly: for index in range(1, 9); filename = f"worker-{index:02d}.txt"; '
            "content = filename * index. Do not start at zero and do not create worker-00.txt. "
            "Use one single "
            "run_powershell tool call with timeout_seconds at least 120 and exactly 4 background jobs "
            "to compute SHA-256 values for all 8 files. Never split job creation, waiting, receiving, "
            "cleanup, or JSON writing across separate run_powershell calls because job state is "
            "process-local. Copy this "
            "proven Windows PowerShell 5.1 structure literally, changing only $taskRoot to the exact "
            "task root from this prompt: "
            "$taskRoot = '<TASK_ROOT>'; "
            "$inputs = @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'inputs') -File | Sort-Object Name); "
            "$jobs = foreach ($worker in 0..3) { "
            "$first = $inputs[$worker].FullName; $second = $inputs[$worker + 4].FullName; "
            "Start-Job -ArgumentList $first, $second -ScriptBlock { param($FirstPath,$SecondPath) "
            "foreach ($path in @($FirstPath,$SecondPath)) { [pscustomobject]@{ "
            "Name = [IO.Path]::GetFileName($path); "
            "Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } } } }; "
            "$results = @($jobs | Wait-Job | Receive-Job); $jobs | Remove-Job -Force; "
            "$ordered = [ordered]@{}; $results | Sort-Object Name | ForEach-Object { "
            "$ordered[$_.Name] = $_.Hash }; $ordered | ConvertTo-Json | "
            "Set-Content -LiteralPath (Join-Path $taskRoot 'hashes.json') -Encoding UTF8. "
            "Do not change foreach to for, do not read .FullName from a path string inside the job, "
            "and do not receive a job before Wait-Job completes. Do not precompute or replace the PowerShell hashes with "
            "Python. Use read_file to inspect hashes.json and run_python to "
            "independently recompute and compare every hash, but do not let that run_python call create "
            "proof.json. After the successful comparison, use write_file, not run_python, to create "
            "proof.json as the final task action with status PASS, worker_count=4, file_count=8, "
            "and hashes_match=true."
        ),
    )
    add(
        "20-red-green-recovery",
        "Autonomous red-green debugging of a generated mini-project",
        ("make_directory", "write_file", "run_python", "run_powershell", "search_files", "list_directory"),
        10,
        validate_20,
        (
            "Create a mini-project with app.py, config.json, tests.py, and README.md. Work in this exact "
            "order. First write config.json as {\"multiplier\":3}. Then write the initial app.py with a "
            "deliberate bug: it must not read config.json and normalize(values) must return "
            "sorted(set(int(value * 2) for value in values)). Next create tests.py exactly once and never "
            "write or edit it again. Do not use unittest, pytest, or test discovery. tests.py must insert "
            "str(Path(__file__).resolve().parent) at sys.path[0] before importing app, define these five "
            "case pairs in order: ([1,2,3,4],[3,6,9,12]), ([1,1,2,2,3],[3,6,9]), ([],[]), "
            "([-1,-2,0],[-6,-3,0]), ([1.5,2.5],[4,7]); loop over them with enumerate(...,1); print "
            "exactly CHECK {index}: actual={actual} expected={expected} for every case; collect each "
            "mismatch; if mismatches exist print a line beginning FAIL: and exit 1; otherwise print "
            "exactly PASS: 5/5 and exit 0. This is a direct manual runner, so all five checks must execute. "
            "Write README.md before running tests. For the red "
            "run, use run_python with this exact process pattern, replacing TASK_ROOT with the absolute "
            "task root: import subprocess,sys; from pathlib import Path; task_root=Path(r'TASK_ROOT'); "
            "p=subprocess.run([sys.executable, str(task_root / 'tests.py')], cwd=task_root, "
            "capture_output=True, text=True); print(p.stdout,end=''); print(p.stderr,end='',file=sys.stderr); "
            "sys.exit(p.returncode). This run_python action must print CHECK 5:, print FAIL:, and fail "
            "because of the deliberate app.py multiplier=2 bug, "
            "not because of an import, path, shell, or __file__ error. Next use run_powershell once for "
            "the red native rerun. In that PowerShell command set $taskRoot to the absolute task root, "
            "set $python=(Get-Command python.exe).Source, then run "
            "$output=@(& $python (Join-Path $taskRoot 'tests.py') 2>&1 | ForEach-Object { $_.ToString() }); "
            "$exitCode=$LASTEXITCODE; write (($output -join [Environment]::NewLine) + "
            "[Environment]::NewLine) to red.txt with "
            "[IO.File]::WriteAllText(...,(New-Object Text.UTF8Encoding($false))); emit every output line "
            "and NATIVE_EXIT_CODE=$exitCode; throw if $exitCode is zero. Do not use python -c or embed "
            "Python source in PowerShell. Diagnose and fix only app.py with write_file. "
            "The fixed app.py must read multiplier from config.json beside app.py and return "
            "sorted(set(int(value * multiplier) for value in values)); do not edit tests.py after the "
            "first red run. Repeat the exact subprocess.run pattern through "
            "run_python for the green run, which must exit successfully. Use run_powershell once more "
            "with the same direct native invocation and UTF-8 capture pattern, writing green.txt and "
            "throwing unless the captured native exit code is zero. Do not create helper Python or "
            "PowerShell scripts. Use search_files to "
            "confirm no TODO/placeholder remains and list_directory recursively to inventory the "
            "project. Write proof.json with status PASS only after the green run."
        ),
    )
    return tasks


def terminate_process_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    taskkill = Path(os.environ.get("WINDIR", r"C:\Windows")) / "System32" / "taskkill.exe"
    subprocess.run(
        [str(taskkill), "/PID", str(process.pid), "/T", "/F"],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def read_action_delta(offset: int) -> list[dict[str, Any]]:
    if not ACTION_LOG.exists():
        return []
    with ACTION_LOG.open("rb") as handle:
        handle.seek(offset)
        payload = handle.read().decode("utf-8", errors="replace")
    actions: list[dict[str, Any]] = []
    for line in payload.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            actions.append(value)
    return actions


def invoke_task(task: Task, log_path: Path, max_turns: int, timeout_seconds: int) -> tuple[int, float]:
    command = [
        "powershell.exe",
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(LAUNCHER),
        "--prompt",
        task.prompt,
        "--max-turns",
        str(max_turns),
    ]
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8", newline="\n") as log:
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        assert process.stdout is not None
        lines: queue.Queue[str | None] = queue.Queue()

        def read_output() -> None:
            try:
                for line in process.stdout:
                    lines.put(line)
            finally:
                lines.put(None)

        reader = threading.Thread(target=read_output, name=f"acceptance-output-{task.task_id}", daemon=True)
        reader.start()
        parent_exited_at: float | None = None
        try:
            while True:
                elapsed = time.monotonic() - started
                if elapsed > timeout_seconds:
                    terminate_process_tree(process)
                    raise TimeoutError(f"Task exceeded {timeout_seconds} seconds")
                try:
                    line = lines.get(timeout=0.25)
                except queue.Empty:
                    line = ""
                if line is None:
                    if process.poll() is not None:
                        break
                    continue
                if line:
                    rendered = line.rstrip("\r\n")
                    timestamp = datetime.now().strftime("%H:%M:%S")
                    output = f"[{timestamp}] {rendered}"
                    print(console_text(output), flush=True)
                    log.write(output + "\n")
                    log.flush()
                if process.poll() is not None:
                    if parent_exited_at is None:
                        parent_exited_at = time.monotonic()
                    if lines.empty() and time.monotonic() - parent_exited_at >= 0.5:
                        break
            exit_code = process.wait(timeout=30)
        finally:
            if process.poll() is None:
                terminate_process_tree(process)
            process.stdout.close()
            reader.join(timeout=2)
    return exit_code, time.monotonic() - started


def validate_action_contract(task: Task, actions: list[dict[str, Any]]) -> dict[str, Any]:
    successful = successful_actions(actions)
    successful_tools = [str(action.get("tool", "")) for action in successful]
    missing = sorted(set(task.required_tools) - set(successful_tools))
    require(not missing, f"Missing successful required tools: {missing}")
    require(
        len(successful) >= task.minimum_successful_actions,
        f"Only {len(successful)} successful actions; expected at least {task.minimum_successful_actions}",
    )
    return {
        "successful_action_count": len(successful),
        "successful_tools": sorted(set(successful_tools)),
    }


def is_administrator() -> bool:
    if os.name != "nt":
        return False
    import ctypes

    return bool(ctypes.windll.shell32.IsUserAnAdmin())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--agent-root",
        type=Path,
        default=Path(os.environ.get("UNRESTRICTED_AGENT_ROOT", DEFAULT_DEPLOYED_ROOT)),
        help="Installed local-agent root to exercise",
    )
    parser.add_argument("--root", type=Path, default=None, help="Validation artifact root")
    parser.add_argument("--only", default="", help="Comma-separated task ids to run")
    parser.add_argument("--max-turns", type=int, default=48)
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--suite-id", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    configure_deployment_root(args.agent_root)
    suite_id = args.suite_id or datetime.now().strftime("%Y%m%d-%H%M%S")
    validation_root = args.root.expanduser().resolve() if args.root else DEFAULT_VALIDATION_ROOT
    suite_root = validation_root / f"complex-acceptance-{suite_id}"
    tasks_root = suite_root / "tasks"
    logs_root = suite_root / "_harness_logs"
    tasks = build_tasks(tasks_root, suite_id)

    if args.list:
        for task in tasks:
            print(f"{task.task_id}: {task.title}")
        print(f"TOTAL_TASKS: {len(tasks)}")
        return 0

    require(is_administrator(), "Run the acceptance harness from an elevated administrator shell")
    require(LAUNCHER.is_file(), f"Missing launcher: {LAUNCHER}")
    require(AGENT_PYTHON.is_file(), f"Missing private Python: {AGENT_PYTHON}")
    require(ACTION_LOG.is_file(), f"Missing action log: {ACTION_LOG}")

    selected = {item.strip() for item in args.only.split(",") if item.strip()}
    if selected:
        known = {task.task_id for task in tasks}
        unknown = sorted(selected - known)
        require(not unknown, f"Unknown task ids: {unknown}")
        tasks = [task for task in tasks if task.task_id in selected]

    if suite_root.exists():
        shutil.rmtree(suite_root)
    tasks_root.mkdir(parents=True)
    logs_root.mkdir(parents=True)

    summary: dict[str, Any] = {
        "suite_id": suite_id,
        "started_at": datetime.now().astimezone().isoformat(),
        "launcher": str(LAUNCHER),
        "model": "qwen3.5:9b",
        "task_count": len(tasks),
        "results": [],
    }
    failures = 0

    print(f"COMPLEX_ACCEPTANCE_START: {suite_id}", flush=True)
    print(f"TASK_COUNT: {len(tasks)}", flush=True)
    print(f"SUITE_ROOT: {suite_root}", flush=True)

    for index, task in enumerate(tasks, start=1):
        print("", flush=True)
        print(f"=== TASK {index:02d}/{len(tasks):02d}: {task.task_id} ===", flush=True)
        print(task.title, flush=True)
        log_path = logs_root / f"{task.task_id}.log"
        action_offset = ACTION_LOG.stat().st_size
        result: dict[str, Any] = {
            "task_id": task.task_id,
            "title": task.title,
            "log": str(log_path),
            "status": "FAIL",
        }
        try:
            exit_code, duration = invoke_task(task, log_path, args.max_turns, args.timeout_seconds)
            actions = read_action_delta(action_offset)
            result["exit_code"] = exit_code
            result["duration_seconds"] = round(duration, 3)
            result["action_count"] = len(actions)
            require(exit_code == 0, f"Agent process exited with code {exit_code}")
            result["action_contract"] = validate_action_contract(task, actions)
            task_root = tasks_root / task.task_id
            result["verification"] = task.validator(task_root, actions)
            result["status"] = "PASS"
            print(f"TASK_RESULT: PASS {task.task_id}", flush=True)
        except Exception as exc:
            failures += 1
            result["error"] = f"{type(exc).__name__}: {exc}"
            print(f"TASK_RESULT: FAIL {task.task_id}: {result['error']}", flush=True)
            if not args.keep_going:
                summary["results"].append(result)
                break
        summary["results"].append(result)
        (suite_root / "summary.partial.json").write_text(
            json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    summary["finished_at"] = datetime.now().astimezone().isoformat()
    summary["passed"] = sum(item["status"] == "PASS" for item in summary["results"])
    summary["failed"] = sum(item["status"] != "PASS" for item in summary["results"])
    summary["status"] = "PASS" if summary["failed"] == 0 and len(summary["results"]) == len(tasks) else "FAIL"
    summary_path = suite_root / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("", flush=True)
    print(f"SUMMARY: {summary_path}", flush=True)
    print(f"PASSED: {summary['passed']}", flush=True)
    print(f"FAILED: {summary['failed']}", flush=True)
    print(f"COMPLEX_ACCEPTANCE_RESULT: {summary['status']}", flush=True)
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
