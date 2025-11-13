#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  InitializeRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import axios from "axios";
import yargs from "yargs/yargs";
import { hideBin } from "yargs/helpers";
import https from "https";

// Basic top-level error logging so Claude can surface failures
process.on("uncaughtException", (err) => {
  console.error("Uncaught exception in remote-hosts-mcp-client:", err);
});

process.on("unhandledRejection", (reason) => {
  console.error("Unhandled rejection in remote-hosts-mcp-client:", reason);
});

// Parse command line arguments
const argv = yargs(hideBin(process.argv))
  .option("api-base", {
    alias: "a",
    type: "string",
    description: "Base URL of the Remote Hosts API",
    default: "https://localhost:8443",
  })
  .help()
  .alias("help", "h").argv;

const API_BASE = argv["api-base"];

// Create axios instance with SSL verification disabled for self-signed certs
const api = axios.create({
  baseURL: API_BASE,
  timeout: 30000,
  httpsAgent: new https.Agent({
    rejectUnauthorized: false,
  }),
});

// Helper function to make API calls
async function apiCall(method, endpoint, data = null) {
  try {
    const response = await api.request({
      method,
      url: endpoint,
      data,
    });
    return response.data;
  } catch (error) {
    if (error.response) {
      throw new Error(
        `API Error ${error.response.status}: ${JSON.stringify(
          error.response.data
        )}`
      );
    }
    throw new Error(`Request failed: ${error.message}`);
  }
}

// Active terminal state
let activeTerminal = {
  hostName: null,
  sessionName: null,
};

// Supported MCP spec version (we negotiate down from the client version)
const SUPPORTED_PROTOCOL_VERSION = "2024-11-05";

// Create MCP server
const server = new Server(
  {
    name: "remote-hosts-mcp-client",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
      logging: {},
    },
  }
);

// Explicit initialize handler so we can log and be robust under npx
server.setRequestHandler(InitializeRequestSchema, async (request) => {
  console.error(
    "remote-hosts-mcp-client: received initialize request:",
    JSON.stringify(request)
  );

  // In future we could support multiple protocol versions; for now we always
  // respond with the single version this client is built against.
  const protocolVersion = SUPPORTED_PROTOCOL_VERSION;

  const result = {
    protocolVersion,
    capabilities: {
      tools: {},
      logging: {},
    },
    serverInfo: {
      name: "remote-hosts-mcp-client",
      version: "1.0.0",
    },
  };

  console.error(
    "remote-hosts-mcp-client: sending initialize result:",
    JSON.stringify(result)
  );

  return result;
});

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "add_host",
        description:
          "Add a new remote SSH host to the system. Registers a remote server for terminal session management.",
        inputSchema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description:
                "Unique identifier for the host (e.g., 'production-server', 'web-01')",
            },
            address: {
              type: "string",
              description:
                "Hostname or IP address (e.g., '192.168.1.100' or 'server.example.com')",
            },
            port: {
              type: "number",
              description: "SSH port number (typically 22)",
              default: 22,
            },
            user: {
              type: "string",
              description: "SSH username to authenticate as",
            },
            auth_method: {
              type: "string",
              description: "Authentication type - must be 'password' or 'key'",
              enum: ["password", "key"],
            },
            secret: {
              type: "string",
              description:
                "SSH password (for password auth) or complete private key content",
            },
            validate: {
              type: "boolean",
              description: "Test SSH connection before saving (recommended)",
              default: true,
            },
          },
          required: ["name", "address", "port", "user", "auth_method", "secret"],
        },
      },
      {
        name: "hosts",
        description:
          "List all configured remote hosts with their connection status. Shows all registered SSH hosts in a formatted table.",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
      {
        name: "terminal_sessions",
        description:
          "List active terminal sessions on a specific host. Shows all running terminal sessions with their status and creation time.",
        inputSchema: {
          type: "object",
          properties: {
            host_name: {
              type: "string",
              description:
                "Name of the host to list sessions for (use 'hosts' tool to see available hosts)",
            },
          },
          required: ["host_name"],
        },
      },
      {
        name: "new_terminal",
        description:
          "Create a new terminal session on a remote host. Establishes an SSH connection and starts a new terminal session using tmux.",
        inputSchema: {
          type: "object",
          properties: {
            host_name: {
              type: "string",
              description:
                "Name of the host to create session on (use 'hosts' tool to see available hosts)",
            },
            session_name: {
              type: "string",
              description:
                "Optional custom identifier for the session. If omitted, a unique name will be auto-generated",
            },
          },
          required: ["host_name"],
        },
      },
      {
        name: "terminal_send",
        description:
          "Send input to a specific terminal session. Supports special key syntax like {{enter}}, {{ctrl+c}}, {{tab}}, etc.",
        inputSchema: {
          type: "object",
          properties: {
            host_name: {
              type: "string",
              description: "Name of the host",
            },
            session_name: {
              type: "string",
              description: "Name of the session",
            },
            input_string: {
              type: "string",
              description:
                "Text or commands to send. Use {{enter}} to execute, {{ctrl+c}} to interrupt, etc.",
            },
          },
          required: ["host_name", "session_name", "input_string"],
        },
      },
      {
        name: "terminal_read",
        description:
          "Read the current output from a terminal session. Captures and returns all visible output from the terminal screen.",
        inputSchema: {
          type: "object",
          properties: {
            host_name: {
              type: "string",
              description: "Name of the host",
            },
            session_name: {
              type: "string",
              description: "Name of the session",
            },
          },
          required: ["host_name", "session_name"],
        },
      },
      {
        name: "set_active_terminal",
        description:
          "Set the active terminal session for shorthand commands. Allows using 'send' and 'read' tools without specifying host/session.",
        inputSchema: {
          type: "object",
          properties: {
            host_name: {
              type: "string",
              description: "Name of the host",
            },
            session_name: {
              type: "string",
              description: "Name of the session",
            },
          },
          required: ["host_name", "session_name"],
        },
      },
      {
        name: "send",
        description:
          "Send input to the active terminal session (shorthand). Must call 'set_active_terminal' first.",
        inputSchema: {
          type: "object",
          properties: {
            input_string: {
              type: "string",
              description:
                "Text or commands to send. Use {{enter}} to execute, {{ctrl+c}} to interrupt, etc.",
            },
          },
          required: ["input_string"],
        },
      },
      {
        name: "read",
        description:
          "Read output from the active terminal session (shorthand). Must call 'set_active_terminal' first.",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result;

    switch (name) {
      case "add_host":
        const hostData = await apiCall("POST", "/hosts/add", {
          name: args.name,
          address: args.address,
          port: args.port,
          user: args.user,
          auth_method: args.auth_method,
          secret: args.secret,
          validate: args.validate !== false,
        });
        result = `✅ Host Added Successfully\n\nName: ${args.name}\nAddress: ${args.address}:${args.port}\nUser: ${args.user}\nAuth: ${args.auth_method}\nStatus: ${hostData.status}`;
        break;

      case "hosts":
        const hosts = await apiCall("POST", "/hosts/list", {});
        if (!hosts || hosts.length === 0) {
          result = "No hosts configured yet.";
        } else {
          const lines = [
            `# Configured Hosts (${hosts.length})`,
            "",
            "| Name | Address | User | Auth | Status |",
            "|------|---------|------|------|--------|",
          ];
          hosts.forEach((host) => {
            const status = host.last_connected ? "✅" : "❓";
            lines.push(
              `| ${host.name} | ${host.address}:${host.port} | ${host.user} | ${host.auth_method} | ${status} |`
            );
          });
          result = lines.join("\n");
        }
        break;

      case "terminal_sessions":
        const hostInfo = await apiCall(
          "GET",
          `/hosts/by-name/${args.host_name}`
        );
        const sessions = await apiCall(
          "POST",
          `/hosts/${hostInfo.host_id}/sessions/list`,
          {}
        );
        if (!sessions || sessions.length === 0) {
          result = `No terminal sessions on host '${args.host_name}'.`;
        } else {
          const lines = [
            `# Terminal Sessions (${sessions.length})`,
            "",
            "| Host | Session | Created | Status |",
            "|------|---------|---------|--------|",
          ];
          sessions.forEach((session) => {
            const created = session.created_at.substring(0, 19);
            lines.push(
              `| ${args.host_name} | ${session.session_name} | ${created} | 🟢 Active |`
            );
          });
          result = lines.join("\n");
        }
        break;

      case "new_terminal":
        const host = await apiCall("GET", `/hosts/by-name/${args.host_name}`);
        const newSession = await apiCall(
          "POST",
          `/hosts/${host.host_id}/sessions/new`,
          {}
        );
        result = `✅ Session Created\n\nHost: ${args.host_name}\nSession: ${newSession.session_name}\nCreated: ${newSession.created_at.substring(0, 19)}`;
        break;

      case "terminal_send":
        result = await sendToSession(
          args.host_name,
          args.session_name,
          args.input_string
        );
        break;

      case "terminal_read":
        result = await readFromSession(args.host_name, args.session_name);
        break;

      case "set_active_terminal":
        // Verify session exists
        const h = await apiCall("GET", `/hosts/by-name/${args.host_name}`);
        const sess = await apiCall(
          "POST",
          `/hosts/${h.host_id}/sessions/list`,
          {}
        );
        const found = sess.find((s) => s.session_name === args.session_name);
        if (!found) {
          throw new Error(
            `Session '${args.session_name}' not found on host '${args.host_name}'`
          );
        }
        activeTerminal.hostName = args.host_name;
        activeTerminal.sessionName = args.session_name;
        result = `✅ Active Terminal Set\n\nHost: ${args.host_name}\nSession: ${args.session_name}`;
        break;

      case "send":
        if (!activeTerminal.hostName || !activeTerminal.sessionName) {
          throw new Error(
            "No active terminal set. Use 'set_active_terminal' first."
          );
        }
        result = await sendToSession(
          activeTerminal.hostName,
          activeTerminal.sessionName,
          args.input_string
        );
        break;

      case "read":
        if (!activeTerminal.hostName || !activeTerminal.sessionName) {
          throw new Error(
            "No active terminal set. Use 'set_active_terminal' first."
          );
        }
        result = await readFromSession(
          activeTerminal.hostName,
          activeTerminal.sessionName
        );
        break;

      default:
        throw new Error(`Unknown tool: ${name}`);
    }

    return {
      content: [
        {
          type: "text",
          text: result,
        },
      ],
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `❌ Error: ${error.message}`,
        },
      ],
      isError: true,
    };
  }
});

// Helper: Send input to session
async function sendToSession(hostName, sessionName, inputString) {
  const host = await apiCall("GET", `/hosts/by-name/${hostName}`);
  const sessions = await apiCall(
    "POST",
    `/hosts/${host.host_id}/sessions/list`,
    {}
  );
  const session = sessions.find((s) => s.session_name === sessionName);
  if (!session) {
    throw new Error(`Session '${sessionName}' not found on host '${hostName}'`);
  }
  await apiCall("POST", `/sessions/${session.session_id}/input`, {
    input: inputString,
  });
  return `✅ Input Sent\n\nHost: ${hostName}\nSession: ${sessionName}\nInput: ${inputString}`;
}

// Helper: Read output from session
async function readFromSession(hostName, sessionName) {
  const host = await apiCall("GET", `/hosts/by-name/${hostName}`);
  const sessions = await apiCall(
    "POST",
    `/hosts/${host.host_id}/sessions/list`,
    {}
  );
  const session = sessions.find((s) => s.session_name === sessionName);
  if (!session) {
    throw new Error(`Session '${sessionName}' not found on host '${hostName}'`);
  }
  const output = await apiCall("GET", `/sessions/${session.session_id}/output`);
  return output.output || "";
}

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(
    `Remote Hosts MCP Client running (API: ${API_BASE})`
  );
}

main().catch((error) => {
  console.error("Server error:", error);
  process.exit(1);
});

