# Remote Hosts MCP Client

Node.js MCP client for the Remote Hosts Server. Works with Claude Desktop, Cursor, and other MCP-compatible AI tools.

## Installation

This package is designed to be run directly with `npx` - no installation needed!

## Usage with Claude Desktop

Add this to your Claude Desktop config file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`  
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`  
**Linux**: `~/.config/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "remote-hosts": {
      "command": "npx",
      "args": [
        "-y",
        "github:laelhalawani/remote_hosts_client",
        "--api-base",
        "https://localhost:8443"
      ]
    }
  }
}
```

**That's it!** No paths, no installation, works on any OS.

## Requirements

- Node.js 18+ installed
- Remote Terminal Control Server running on `https://localhost` (or specify different URL with `--api-base`)

## Available MCP Tools

Once configured, Claude will have access to these 9 tools:

1. **add_host** - Register a new remote SSH host
2. **hosts** - List all configured hosts
3. **terminal_sessions** - List terminal sessions on a host
4. **new_terminal** - Create a new terminal session
5. **terminal_send** - Send input to a specific session
6. **terminal_read** - Read output from a specific session
7. **set_active_terminal** - Set active session for shorthand commands
8. **send** - Send input to active terminal (shorthand)
9. **read** - Read output from active terminal (shorthand)

## Configuration

### Custom API URL

If your Terminal Control Server is running on a different machine:

```json
{
  "command": "npx",
  "args": [
    "-y",
    "github:laelhalawani/remote_hosts_client",
    "--api-base",
    "https://192.168.1.100:8443"
  ]
}
```

## Testing Locally

```bash
# Clone and test
git clone https://github.com/laelhalawani/remote_hosts_client
cd remote_hosts_client
npm install
node index.js --api-base https://localhost:8443
```

## How It Works

This client acts as a bridge between:
- **MCP protocol** (stdio) ↔ **Terminal Control API** (HTTP)

It translates MCP tool calls from Claude Desktop into HTTP API requests to your Terminal Control Server.

## Related Projects

- **[Remote Terminal Control Server](https://github.com/laelhalawani/remote_hosts_server)** - The main server (keep private if you want)
- This client can be public - it only contains the MCP interface, no sensitive code

## License

MIT

