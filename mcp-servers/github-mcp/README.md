# GitHub MCP Server

For GitHub integration, this pipeline uses the official MCP server for GitHub rather than a custom implementation.

## Option 1: Official MCP Server (Recommended)

Use `@modelcontextprotocol/server-github` which provides full GitHub API access including:

- Repository management
- Pull request creation and review
- Issue tracking
- File operations (read, create, update)
- Branch management
- Code search

### Configuration

Add the following to your `mcp_config.json`:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-github-pat>"
      }
    }
  }
}
```

### Required Token Scopes

Your GitHub Personal Access Token needs the following scopes:
- `repo` — Full control of private repositories
- `read:org` — Read org membership (if accessing org repos)
- `workflow` — Update GitHub Actions workflows (if triggering CI)

## Option 2: GitHub CLI (`gh`)

Alternatively, you can use the `gh` CLI directly in workflows. The DevOps pipeline scripts already support `gh` for:

- Creating pull requests: `gh pr create --title "fix: ..." --body "..."`
- Checking PR status: `gh pr status`
- Merging PRs: `gh pr merge --auto`

Ensure `gh` is authenticated:

```bash
gh auth login
gh auth status
```

## Usage in the Pipeline

The auto-fix pipeline uses GitHub MCP for:

1. **Reading source code** that caused build failures
2. **Creating fix branches** with corrected code
3. **Opening pull requests** with AI-generated fixes
4. **Adding PR comments** with analysis details
5. **Monitoring CI status** on fix PRs
