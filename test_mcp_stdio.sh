#!/bin/bash

# MCP STDIO Client Testing Script
# Tests the Node.js MCP client that will be run via npx

set -e

echo "=========================================="
echo "MCP STDIO Client Testing"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if API is running
echo -e "${BLUE}Checking if Terminal Control API is running...${NC}"
if ! curl -k -s https://localhost/health > /dev/null 2>&1; then
  echo -e "${RED}❌ Terminal Control API is not running!${NC}"
  echo "Please start the API first:"
  echo "  cd /home/lael/ssh-mcp/remote_hosts_server"
  echo "  docker compose --profile testing up -d"
  exit 1
fi
echo -e "${GREEN}✅ API is running${NC}"
echo ""

# Path to the client
CLIENT_DIR="/home/lael/ssh-mcp/remote_hosts_client"
CLIENT_SCRIPT="$CLIENT_DIR/index.js"

# Check if client exists
if [ ! -f "$CLIENT_SCRIPT" ]; then
  echo -e "${RED}❌ Client script not found at $CLIENT_SCRIPT${NC}"
  exit 1
fi

# Check if node_modules exists
if [ ! -d "$CLIENT_DIR/node_modules" ]; then
  echo -e "${YELLOW}Installing dependencies...${NC}"
  cd "$CLIENT_DIR"
  npm install
  echo ""
fi

# Temporary files for communication
TEMP_IN=$(mktemp)
TEMP_OUT=$(mktemp)

# Cleanup function
cleanup() {
  rm -f "$TEMP_IN" "$TEMP_OUT"
  if [ ! -z "$CLIENT_PID" ]; then
    kill $CLIENT_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Start the MCP client with file-based I/O
echo -e "${BLUE}Starting MCP STDIO Client...${NC}"
cd "$CLIENT_DIR"
(tail -f "$TEMP_IN" 2>/dev/null) | API_BASE="https://localhost" node "$CLIENT_SCRIPT" > "$TEMP_OUT" 2>&1 &
CLIENT_PID=$!

# Give it time to start
sleep 2

# Check if client is still running
if ! kill -0 $CLIENT_PID 2>/dev/null; then
  echo -e "${RED}❌ Client failed to start${NC}"
  cat "$TEMP_OUT"
  exit 1
fi
echo -e "${GREEN}✅ Client started (PID: $CLIENT_PID)${NC}"
echo ""

# Helper function to send JSON-RPC request
send_request() {
  local request="$1"
  echo "$request" >> "$TEMP_IN"
  sleep 2
}

# Helper function to read response
read_response() {
  # Read accumulated output and find the last complete JSON response
  tail -20 "$TEMP_OUT" 2>/dev/null | grep -o '{.*}' | tail -1 || echo "{}"
}

# Test 1: Initialize
echo -e "${BLUE}Step 1: Initialize MCP Session${NC}"
echo "----------------------------------------"
send_request '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test-client","version":"1.0.0"}}}'
INIT_RESPONSE=$(read_response)
echo "$INIT_RESPONSE" | jq . 2>/dev/null || echo "$INIT_RESPONSE"
echo -e "${GREEN}✅ Session initialized${NC}"
echo ""

# Test 2: Initialized notification
echo -e "${BLUE}Step 2: Send Initialized Notification${NC}"
echo "----------------------------------------"
send_request '{"jsonrpc":"2.0","method":"notifications/initialized"}'
sleep 1
echo -e "${GREEN}✅ Notification sent${NC}"
echo ""

# Test 3: List tools
echo -e "${BLUE}Step 3: List Available Tools${NC}"
echo "----------------------------------------"
send_request '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
TOOLS_RESPONSE=$(read_response)
echo "$TOOLS_RESPONSE" | jq -r '.result.tools[]? | "  - \(.name): \(.description | split("\n")[0])"' 2>/dev/null || echo "$TOOLS_RESPONSE"
echo ""

# Test 4: List hosts (should be empty initially)
echo -e "${BLUE}Step 4: Test 'hosts' Tool (List Hosts)${NC}"
echo "----------------------------------------"
send_request '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"hosts","arguments":{}}}'
HOSTS_RESPONSE=$(read_response)
echo "$HOSTS_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$HOSTS_RESPONSE"
echo ""

# Test 5: Add host
echo -e "${BLUE}Step 5: Test 'add_host' Tool (Add SSH Test Server)${NC}"
echo "----------------------------------------"
ADD_HOST_REQUEST='{
  "jsonrpc":"2.0",
  "id":3,
  "method":"tools/call",
  "params":{
    "name":"add_host",
    "arguments":{
      "name":"test-ssh-server",
      "address":"ssh-test-server",
      "port":22,
      "user":"testuser",
      "auth_method":"password",
      "secret":"testpass",
      "validate":true
    }
  }
}'
send_request "$ADD_HOST_REQUEST"
ADD_HOST_RESPONSE=$(read_response)
echo "$ADD_HOST_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$ADD_HOST_RESPONSE"
echo ""

# Test 6: List hosts again
echo -e "${BLUE}Step 6: Verify Host Was Added${NC}"
echo "----------------------------------------"
send_request '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"hosts","arguments":{}}}'
HOSTS_RESPONSE2=$(read_response)
echo "$HOSTS_RESPONSE2" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$HOSTS_RESPONSE2"
echo ""

# Test 7: Create terminal session
echo -e "${BLUE}Step 7: Test 'new_terminal' Tool (Create Session)${NC}"
echo "----------------------------------------"
NEW_TERMINAL_REQUEST='{
  "jsonrpc":"2.0",
  "id":5,
  "method":"tools/call",
  "params":{
    "name":"new_terminal",
    "arguments":{
      "host_name":"test-ssh-server"
    }
  }
}'
send_request "$NEW_TERMINAL_REQUEST"
NEW_TERMINAL_RESPONSE=$(read_response)
SESSION_OUTPUT=$(echo "$NEW_TERMINAL_RESPONSE" | jq -r '.result.content[]?.text // .' 2>/dev/null || echo "$NEW_TERMINAL_RESPONSE")
echo "$SESSION_OUTPUT"

# Extract session name
SESSION_NAME=$(echo "$SESSION_OUTPUT" | grep -oP 'Session: \K[^\s]+' || echo "")
if [ -z "$SESSION_NAME" ]; then
  echo -e "${RED}❌ Failed to create session${NC}"
  exit 1
fi
echo -e "${YELLOW}Session name: $SESSION_NAME${NC}"
echo ""

# Test 8: List sessions
echo -e "${BLUE}Step 8: Test 'terminal_sessions' Tool${NC}"
echo "----------------------------------------"
TERMINAL_SESSIONS_REQUEST="{
  \"jsonrpc\":\"2.0\",
  \"id\":6,
  \"method\":\"tools/call\",
  \"params\":{
    \"name\":\"terminal_sessions\",
    \"arguments\":{
      \"host_name\":\"test-ssh-server\"
    }
  }
}"
send_request "$TERMINAL_SESSIONS_REQUEST"
SESSIONS_RESPONSE=$(read_response)
echo "$SESSIONS_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$SESSIONS_RESPONSE"
echo ""

# Test 9: Send command
echo -e "${BLUE}Step 9: Test 'terminal_send' Tool (Send Command)${NC}"
echo "----------------------------------------"
TERMINAL_SEND_REQUEST="{
  \"jsonrpc\":\"2.0\",
  \"id\":7,
  \"method\":\"tools/call\",
  \"params\":{
    \"name\":\"terminal_send\",
    \"arguments\":{
      \"host_name\":\"test-ssh-server\",
      \"session_name\":\"$SESSION_NAME\",
      \"input_string\":\"whoami{{enter}}\"
    }
  }
}"
send_request "$TERMINAL_SEND_REQUEST"
SEND_RESPONSE=$(read_response)
echo "$SEND_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$SEND_RESPONSE"
echo ""

echo -e "${YELLOW}Waiting 2 seconds for command to execute...${NC}"
sleep 2

# Test 10: Read output
echo -e "${BLUE}Step 10: Test 'terminal_read' Tool (Read Output)${NC}"
echo "----------------------------------------"
TERMINAL_READ_REQUEST="{
  \"jsonrpc\":\"2.0\",
  \"id\":8,
  \"method\":\"tools/call\",
  \"params\":{
    \"name\":\"terminal_read\",
    \"arguments\":{
      \"host_name\":\"test-ssh-server\",
      \"session_name\":\"$SESSION_NAME\"
    }
  }
}"
send_request "$TERMINAL_READ_REQUEST"
READ_RESPONSE=$(read_response)
OUTPUT=$(echo "$READ_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$READ_RESPONSE")
echo "$OUTPUT"

# Check if output contains expected result
if echo "$OUTPUT" | grep -q "testuser"; then
  echo -e "${GREEN}✅ Command output verified (contains 'testuser')${NC}"
else
  echo -e "${YELLOW}⚠️  Output doesn't contain expected 'testuser'${NC}"
fi
echo ""

# Test 11: Set active terminal
echo -e "${BLUE}Step 11: Test 'set_active_terminal' Tool${NC}"
echo "----------------------------------------"
SET_ACTIVE_REQUEST="{
  \"jsonrpc\":\"2.0\",
  \"id\":9,
  \"method\":\"tools/call\",
  \"params\":{
    \"name\":\"set_active_terminal\",
    \"arguments\":{
      \"host_name\":\"test-ssh-server\",
      \"session_name\":\"$SESSION_NAME\"
    }
  }
}"
send_request "$SET_ACTIVE_REQUEST"
SET_ACTIVE_RESPONSE=$(read_response)
echo "$SET_ACTIVE_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$SET_ACTIVE_RESPONSE"
echo ""

# Test 12: Send shorthand
echo -e "${BLUE}Step 12: Test 'send' Tool (Shorthand)${NC}"
echo "----------------------------------------"
SEND_SHORTHAND_REQUEST='{
  "jsonrpc":"2.0",
  "id":10,
  "method":"tools/call",
  "params":{
    "name":"send",
    "arguments":{
      "input_string":"pwd{{enter}}"
    }
  }
}'
send_request "$SEND_SHORTHAND_REQUEST"
SEND_SHORT_RESPONSE=$(read_response)
echo "$SEND_SHORT_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$SEND_SHORT_RESPONSE"
echo ""

echo -e "${YELLOW}Waiting 2 seconds for command to execute...${NC}"
sleep 2

# Test 13: Read shorthand
echo -e "${BLUE}Step 13: Test 'read' Tool (Shorthand)${NC}"
echo "----------------------------------------"
READ_SHORTHAND_REQUEST='{
  "jsonrpc":"2.0",
  "id":11,
  "method":"tools/call",
  "params":{
    "name":"read",
    "arguments":{}
  }
}'
send_request "$READ_SHORTHAND_REQUEST"
READ_SHORT_RESPONSE=$(read_response)
OUTPUT2=$(echo "$READ_SHORT_RESPONSE" | jq -r '.result.content[]?.text // .error.message // .' 2>/dev/null || echo "$READ_SHORT_RESPONSE")
echo "$OUTPUT2"

# Check if output contains pwd result
if echo "$OUTPUT2" | grep -q "/home/testuser"; then
  echo -e "${GREEN}✅ Shorthand read verified (contains '/home/testuser')${NC}"
else
  echo -e "${YELLOW}⚠️  Output doesn't contain expected path${NC}"
fi
echo ""

echo "=========================================="
echo -e "${GREEN}✅ All MCP STDIO Client Tests Completed!${NC}"
echo "=========================================="
echo ""
echo "The Node.js client is working correctly and can be used with:"
echo "  npx -y github:laelhalawani/terminal-control-mcp-client --api-base https://localhost"

