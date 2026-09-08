#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const proxyPath = process.env.NVIDIA_PROXY_UNDER_TEST ||
  "C:\\Users\\micha\\.config\\opencode\\nvidia-proxy.cjs";

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.removeListener("error", reject);
      resolve(server.address().port);
    });
  });
}

function closeServer(server) {
  return new Promise(resolve => server.close(() => resolve()));
}

function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitFor(fn, timeoutMs, label) {
  const deadline = Date.now() + timeoutMs;
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const value = await fn();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await delay(25);
  }
  throw new Error(`${label} timed out${lastError ? `: ${lastError.message}` : ""}`);
}

function requestJson(port, pathname) {
  return new Promise((resolve, reject) => {
    const req = http.get({
      hostname: "127.0.0.1",
      port,
      path: pathname,
      timeout: 1000,
    }, res => {
      const chunks = [];
      res.on("data", chunk => chunks.push(chunk));
      res.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (error) {
          reject(error);
        }
      });
    });
    req.on("timeout", () => req.destroy(new Error("request timeout")));
    req.on("error", reject);
  });
}

function post(port, payload, options = {}) {
  const body = Buffer.from(JSON.stringify(payload));
  let req;
  const result = new Promise((resolve, reject) => {
    const started = Date.now();
    req = http.request({
      hostname: "127.0.0.1",
      port,
      path: "/v1/chat/completions",
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-length": body.length,
      },
    }, res => {
      const chunks = [];
      let firstDataMs = null;
      res.on("data", chunk => {
        if (firstDataMs === null) firstDataMs = Date.now() - started;
        chunks.push(chunk);
        if (options.abortOnFirstData) req.destroy();
      });
      res.on("end", () => resolve({
        statusCode: res.statusCode,
        headers: res.headers,
        body: Buffer.concat(chunks).toString("utf8"),
        firstDataMs,
        elapsedMs: Date.now() - started,
      }));
      res.on("error", error => {
        if (options.abortOnFirstData) {
          resolve({
            statusCode: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString("utf8"),
            firstDataMs,
            elapsedMs: Date.now() - started,
            aborted: true,
          });
        } else {
          reject(error);
        }
      });
    });
    req.on("error", error => {
      if (options.abortOnFirstData) {
        resolve({ aborted: true, firstDataMs: null, elapsedMs: Date.now() - started });
      } else {
        reject(error);
      }
    });
    req.end(body);
  });
  return { req, result };
}

function parseCompletion(text, stream, model, firstDataOnly = false) {
  const values = [];
  let done = !stream;
  let parseError = null;
  if (stream) {
    for (const frame of text.split(/\r?\n\r?\n/)) {
      const data = frame.split(/\r?\n/).filter(line => line.startsWith("data:"))
        .map(line => line.slice(5).trimStart()).join("\n").trim();
      if (!data) continue;
      if (data === "[DONE]") { done = true; continue; }
      try { values.push(JSON.parse(data)); }
      catch (_) { parseError = "malformed provider JSON"; }
    }
  } else {
    try { values.push(JSON.parse(text)); }
    catch (_) { parseError = text.trim().slice(0, 200) || "empty provider response"; }
  }
  const models = new Set();
  const calls = new Map();
  let content = "";
  let reasoningContent = "";
  let finishReason = null;
  let upstreamError = null;
  let sawChoices = false;
  for (const value of values) {
    if (value.error || value.type === "error" || Number(value.status) >= 400) {
      const error = value.error || value;
      upstreamError = { code: error.code || error.status || value.status || null,
        message: typeof error === "string" ? error : error.message || error.detail || "upstream error" };
      continue;
    }
    if (value.model) models.add(String(value.model));
    for (const choice of value.choices || []) {
      if (choice.index !== 0) continue;
      sawChoices = true;
      if (choice.finish_reason != null) finishReason = choice.finish_reason;
      const delta = choice.delta || choice.message || {};
      if (typeof delta.content === "string") content += delta.content;
      reasoningContent += String(delta.reasoning_content || delta.reasoning || "");
      for (const [offset, call] of (delta.tool_calls || []).entries()) {
        const index = Number.isInteger(call.index) ? call.index : offset;
        const current = calls.get(index) || { id: "", type: "function", function: { name: "", arguments: "" } };
        if (call.id) current.id += call.id;
        if (call.type) current.type = call.type;
        if (call.function?.name) current.function.name += call.function.name;
        if (typeof call.function?.arguments === "string") current.function.arguments += call.function.arguments;
        calls.set(index, current);
      }
    }
  }
  const modelMatches = models.size === 1 && models.has(model);
  const toolCalls = [...calls.values()];
  let toolArgumentsValid = toolCalls.length === 1;
  for (const call of toolCalls) {
    let args = null;
    try { args = JSON.parse(call.function.arguments); } catch (_) {}
    toolArgumentsValid = toolArgumentsValid && !!call.id && call.type === "function" &&
      call.function.name === "report_status" && !!args && !Array.isArray(args) &&
      args.status === "ready" && Object.keys(args).length === 1;
  }
  let error = upstreamError?.message || parseError;
  if (!error && !modelMatches) error = "missing or mismatched upstream model identity";
  if (!error && !sawChoices) error = "no assistant choices";
  if (!error && !firstDataOnly && (!done || finishReason == null)) error = "incomplete completion";
  if (!error && !firstDataOnly && finishReason === "length") error = "output budget exhausted; tool support inconclusive";
  if (!error && /\[PROXY ERROR/.test(content)) error = content;
  return { ok: !error && !firstDataOnly, transportReady: !error,
    firstReportedModel: [...models][0] || null, reportedModels: [...models], modelMatches,
    finishReason, content, reasoningChars: reasoningContent.length, reasoningContent, toolCalls, toolArgumentsValid,
    upstreamErrorCode: upstreamError?.code || null, error: error || null };
}

function validateProbeDecoder() {
  const frame = value => "data: " + JSON.stringify(value) + "\n\n";
  const common = { model: "test/decoder" };
  const first = frame({ ...common, choices: [{ index: 0, delta: { tool_calls: [
    { index: 0, id: "call_1", type: "function", function: { name: "report_status", arguments: '{"sta' } }
  ] }, finish_reason: null }] });
  const last = frame({ ...common, choices: [{ index: 0, delta: { tool_calls: [
    { index: 0, function: { arguments: 'tus":"ready"}' } }
  ] }, finish_reason: "tool_calls" }] }) + "data: [DONE]\n\n";
  assert.ok(parseCompletion(first + last, true, common.model).toolArgumentsValid);
  const empty = frame({ ...common, choices: [{ index: 0, delta: { tool_calls: [] }, finish_reason: "stop" }] }) + "data: [DONE]\n\n";
  assert.ok(!parseCompletion(empty, true, common.model).toolArgumentsValid);
  assert.ok(!parseCompletion(first, true, common.model).ok);
  assert.ok(!parseCompletion(first + last, true, "test/other").ok);
  const truncated = frame({ ...common, choices: [{ index: 0, delta: { reasoning_content: "still thinking" }, finish_reason: "length" }] }) + "data: [DONE]\n\n";
  assert.match(parseCompletion(truncated, true, common.model).error, /budget exhausted/);
  assert.strictEqual(parseCompletion(truncated, true, common.model).reasoningContent, "still thinking",
    "tool continuation must retain provider reasoning history internally");
  assert.ok(!parseCompletion(frame({ error: { message: "Gone", code: 410 } }) + "data: [DONE]\n\n", true, common.model).ok);
}

function probeRequest(baseUrl, payload, timeoutMs, firstDataOnly = false, stopOnThrottle = false) {
  const url = new URL("/v1/chat/completions", baseUrl);
  // The authenticated live route is the local proxy; never forward key files
  // or authorization headers through this test harness.
  assert.ok(url.protocol === "http:" && ["127.0.0.1", "localhost"].includes(url.hostname),
    "live probe must target the local proxy");
  const body = Buffer.from(JSON.stringify(payload));
  return new Promise(resolve => {
    const started = Date.now();
    const decoder = new (require("string_decoder").StringDecoder)("utf8");
    let firstProgressMs = null;
    let firstModelDataMs = null;
    let text = "";
    let settled = false;
    let timer = null;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ model: payload.model, firstProgressMs, firstModelDataMs,
        elapsedMs: Date.now() - started, ...result });
    };
    const req = http.request({ hostname: url.hostname, port: url.port, path: url.pathname,
      method: "POST", headers: { "content-type": "application/json", "content-length": body.length,
        ...(stopOnThrottle ? { 'x-nvidia-probe-stop-on-throttle': '1' } : {}) } }, res => {
      res.on("data", chunk => {
        if (firstProgressMs === null) firstProgressMs = Date.now() - started;
        text += decoder.write(chunk);
        if (firstModelDataMs === null && (payload.stream ? /(?:^|\n)data:\s*\{/.test(text) : text.length > 0)) {
          firstModelDataMs = Date.now() - started;
        }
        if (firstDataOnly && /\r?\n\r?\n/.test(text) && firstModelDataMs !== null) {
          const parsed = parseCompletion(text, payload.stream, payload.model, true);
          if (parsed.firstReportedModel || parsed.upstreamErrorCode) {
            finish({ ...parsed, firstDataOnly: true, statusCode: res.statusCode });
            req.destroy();
          }
        }
      });
      res.once("end", () => {
        text += decoder.end();
        const parsed = parseCompletion(text, payload.stream, payload.model);
        finish({ ...parsed, statusCode: res.statusCode,
          classification: Number(parsed.upstreamErrorCode) === 429 ? 'throttled' : null,
          ok: parsed.ok && res.statusCode === 200,
          error: parsed.error || (res.statusCode === 200 ? null : "HTTP " + res.statusCode) });
      });
      res.once("error", error => finish({ ok: false, error: error.message }));
    });
    req.once("error", error => finish({ ok: false, error: error.message }));
    timer = setTimeout(() => {
      finish({ ok: false, error: "client timeout after " + timeoutMs + "ms",
        classification: "inconclusive-timeout" });
      req.destroy();
    }, timeoutMs);
    req.end(body);
  });
}

async function livePost(baseUrl, model, timeoutMs) {
  const toolMode = process.env.LIVE_NVIDIA_TOOL_MODE === "1";
  const maxTokens = Number.parseInt(process.env.LIVE_NVIDIA_MAX_TOKENS || "4096", 10);
  assert.ok(Number.isInteger(maxTokens) && maxTokens > 0);
  const payload = {
    model, messages: [{ role: "user", content: toolMode
      ? "Call report_status with status=ready. After its tool result arrives, reply with only the receipt from the result. Do not invent the receipt."
      : "Reply with exactly OK." }],
    stream: process.env.LIVE_NVIDIA_STREAM !== "0", max_tokens: maxTokens,
  };
  if (process.env.LIVE_NVIDIA_PAYLOAD_OPTIONS) {
    const options = JSON.parse(process.env.LIVE_NVIDIA_PAYLOAD_OPTIONS);
    for (const key of Object.keys(options)) {
      assert.ok(["temperature", "top_p", "reasoning_effort", "chat_template_kwargs"].includes(key), "unsupported payload override " + key);
    }
    Object.assign(payload, options);
  }
  if (toolMode) {
    payload.tools = [{ type: "function", function: { name: "report_status",
      description: "Return readiness and a new receipt. The receipt is known only after this function returns.",
      parameters: { type: "object", properties: { status: { type: "string", enum: ["ready"] } },
        required: ["status"], additionalProperties: false } } }];
    const choice = process.env.LIVE_NVIDIA_TOOL_CHOICE || "auto";
    payload.tool_choice = ["auto", "required"].includes(choice)
      ? choice : { type: "function", function: { name: "report_status" } };
  }
  const first = await probeRequest(baseUrl, payload, timeoutMs,
    !toolMode && process.env.LIVE_NVIDIA_FIRST_DATA_ONLY === "1", true);
  // Keep reasoning history in-memory for the next request, never in reports.
  const { reasoningContent, ...firstReport } = first;
  const result = { ...firstReport, toolMode, maxTokens, toolChoice: payload.tool_choice || null,
    stream: payload.stream, payloadOptions: payload.chat_template_kwargs || null,
    reasoningEffort: payload.reasoning_effort || null };
  if (!toolMode) {
    result.ok = first.ok && first.content?.trim() === "OK";
    if (first.ok && !result.ok) result.error = "completed but did not return the requested marker";
    return result;
  }
  result.nativeToolCallValid = !!first.ok && first.toolArgumentsValid;
  if (!result.nativeToolCallValid) {
    result.ok = false;
    result.error ||= "no complete valid native tool call";
    return result;
  }
  const receipt = "NVI_" + require("crypto").randomBytes(10).toString("hex");
  const call = first.toolCalls[0];
  const continuation = { ...payload, tool_choice: "auto", messages: [
    ...payload.messages,
    { role: "assistant", content: first.content || null, tool_calls: first.toolCalls,
      reasoning_content: reasoningContent || "" },
    { role: "tool", tool_call_id: call.id, content: JSON.stringify({ status: "ready", receipt }) },
  ] };
  const remainingMs = Math.max(1, timeoutMs - first.elapsedMs);
  const followup = await probeRequest(baseUrl, continuation, remainingMs, false, true);
  const { reasoningContent: followupReasoning, ...followupReport } = followup;
  result.followup = followupReport;
  if (Number(followup.upstreamErrorCode) === 429) {
    result.upstreamErrorCode = 429;
    result.classification = 'throttled';
  }
  result.reasoningHistoryPreserved = true;
  result.toolRoundTrip = !!followup.ok && followup.content?.trim() === receipt &&
    followup.toolCalls.length === 0;
  result.ok = result.nativeToolCallValid && result.toolRoundTrip;
  result.elapsedMs = first.elapsedMs + followup.elapsedMs;
  result.error = result.ok ? null : followup.error || "tool result receipt was not returned exactly";
  return result;
}

async function liveMain() {
  const baseUrl = process.env.LIVE_NVIDIA_PROXY_URL;
  const timeoutMs = Number.parseInt(process.env.LIVE_NVIDIA_TIMEOUT_MS || "180000", 10);
  // Resolve the canonical dispatcher only for an unfiltered live run; no
  // second hand-maintained pool that silently omits newly restored models.
  const defaultModels = () => JSON.parse(require('child_process').execFileSync(
    'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    ['-NoProfile', '-Command', "@(& 'C:\\Users\\micha\\Documents\\WindowsPowerShell\\Invoke-NvidiaRankedModel.ps1' -List | Select-Object -ExpandProperty ModelId -Unique) | ConvertTo-Json -Compress"],
    { windowsHide: true, encoding: 'utf8', timeout: 10000 }));
  const models = process.env.LIVE_NVIDIA_MODELS
    ? process.env.LIVE_NVIDIA_MODELS.split(",").map(model => model.trim()).filter(Boolean)
    : defaultModels();
  // Bounded sequential calls honor shared free-endpoint capacity. Emit each
  // result as it completes, so an interrupted run retains useful evidence.
  const results = [];
  for (const model of models) {
    const result = await livePost(baseUrl, model, timeoutMs);
    result.verifiedAtUtc = new Date().toISOString();
    results.push(result);
    console.log(JSON.stringify(result));
    if (process.env.LIVE_NVIDIA_REPORT_PATH) {
      fs.appendFileSync(process.env.LIVE_NVIDIA_REPORT_PATH, JSON.stringify(result) + "\n", "utf8");
    }
    if (result.upstreamErrorCode === 429) break;
  }
  const port = new URL(baseUrl).port;
  const health = await waitFor(async () => {
    const value = await requestJson(port, "/health");
    return value.running === 0 && value.queued === 0 ? value : null;
  }, 5000, "live slot cleanup");
  const fastProgress = results.every(result => result.firstProgressMs !== null && result.firstProgressMs < 2500);
  const allOk = results.every(result => result.ok);
  if (process.env.LIVE_NVIDIA_STREAM !== "0") {
    assert.ok(fastProgress, "one or more sessions did not receive immediate local progress");
  }
  assert.strictEqual(health.leaked, 0, "live proxy leaked a scheduler slot");
  assert.ok(allOk, "one or more live models failed");
  console.log(`NVIDIA_PROXY_LIVE_OK models=${results.length} progress_events=${health.progressEvents} retries=${health.retries}`);
}

async function main() {
  validateProbeDecoder();
  assert.ok(fs.existsSync(proxyPath), `proxy not found: ${proxyPath}`);

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "nvidia-proxy-test-"));
  const keyFile = path.join(tempDir, "keys.txt");
  fs.writeFileSync(keyFile, "nvapi-test-one\nnvapi-test-two\n", "utf8");

  const seenBodies = [];
  const openResponses = new Set();
  const upstream = http.createServer((req, res) => {
    const chunks = [];
    req.on("data", chunk => chunks.push(chunk));
    req.on("end", () => {
      const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      seenBodies.push(body);

      if (body.model === 'test/throttled-probe') {
        res.writeHead(429, { 'content-type': 'application/json', 'retry-after': '0.2' });
        res.end(JSON.stringify({ error: { message: 'fixture quota', code: 429 } }));
        return;
      }

      if (body.model === "test/stall") {
        res.writeHead(200, { "content-type": "text/event-stream" });
        openResponses.add(res);
        res.on("error", () => {});
        res.once("close", () => openResponses.delete(res));
        return;
      }

      if (body.model === "test/retry-same-model") {
        const attempts = seenBodies.filter(item => item.model === body.model).length;
        if (attempts <= 2) {
          res.writeHead(503, { "content-type": "text/plain" });
          res.end("retry this exact model");
          return;
        }
      }

      const common = { id: "chatcmpl-fixture", object: "chat.completion.chunk",
        created: 1, model: body.model };
      if (body.model === "test/wrong-model" || body.model === "test/missing-model") {
        if (body.model === "test/wrong-model") common.model = "test/unrequested";
        else delete common.model;
        res.writeHead(200, { "content-type": "text/event-stream" });
        res.end(`data: ${JSON.stringify({ ...common, choices: [{ index: 0,
          delta: { content: "wrong-model-output" }, finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`);
        return;
      }
      if (body.model === "test/prose-json") {
        res.writeHead(200, { "content-type": "text/event-stream" });
        res.end(`data: ${JSON.stringify({ ...common, choices: [{ index: 0,
          delta: { content: '{"name":"report_status","arguments":{"status":"ready"}}' },
          finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`);
        return;
      }
      if (body.model === "test/nonstream-tools" || body.model === "test/nonstream-wrong") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ ...common, object: "chat.completion",
          model: body.model === "test/nonstream-wrong" ? "test/unrequested" : body.model,
          choices: [{ index: 0, message: { role: "assistant", content: null,
            reasoning_content: "fixture reasoning",
            tool_calls: [{ id: "call_fixture", type: "function",
              function: { name: "report_status", arguments: '{"status":"ready"}' } }] },
            finish_reason: "tool_calls" }], usage: { prompt_tokens: 9, completion_tokens: 8, total_tokens: 17 } }));
        return;
      }

      if (body.model === "openai/gpt-oss-120b") {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({
          id: "chatcmpl-test-oss",
          object: "chat.completion",
          model: body.model,
          choices: [{
            index: 0,
            message: { role: "assistant", content: "oss-ok" },
            finish_reason: "stop",
          }],
        }));
        return;
      }

      res.writeHead(200, { "content-type": "text/event-stream" });
      res.end(
        `data: ${JSON.stringify({
          id: "chatcmpl-test-fast",
          object: "chat.completion.chunk",
          model: body.model,
          choices: [{ index: 0, delta: { content: "fast-ok" }, finish_reason: null }],
        })}\n\n` +
        `data: ${JSON.stringify({ id: "chatcmpl-test-fast", object: "chat.completion.chunk",
          model: body.model, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n` +
        "data: [DONE]\n\n"
      );
    });
  });

  let child = null;
  try {
    const upstreamPort = await listen(upstream);
    const reservation = http.createServer();
    const proxyPort = await listen(reservation);
    await closeServer(reservation);

    child = spawn(process.execPath, [
      proxyPath,
      "--port", String(proxyPort),
      "--keys", keyFile,
    ], {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        PROXY_LOG_FILE: path.join(tempDir, 'proxy.log'),
        PROXY_UPSTREAM_PROTOCOL: "http",
        PROXY_UPSTREAM_HOST: "127.0.0.1",
        PROXY_UPSTREAM_PORT: String(upstreamPort),
        PROXY_MAX_CONCURRENT: "1",
        PROXY_MAX_PER_KEY: "1",
        PROXY_FIRST_DATA_MS: "1000",
        PROXY_IDLE_MS: "1000",
        PROXY_OVERALL_MS: "4000",
        PROXY_QUEUE_PROGRESS_MS: "50",
        PROXY_FORCE_NON_STREAM_MODELS: "openai/gpt-oss-120b,test/nonstream-tools,test/nonstream-wrong",
      },
    });

    let childStderr = "";
    child.stderr.on("data", chunk => { childStderr += chunk.toString("utf8"); });

    const health = await waitFor(
      () => requestJson(proxyPort, "/health"),
      3000,
      "proxy startup"
    );
    assert.ok(health.v >= 12, `expected proxy v12+, got v${health.v}`);

    const first = post(proxyPort, {
      model: "test/stall",
      messages: [{ role: "user", content: "hold" }],
      stream: true,
      max_tokens: 1,
    });
    const firstAborted = first.result.catch(error => ({ aborted: true, error }));

    await waitFor(
      () => seenBodies.some(body => body.model === "test/stall"),
      1000,
      "stalled upstream request"
    );

    const second = post(proxyPort, {
      model: "test/fast",
      messages: [{ role: "user", content: "next" }],
      stream: true,
      max_tokens: 1,
    });

    await waitFor(async () => {
      const h = await requestJson(proxyPort, "/health");
      return h.running === 1 && h.queued === 1 ? h : null;
    }, 1000, "queued request");

    const queuedProgress = await waitFor(async () => {
      const h = await requestJson(proxyPort, "/health");
      return h.progressEvents > 0 ? h : null;
    }, 500, "real-time queue progress");
    assert.ok(queuedProgress.progressEvents > 0);

    await requestJson(proxyPort, "/_reload");

    first.req.destroy();
    await firstAborted;

    const secondResult = await second.result;
    assert.strictEqual(secondResult.statusCode, 200);
    assert.ok(secondResult.body.includes("fast-ok"), secondResult.body);
    assert.ok(secondResult.firstDataMs !== null && secondResult.firstDataMs < 250,
      `queued stream did not begin immediately: ${secondResult.firstDataMs}ms`);

    await waitFor(async () => {
      const h = await requestJson(proxyPort, "/health");
      return h.running === 0 && h.queued === 0 ? h : null;
    }, 1000, "slot release after client disconnect");

    const oss = post(proxyPort, {
      model: "openai/gpt-oss-120b",
      messages: [{ role: "user", content: "reply with ok" }],
      stream: true,
      max_tokens: 8,
    });
    const ossResult = await oss.result;
    const upstreamOss = seenBodies.find(body => body.model === "openai/gpt-oss-120b");
    assert.ok(upstreamOss, "GPT-OSS request did not reach the upstream");
    assert.notStrictEqual(upstreamOss.stream, true, "GPT-OSS upstream request still streams");
    assert.strictEqual(ossResult.statusCode, 200);
    assert.match(String(ossResult.headers["content-type"]), /text\/event-stream/i);
    assert.ok(ossResult.body.includes("oss-ok"), ossResult.body);
    assert.ok(ossResult.body.includes("data: [DONE]"), ossResult.body);

    for (const model of ["test/wrong-model", "test/missing-model", "test/nonstream-wrong"]) {
      const result = await post(proxyPort, { model, stream: true,
        messages: [{ role: "user", content: "identity fixture" }] }).result;
      assert.match(result.body, /"error"\s*:/, `${model} must fail closed`);
      assert.ok(!result.body.includes('"finish_reason":"stop"'), "identity failure was disguised as normal completion");
    }
    const prose = await post(proxyPort, { model: "test/prose-json", stream: true,
      messages: [{ role: "user", content: "Show an example of calling a tool." }] }).result;
    assert.ok(!prose.body.includes('"tool_calls"'), "proxy manufactured a tool invocation from answer text");
    const toolSchema = [{ type: "function", function: { name: "report_status",
      parameters: { type: "object", properties: {} } } }];
    await post(proxyPort, { model: "test/fast", stream: true, tools: toolSchema,
      messages: [{ role: "user", content: "Find the text 'do not use tools' with the search tool." }] }).result;
    assert.deepStrictEqual(seenBodies.at(-1).tools, toolSchema, "proxy removed tools based on quoted user text");
    await post(proxyPort, { model: 'test/history-audit', stream: true, reasoning_effort: 'max',
      messages: [{ role: 'assistant', content: null, reasoning_content: 'PRIVATE_FIXTURE_HISTORY',
        tool_calls: [{ id: 'fixture_history', type: 'function', function: { name: 'report_status', arguments: '{}' } }] },
        { role: 'tool', tool_call_id: 'fixture_history', content: 'PRIVATE_FIXTURE_RESULT' }],
      tools: toolSchema }).result;
    assert.match(childStderr, /model=test\/history-audit.*reasoningEffort=max.*assistantToolTurns=1.*reasoningToolTurns=1/,
      'safe diagnostics must expose whether reasoning history reached the provider boundary');
    assert.ok(!childStderr.includes('PRIVATE_FIXTURE'), 'diagnostics leaked content');
    const throttleProbe = await probeRequest(`http://127.0.0.1:${proxyPort}`, {
      model: 'test/throttled-probe', stream: true, messages: [{ role: 'user', content: 'quota fixture' }],
    }, 1000, false, true);
    assert.strictEqual(throttleProbe.upstreamErrorCode, 429, 'diagnostic probe must stop on quota instead of retrying keys');
    assert.strictEqual(throttleProbe.classification, 'throttled');
    const converted = await post(proxyPort, { model: "test/nonstream-tools", stream: true,
      messages: [{ role: "user", content: "invoke tool" }], tools: toolSchema }).result;
    assert.match(converted.body, /"model":"test\/nonstream-tools"/);
    assert.match(converted.body, /"reasoning_content":"fixture reasoning"/);
    assert.match(converted.body, /"id":"call_fixture"/);
    assert.match(converted.body, /"finish_reason":"tool_calls"/);
    assert.match(converted.body, /"total_tokens":17/);
    assert.ok(!converted.body.includes('"error"'), converted.body);

    const retryStart = seenBodies.length;
    const retrySameModel = post(proxyPort, {
      model: "test/retry-same-model",
      messages: [{ role: "user", content: "retry without substitution" }],
      stream: true,
      max_tokens: 1,
    });
    const retrySameModelResult = await retrySameModel.result;
    const retryBodies = seenBodies.slice(retryStart);
    assert.ok(retryBodies.length >= 3, `expected key retries for exact model, got ${retryBodies.length}`);
    assert.ok(retryBodies.every(body => body.model === "test/retry-same-model"),
      "proxy changed the model while retrying a failed request");
    assert.strictEqual(retrySameModelResult.statusCode, 200);
    assert.ok(retrySameModelResult.body.includes("fast-ok"), retrySameModelResult.body);

    const burst = Array.from({ length: 250 }, (_, index) => post(proxyPort, {
      model: "test/fast",
      messages: [{ role: "user", content: `burst-${index}` }],
      stream: true,
      max_tokens: 1,
    }).result);
    const burstResults = await Promise.all(burst);
    assert.ok(burstResults.every(result =>
      result.statusCode === 200 && result.body.includes("fast-ok") &&
      !result.body.includes('"error"') &&
      result.firstDataMs !== null && result.firstDataMs < 2500
    ), "250-session burst did not complete with prompt progress");

    const finalHealth = await requestJson(proxyPort, "/health");
    assert.strictEqual(finalHealth.running, 0);
    assert.strictEqual(finalHealth.queued, 0);
    assert.strictEqual(finalHealth.leaked, 0);
    assert.ok(finalHealth.keyState.every(key => key.active === 0),
      `key activity leaked across reload: ${JSON.stringify(finalHealth.keyState)}`);
    console.log(
      `NVIDIA_PROXY_TEST_OK version=${finalHealth.v} ` +
      `progress_events=${finalHealth.progressEvents} aborted=${finalHealth.aborted}`
    );
  } finally {
    for (const res of openResponses) res.destroy();
    if (child && !child.killed) child.kill();
    await closeServer(upstream).catch(() => {});
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

const selectedMain = process.env.LIVE_NVIDIA_PROXY_URL ? liveMain : main;
selectedMain().catch(error => {
  console.error(`NVIDIA_PROXY_TEST_FAIL ${error.stack || error.message}`);
  process.exitCode = 1;
});
