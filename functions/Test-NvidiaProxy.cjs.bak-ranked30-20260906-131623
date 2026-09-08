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

function livePost(baseUrl, model, timeoutMs) {
  const url = new URL("/v1/chat/completions", baseUrl);
  const body = Buffer.from(JSON.stringify({
    model,
    messages: [{ role: "user", content: "Reply with exactly OK." }],
    stream: true,
    max_tokens: 4,
    temperature: 0,
  }));
  return new Promise(resolve => {
    const started = Date.now();
    let firstProgressMs = null;
    let firstModelDataMs = null;
    let text = "";
    let settled = false;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ model, firstProgressMs, firstModelDataMs, elapsedMs: Date.now() - started, ...result });
    };
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: "POST",
      headers: { "content-type": "application/json", "content-length": body.length },
    }, res => {
      res.on("data", chunk => {
        if (firstProgressMs === null) firstProgressMs = Date.now() - started;
        text += chunk.toString("utf8");
        if (firstModelDataMs === null && /(^|\n)data:\s*\{/.test(text)) firstModelDataMs = Date.now() - started;
      });
      res.once("end", () => finish({
        statusCode: res.statusCode,
        ok: res.statusCode === 200 && text.includes("data: [DONE]") && !text.includes("[PROXY ERROR"),
        error: text.includes("[PROXY ERROR") ? text.match(/\[PROXY ERROR[^\]]*\]/)?.[0] : null,
      }));
      res.once("error", error => finish({ ok: false, error: error.message }));
    });
    req.once("error", error => finish({ ok: false, error: error.message }));
    const timer = setTimeout(() => {
      req.destroy();
      finish({ ok: false, error: `client timeout after ${timeoutMs}ms` });
    }, timeoutMs);
    req.end(body);
  });
}

async function liveMain() {
  const baseUrl = process.env.LIVE_NVIDIA_PROXY_URL;
  const timeoutMs = Number.parseInt(process.env.LIVE_NVIDIA_TIMEOUT_MS || "180000", 10);
  const defaultModels = [
    "thinkingmachines/inkling",
    "deepseek-ai/deepseek-v4-flash-0731",
    "z-ai/glm-5.2",
    "nvidia/nemotron-3.5-lightning-30b-a3b",
    "nvidia/nemotron-3-nano-30b-a3b",
    "meta/llama-3.1-70b-instruct",
    "nvidia/nemotron-3-ultra-550b-a55b",
    "nvidia/nemotron-3-super-120b-a12b",
    "openai/gpt-oss-120b",
  ];
  const models = process.env.LIVE_NVIDIA_MODELS
    ? process.env.LIVE_NVIDIA_MODELS.split(",").map(model => model.trim()).filter(Boolean)
    : defaultModels;
  const results = await Promise.all(models.map(model => livePost(baseUrl, model, timeoutMs)));
  for (const result of results) console.log(JSON.stringify(result));
  const port = new URL(baseUrl).port;
  const health = await waitFor(async () => {
    const value = await requestJson(port, "/health");
    return value.running === 0 && value.queued === 0 ? value : null;
  }, 5000, "live slot cleanup");
  const fastProgress = results.every(result => result.firstProgressMs !== null && result.firstProgressMs < 2500);
  const allOk = results.every(result => result.ok);
  assert.ok(fastProgress, "one or more sessions did not receive immediate local progress");
  assert.strictEqual(health.leaked, 0, "live proxy leaked a scheduler slot");
  assert.ok(allOk, "one or more live models failed");
  console.log(`NVIDIA_PROXY_LIVE_OK models=${results.length} progress_events=${health.progressEvents} retries=${health.retries}`);
}

async function main() {
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

      if (body.model === "test/stall") {
        res.writeHead(200, { "content-type": "text/event-stream" });
        openResponses.add(res);
        res.on("error", () => {});
        res.once("close", () => openResponses.delete(res));
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
        PROXY_UPSTREAM_PROTOCOL: "http",
        PROXY_UPSTREAM_HOST: "127.0.0.1",
        PROXY_UPSTREAM_PORT: String(upstreamPort),
        PROXY_MAX_CONCURRENT: "1",
        PROXY_MAX_PER_KEY: "1",
        PROXY_FIRST_DATA_MS: "1000",
        PROXY_IDLE_MS: "1000",
        PROXY_OVERALL_MS: "4000",
        PROXY_QUEUE_PROGRESS_MS: "50",
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

    const burst = Array.from({ length: 250 }, (_, index) => post(proxyPort, {
      model: "test/fast",
      messages: [{ role: "user", content: `burst-${index}` }],
      stream: true,
      max_tokens: 1,
    }).result);
    const burstResults = await Promise.all(burst);
    assert.ok(burstResults.every(result =>
      result.statusCode === 200 && result.body.includes("fast-ok") &&
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
