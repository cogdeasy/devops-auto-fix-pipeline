# AI-Driven DevOps Auto-Fix Pipeline

An AI-powered auto-fix pipeline that automates issue detection, resolution, and deployment in CI/CD — orchestrated through **Windsurf Cascade** with MCP (Model Context Protocol) integrations.

## Overview

This pipeline implements the HSBC AI-Driven DevOps Auto-Fix workflow from Confluence, providing two operating modes:

| Mode | Description | When to use |
|------|-------------|-------------|
| **Automated (MCP-connected)** | Windsurf connects directly to Jenkins, GitHub, Confluence, Nexus via MCP servers | Full automation — MCPs are configured and network-accessible |
| **Manual (Human-in-the-loop)** | User pastes logs, Confluence pages, Jenkins output into Windsurf prompts | MCPs unavailable, air-gapped environments, or when human review is required at every step |

## Pipeline Stages

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌────────────┐    ┌─────────────┐
│  1. Failure  │───>│  2. Log      │───>│  3. Patch        │───>│ 4. Validate│───>│ 5. PR       │
│  Detection   │    │  Analysis    │    │  Generation      │    │            │    │ Creation    │
└─────────────┘    └──────────────┘    └─────────────────┘    └────────────┘    └─────────────┘
    Jenkins            AI Service          AI Service           Build+Test        GitHub
    (MCP/manual)       (Windsurf)          (Windsurf)           (Jenkins)         (MCP/manual)
```

## Key Features

- **Automated Build Fixes** — AI analyzes build failures and suggests fixes
- **Smart PR Generation** — Creates pull requests for human review
- **Kubernetes Deployment** — Handles containerization and deployment
- **Self-Healing** — Automatically retries with AI-generated patches
- **Dual-mode operation** — Fully automated OR manual paste workflows

## Architecture

### Components

| Component | Purpose | MCP Server |
|-----------|---------|------------|
| Jenkins | Orchestrates the CI/CD pipeline | `jenkins-mcp` |
| Confluence | Documentation & runbooks | `confluence-mcp` |
| GitHub | Version control & PR management | `github-mcp` |
| Docker | Containerization | (via Jenkins) |
| Kubernetes | Container orchestration | (via Jenkins) |
| Nexus | Artifact repository | `nexus-mcp` |

### MCP Integration Map

```
Windsurf Cascade
    │
    ├── jenkins-mcp ────── Jenkins API (build triggers, log retrieval, status)
    │
    ├── confluence-mcp ─── Confluence API (runbooks, known issues, documentation)
    │
    ├── github-mcp ─────── GitHub API (PRs, commits, branch management)
    │
    └── nexus-mcp ──────── Nexus API (artifact status, dependency checks)
```

When MCPs are **not connected**, the user manually provides this data by pasting into Windsurf prompts.

## Project Structure

```
devops-auto-fix-pipeline/
├── .windsurf/
│   ├── workflows/              # Windsurf Cascade workflow definitions
│   │   ├── auto-fix-full.md    # Full automated pipeline (all MCPs)
│   │   ├── auto-fix-manual.md  # Manual mode (human pastes data)
│   │   └── stages/             # Individual stage workflows
│   │       ├── 01-detect.md
│   │       ├── 02-analyse.md
│   │       ├── 03-patch.md
│   │       ├── 04-validate.md
│   │       └── 05-pr-create.md
│   └── rules/
│       └── devops-pipeline.md  # Rules and conventions
│
├── mcp-servers/                # MCP server implementations
│   ├── jenkins-mcp/            # Jenkins MCP server
│   ├── confluence-mcp/         # Confluence MCP server
│   ├── github-mcp/             # GitHub MCP (uses existing)
│   └── nexus-mcp/              # Nexus MCP server
│
├── workflows/                  # Reusable workflow templates
│   ├── pipeline.yaml           # Master pipeline definition
│   └── prompts/                # Prompt templates for each stage
│
├── scripts/                    # Helper scripts
│   ├── setup-mcp.sh            # MCP server setup script
│   └── validate-fix.sh         # Local validation script
│
├── examples/                   # Example inputs/outputs
│   ├── jenkins-build-log.txt
│   ├── sample-patch.diff
│   └── sample-pr-body.md
│
├── docs/
│   ├── MCP-INTEGRATION.md      # Detailed MCP breakout
│   └── MANUAL-MODE.md          # How to use without MCPs
│
├── mcp-config.json             # Windsurf MCP config (copy to ~/.codeium/windsurf/)
└── README.md
```

## Quick Start

### Mode 1: Automated (MCP-connected)

1. Copy MCP config:
   ```bash
   cp mcp-config.json ~/.codeium/windsurf/mcp_config.json
   ```
2. Set environment variables (Jenkins URL, tokens, etc.)
3. Open Windsurf and invoke the workflow:
   ```
   @workflow auto-fix-full
   ```

### Mode 2: Manual (Human-in-the-loop)

1. Open Windsurf (no MCP config needed)
2. Invoke the manual workflow:
   ```
   @workflow auto-fix-manual
   ```
3. Paste your Jenkins build log when prompted
4. Review AI analysis and proposed fix
5. Paste into your PR tool or let Windsurf create a local patch

## Security & Compliance

- All AI-generated changes are logged
- PRs require human approval before merge
- Audit trail maintained through Jenkins + GitHub
- No credentials stored in workflow files — uses environment variables

## License

Internal use only — HSBC Enterprise.
