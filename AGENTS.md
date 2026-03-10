# DevOps Auto-Fix Pipeline — Agent Instructions

## Project Overview
This is an AI-Driven DevOps Auto-Fix Pipeline that operates in two modes:
1. **MCP mode** — MCP servers connect directly to Jenkins, Confluence, GitHub, Nexus
2. **Paste mode** — Users paste data from these tools into prompts

## Build & Verify
- MCP servers: `cd mcp-servers/<name> && npm install && npx tsx index.ts`
- No global build command — each MCP server is independent
- Validate scripts: `bash scripts/validate-fix.sh <branch-name>`

## Key Conventions
- Windsurf workflows live in `.windsurf/workflows/`
- MCP server implementations in `mcp-servers/`
- Never store credentials in files — use environment variables
- All AI-generated patches must be validated before PR creation
- Maximum 3 retry attempts for fix validation
- Always create feature branches, never commit to main

## MCP Servers
| Server | Directory | Port/Transport |
|--------|-----------|----------------|
| jenkins-mcp | mcp-servers/jenkins-mcp/ | stdio |
| confluence-mcp | mcp-servers/confluence-mcp/ | stdio |
| nexus-mcp | mcp-servers/nexus-mcp/ | stdio |
| github | (external: @modelcontextprotocol/server-github) | stdio |
