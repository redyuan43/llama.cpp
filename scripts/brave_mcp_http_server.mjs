#!/usr/bin/env node

import http from "node:http";
import { randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { URL } from "node:url";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function resolveSdkBaseDir() {
  const candidates = [
    process.env.MCP_SDK_BASE_DIR,
    process.env.LLAMA_CPP_WEBUI_NODE_MODULES
      ? path.join(process.env.LLAMA_CPP_WEBUI_NODE_MODULES, "@modelcontextprotocol", "sdk", "dist", "esm")
      : "",
    process.env.LLAMA_CPP_WEBUI_DIR
      ? path.join(process.env.LLAMA_CPP_WEBUI_DIR, "node_modules", "@modelcontextprotocol", "sdk", "dist", "esm")
      : "",
    path.resolve(__dirname, "../../llama.cpp/tools/server/webui/node_modules/@modelcontextprotocol/sdk/dist/esm"),
    path.resolve(__dirname, "../../../llama.cpp/tools/server/webui/node_modules/@modelcontextprotocol/sdk/dist/esm"),
    "/home/dgx/github/llama.cpp/tools/server/webui/node_modules/@modelcontextprotocol/sdk/dist/esm",
    "/home/agx/llama.cpp/tools/server/webui/node_modules/@modelcontextprotocol/sdk/dist/esm",
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, "server", "index.js"))) {
      return candidate;
    }
  }

  throw new Error(
    `Cannot locate @modelcontextprotocol/sdk. Checked: ${candidates.join(", ")}`
  );
}

const sdkBaseDir = resolveSdkBaseDir();
const { Server } = await import(pathToFileURL(path.join(sdkBaseDir, "server", "index.js")).href);
const { StreamableHTTPServerTransport } = await import(
  pathToFileURL(path.join(sdkBaseDir, "server", "streamableHttp.js")).href
);
const { ListToolsRequestSchema, CallToolRequestSchema } = await import(
  pathToFileURL(path.join(sdkBaseDir, "types.js")).href
);

const execFileAsync = promisify(execFile);

const HOST = process.env.BRAVE_MCP_HOST || "127.0.0.1";
const PORT = Number.parseInt(process.env.BRAVE_MCP_PORT || "8765", 10);
const MCP_PATH = process.env.BRAVE_MCP_PATH || "/mcp";
const HEALTH_PATH = process.env.BRAVE_MCP_HEALTH_PATH || "/healthz";
const API_ROOT = "https://api.search.brave.com/res/v1";
const API_KEY = process.env.BRAVE_API_KEY;

if (!API_KEY) {
  console.error("Error: BRAVE_API_KEY environment variable is required");
  process.exit(1);
}

const transports = {};

const TOOL_DEFS = [
  {
    name: "brave_web_search",
    description: "Brave 网页搜索，适合通用联网搜索与网页资料检索。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "搜索词" },
        count: { type: "number", description: "结果数，1-20，默认 10" },
        offset: { type: "number", description: "偏移，默认 0" },
        country: { type: "string", description: "国家代码，如 US" },
        search_lang: { type: "string", description: "搜索语言，如 zh-hans" },
        ui_lang: { type: "string", description: "界面语言，如 zh-CN" },
        safesearch: { type: "string", description: "off、moderate、strict" },
        freshness: { type: "string", description: "pd、pw、pm、py" },
        extra_snippets: { type: "boolean", description: "是否附加更多摘要" },
      },
      required: ["query"],
    },
    endpoint: "/web/search",
    defaults: { count: 10, offset: 0 },
    paramMap: { query: "q" },
  },
  {
    name: "brave_news_search",
    description: "Brave 新闻搜索，适合最新资讯和时效性话题。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "新闻搜索词" },
        count: { type: "number", description: "结果数，1-50，默认 10" },
        offset: { type: "number", description: "偏移，默认 0" },
        country: { type: "string", description: "国家代码" },
        search_lang: { type: "string", description: "搜索语言" },
        ui_lang: { type: "string", description: "界面语言" },
        safesearch: { type: "string", description: "off、moderate、strict" },
        freshness: { type: "string", description: "pd、pw、pm、py" },
        extra_snippets: { type: "boolean", description: "是否附加更多摘要" },
      },
      required: ["query"],
    },
    endpoint: "/news/search",
    defaults: { count: 10, offset: 0 },
    paramMap: { query: "q" },
  },
  {
    name: "brave_image_search",
    description: "Brave 图片搜索，适合找图片和视觉参考。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "图片搜索词" },
        count: { type: "number", description: "结果数，1-200，默认 20" },
        country: { type: "string", description: "国家代码" },
        search_lang: { type: "string", description: "搜索语言" },
        safesearch: { type: "string", description: "off 或 strict，默认 strict" },
        spellcheck: { type: "boolean", description: "是否启用拼写纠正" },
      },
      required: ["query"],
    },
    endpoint: "/images/search",
    defaults: { count: 20, safesearch: "strict", spellcheck: true },
    paramMap: { query: "q" },
  },
  {
    name: "brave_video_search",
    description: "Brave 视频搜索，适合找教程、讲座和视频资料。",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "视频搜索词" },
        count: { type: "number", description: "结果数，1-50，默认 10" },
        offset: { type: "number", description: "偏移，默认 0" },
        country: { type: "string", description: "国家代码" },
        search_lang: { type: "string", description: "搜索语言" },
        ui_lang: { type: "string", description: "界面语言" },
        safesearch: { type: "string", description: "off、moderate、strict" },
        freshness: { type: "string", description: "pd、pw、pm、py" },
        spellcheck: { type: "boolean", description: "是否启用拼写纠正" },
      },
      required: ["query"],
    },
    endpoint: "/videos/search",
    defaults: { count: 10, offset: 0, spellcheck: true },
    paramMap: { query: "q" },
  },
];

const TOOL_INDEX = new Map(TOOL_DEFS.map((tool) => [tool.name, tool]));

function normalizeProxyUrl(raw = "") {
  const trimmed = String(raw).trim().replace(/\/$/, "");
  if (!trimmed) {
    return "";
  }
  if (trimmed.startsWith("socks://")) {
    return `socks5h://${trimmed.slice("socks://".length)}`;
  }
  return trimmed;
}

function getProxyUrl() {
  return normalizeProxyUrl(
    process.env.ALL_PROXY ||
      process.env.all_proxy ||
      process.env.HTTPS_PROXY ||
      process.env.https_proxy ||
      process.env.HTTP_PROXY ||
      process.env.http_proxy ||
      ""
  );
}

function isInitializeRequest(body) {
  return Boolean(body && typeof body === "object" && body.method === "initialize");
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      const text = Buffer.concat(chunks).toString("utf8");
      if (!text) {
        resolve(undefined);
        return;
      }
      try {
        resolve(JSON.parse(text));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function writeJson(res, status, payload) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

function logInfo(message, extra = undefined) {
  if (extra === undefined) {
    console.error(`[brave-mcp] ${message}`);
    return;
  }
  console.error(`[brave-mcp] ${message}`, extra);
}

function normalizeQuery(query, fallback = undefined) {
  if (typeof query === "string") {
    return query;
  }

  if (query && typeof query === "object") {
    if (typeof query.original === "string" && query.original) {
      return query.original;
    }
    return query;
  }

  if (typeof fallback === "string" && fallback) {
    return fallback;
  }

  return query ?? fallback ?? null;
}

function mapItems(items, limit, mapper) {
  if (!Array.isArray(items)) {
    return [];
  }

  return items.slice(0, limit).map(mapper);
}

function summarizeWebResults(payload) {
  return mapItems(payload.web?.results, 5, (item) => ({
    title: item.title,
    url: item.url,
    description: item.description,
    age: item.age,
    language: item.language,
  }));
}

function summarizeNewsResults(payload) {
  const results = Array.isArray(payload.results) ? payload.results : payload.news?.results;
  return mapItems(results, 5, (item) => ({
    title: item.title,
    url: item.url,
    description: item.description,
    age: item.age,
    source: item.profile?.name || item.meta_url?.hostname,
  }));
}

function summarizeImageResults(payload) {
  const results = Array.isArray(payload.results) ? payload.results : payload.images?.results;
  return mapItems(results, 10, (item) => {
    const summary = {
      title: item.title,
      url: item.url,
      source: item.source || item.meta_url?.hostname,
      page_fetched: item.page_fetched,
    };

    if (item.properties?.url) {
      summary.image_url = item.properties.url;
    }

    return summary;
  });
}

function summarizeVideoResults(payload) {
  const results = Array.isArray(payload.results) ? payload.results : payload.videos?.results;
  return mapItems(results, 10, (item) => {
    const summary = {
      title: item.title,
      url: item.url,
      description: item.description,
      age: item.age,
      source: item.video?.publisher || item.meta_url?.hostname,
    };

    if (item.video?.creator || item.video?.author?.name) {
      summary.creator = item.video?.creator || item.video?.author?.name;
    }

    return summary;
  });
}

function summarizePayload(toolName, payload, args = {}) {
  const summary = {};
  const query = normalizeQuery(payload.query, args.query);

  if (query !== null && query !== undefined) {
    summary.query = query;
  }

  switch (toolName) {
    case "brave_web_search":
      summary.web_results = summarizeWebResults(payload);
      if (Array.isArray(payload.videos?.results)) {
        summary.video_results = summarizeVideoResults({ results: payload.videos.results });
      }
      break;
    case "brave_news_search":
      summary.news_results = summarizeNewsResults(payload);
      break;
    case "brave_image_search":
      summary.image_results = summarizeImageResults(payload);
      break;
    case "brave_video_search":
      summary.video_results = summarizeVideoResults(payload);
      break;
    default:
      break;
  }

  return summary;
}

function summarizeCounts(summary) {
  const counts = {};
  for (const [key, value] of Object.entries(summary)) {
    if (Array.isArray(value)) {
      counts[`${key}_count`] = value.length;
    }
  }
  return counts;
}

async function callBrave(endpoint, args = {}) {
  const url = new URL(`${API_ROOT}${endpoint}`);

  for (const [key, value] of Object.entries(args)) {
    if (value === undefined || value === null || value === "") {
      continue;
    }

    if (Array.isArray(value)) {
      for (const item of value) {
        url.searchParams.append(key, String(item));
      }
      continue;
    }

    url.searchParams.set(key, String(value));
  }

  const cmd = [
    "curl",
    "--ipv4",
    "--silent",
    "--show-error",
    "--location",
    "--compressed",
    "--retry",
    "2",
    "--retry-delay",
    "1",
    "--retry-all-errors",
    "--retry-connrefused",
    "--max-time",
    "25",
    "--connect-timeout",
    "8",
    "--header",
    "Accept: application/json",
    "--header",
    `X-Subscription-Token: ${API_KEY}`,
  ];

  const proxy = getProxyUrl();
  if (proxy) {
    cmd.push("--proxy", proxy);
  }

  cmd.push(url.toString());

  logInfo(`upstream request ${endpoint}`, Object.fromEntries(url.searchParams.entries()));

  const env = {
    ...process.env,
    ALL_PROXY: "",
    all_proxy: "",
    HTTPS_PROXY: "",
    https_proxy: "",
    HTTP_PROXY: "",
    http_proxy: "",
  };

  const { stdout, stderr } = await execFileAsync(cmd[0], cmd.slice(1), {
    env,
    maxBuffer: 10 * 1024 * 1024,
  });

  if (stderr && stderr.trim()) {
    console.warn(`[brave-mcp] curl stderr: ${stderr.trim()}`);
  }

  return JSON.parse(stdout);
}

function mapToolArgs(tool, args = {}) {
  const mapped = {};
  const paramMap = tool.paramMap || {};

  for (const [key, value] of Object.entries(args)) {
    const targetKey = paramMap[key] || key;
    mapped[targetKey] = value;
  }

  return mapped;
}

function createServer() {
  const server = new Server(
    { name: "llama.cpp-brave-mcp", version: "1.0.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOL_DEFS.map(({ name, description, inputSchema }) => ({
      name,
      description,
      inputSchema,
    })),
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const name = request.params.name;
    const args = request.params.arguments || {};
    const tool = TOOL_INDEX.get(name);

    if (!tool) {
      return {
        isError: true,
        content: [{ type: "text", text: `Unknown tool: ${name}` }],
      };
    }

    try {
      logInfo(`tool call ${name}`, args);
      const payload = await callBrave(tool.endpoint, {
        ...tool.defaults,
        ...mapToolArgs(tool, args),
      });
      const summary = summarizePayload(name, payload, args);
      logInfo(`tool success ${name}`, {
        sections: Object.keys(summary),
        ...summarizeCounts(summary),
      });
      const text =
        Object.keys(summary).length > 0
          ? JSON.stringify(summary, null, 2)
          : JSON.stringify(
              {
                query: payload.query || null,
                type: payload.type || null,
                available_sections: Object.keys(payload).filter((key) => key !== "query"),
              },
              null,
              2
            );

      return {
        content: [
          {
            type: "text",
            text,
          },
        ],
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logInfo(`tool error ${name}`, message);
      return {
        isError: true,
        content: [
          {
            type: "text",
            text: `Brave API request failed: ${message}`,
          },
        ],
      };
    }
  });

  return server;
}

const httpServer = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || `${HOST}:${PORT}`}`);

    if (url.pathname === HEALTH_PATH) {
      writeJson(res, 200, {
        ok: true,
        service: "brave-mcp-http-server",
        mcp_path: MCP_PATH,
      });
      return;
    }

    if (url.pathname !== MCP_PATH) {
      writeJson(res, 404, { error: "not found" });
      return;
    }

    logInfo(`http ${req.method} ${url.pathname}`);

    if (req.method === "POST") {
      const sessionId = req.headers["mcp-session-id"];
      const body = await readRequestBody(req);
      logInfo("http body", {
        sessionId: sessionId || null,
        method: body?.method || null,
        hasParams: Boolean(body?.params),
      });
      let transport;

      if (sessionId && transports[sessionId]) {
        transport = transports[sessionId];
      } else if (!sessionId && isInitializeRequest(body)) {
        transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => randomUUID(),
          onsessioninitialized: (sid) => {
            transports[sid] = transport;
          },
        });

        transport.onclose = () => {
          const sid = transport.sessionId;
          if (sid && transports[sid]) {
            delete transports[sid];
          }
        };

        const server = createServer();
        await server.connect(transport);
        await transport.handleRequest(req, res, body);
        return;
      } else {
        res.statusCode = 404;
        res.setHeader("Content-Type", "application/json; charset=utf-8");
        res.end(JSON.stringify({
          jsonrpc: "2.0",
          error: { code: -32000, message: "Session not found" },
          id: null,
        }));
        return;
      }

      await transport.handleRequest(req, res, body);
      return;
    }

    if (req.method === "GET" || req.method === "DELETE") {
      const sessionId = req.headers["mcp-session-id"];
      if (!sessionId || !transports[sessionId]) {
        writeJson(res, 404, { error: "Session not found" });
        return;
      }

      await transports[sessionId].handleRequest(req, res);
      return;
    }

    res.statusCode = 405;
    res.end("Method Not Allowed");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[brave-mcp] request error:", message);
    if (!res.headersSent) {
      writeJson(res, 500, { error: message });
    }
  }
});

httpServer.listen(PORT, HOST, () => {
  console.log(`[brave-mcp] listening on http://${HOST}:${PORT}${MCP_PATH}`);
  console.log(`[brave-mcp] health at http://${HOST}:${PORT}${HEALTH_PATH}`);
});

async function shutdown() {
  const sessionIds = Object.keys(transports);
  for (const sessionId of sessionIds) {
    try {
      await transports[sessionId].close();
    } catch (error) {
      console.error(`[brave-mcp] failed to close session ${sessionId}:`, error);
    }
    delete transports[sessionId];
  }

  httpServer.close(() => process.exit(0));
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
