#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# setup-mcp.sh
#
# Setup script for the AI-Driven DevOps Auto-Fix Pipeline MCP servers.
#
# This script performs the following:
#   1. Checks prerequisites (node, npm, npx, tsx, git, jq)
#   2. Installs npm dependencies for each MCP server
#   3. Prompts for environment variables (API tokens, URLs, etc.)
#   4. Creates a .env file in the project root
#   5. Configures Windsurf MCP integration
#   6. Validates MCP server entry points
#   7. Prints a setup summary
#
# Usage:
#   bash scripts/setup-mcp.sh
#
# ==============================================================================

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_SERVERS_DIR="${PROJECT_ROOT}/mcp-servers"
WINDSURF_CONFIG_DIR="${HOME}/.codeium/windsurf"
WINDSURF_CONFIG_FILE="${WINDSURF_CONFIG_DIR}/mcp_config.json"
ENV_FILE="${PROJECT_ROOT}/.env"

MCP_SERVER_DIRS=("jenkins-mcp" "confluence-mcp" "github-mcp" "nexus-mcp")

# ---------------------------------------------------------------------------
# Tracking arrays for the summary
# ---------------------------------------------------------------------------

DEPS_INSTALLED=()
DEPS_SKIPPED=()
ENV_VARS_SET=()
ENV_VARS_SKIPPED=()
SERVERS_PASSED=()
SERVERS_FAILED=()
WINDSURF_STATUS="not configured"

# ---------------------------------------------------------------------------
# Color and formatting helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD="\033[1m"
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    CYAN="\033[0;36m"
    RESET="\033[0m"
else
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    RESET=""
fi

info() {
    printf "${CYAN}[INFO]${RESET}  %s\n" "$*"
}

warn() {
    printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"
}

error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
}

success() {
    printf "${GREEN}[ OK ]${RESET}  %s\n" "$*"
}

header() {
    printf "\n${BOLD}%s${RESET}\n" "$*"
    printf "%s\n" "$(printf '%.0s-' $(seq 1 ${#1}))"
}

# ---------------------------------------------------------------------------
# 1. Check prerequisites
# ---------------------------------------------------------------------------

check_prerequisites() {
    header "Checking prerequisites"

    local missing=()

    # -- node (>=18) --
    if command -v node &>/dev/null; then
        local node_version
        node_version="$(node --version)"
        local node_major
        node_major="$(echo "${node_version}" | sed 's/^v//' | cut -d. -f1)"
        if [[ "${node_major}" -ge 18 ]]; then
            success "node ${node_version}"
        else
            error "node ${node_version} found but >=18 is required"
            missing+=("node>=18")
        fi
    else
        error "node is not installed"
        missing+=("node")
    fi

    # -- npm --
    if command -v npm &>/dev/null; then
        success "npm $(npm --version)"
    else
        error "npm is not installed"
        missing+=("npm")
    fi

    # -- npx --
    if command -v npx &>/dev/null; then
        success "npx $(npx --version 2>/dev/null || echo 'unknown')"
    else
        error "npx is not installed"
        missing+=("npx")
    fi

    # -- tsx --
    if command -v tsx &>/dev/null; then
        success "tsx $(tsx --version 2>/dev/null || echo 'unknown')"
    elif npx tsx --version &>/dev/null; then
        success "tsx (available via npx) $(npx tsx --version 2>/dev/null || echo 'unknown')"
    else
        error "tsx is not installed (install globally: npm install -g tsx)"
        missing+=("tsx")
    fi

    # -- git --
    if command -v git &>/dev/null; then
        success "git $(git --version | awk '{print $3}')"
    else
        error "git is not installed"
        missing+=("git")
    fi

    # -- jq --
    if command -v jq &>/dev/null; then
        success "jq $(jq --version 2>/dev/null || echo 'unknown')"
    else
        error "jq is not installed"
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "\n"
        error "Missing prerequisites: ${missing[*]}"
        error "Please install the above tools and re-run this script."
        exit 1
    fi

    printf "\n"
    success "All prerequisites satisfied."
}

# ---------------------------------------------------------------------------
# 2. Install dependencies
# ---------------------------------------------------------------------------

install_dependencies() {
    header "Installing MCP server dependencies"

    for dir in "${MCP_SERVER_DIRS[@]}"; do
        local server_path="${MCP_SERVERS_DIR}/${dir}"

        if [[ ! -d "${server_path}" ]]; then
            warn "${dir}: directory not found at ${server_path} -- skipping"
            DEPS_SKIPPED+=("${dir} (directory missing)")
            continue
        fi

        if [[ ! -f "${server_path}/package.json" ]]; then
            info "${dir}: no package.json found -- skipping npm install"
            DEPS_SKIPPED+=("${dir} (no package.json)")
            continue
        fi

        info "${dir}: running npm install ..."
        if (cd "${server_path}" && npm install --no-fund --no-audit 2>&1 | tail -1); then
            success "${dir}: dependencies installed"
            DEPS_INSTALLED+=("${dir}")
        else
            warn "${dir}: npm install encountered errors (see output above)"
            DEPS_SKIPPED+=("${dir} (npm install failed)")
        fi
    done
}

# ---------------------------------------------------------------------------
# 3. Prompt for environment variables
# ---------------------------------------------------------------------------

# Helper: prompt for a value, optionally hiding input.
#   prompt_var VARNAME "Prompt text" "example/default" [secret]
prompt_var() {
    local varname="$1"
    local prompt_text="$2"
    local example="$3"
    local secret="${4:-}"
    local value=""

    printf "\n  ${BOLD}%s${RESET}\n" "${prompt_text}"
    if [[ -n "${example}" ]]; then
        printf "  Example: %s\n" "${example}"
    fi
    printf "  (Press Enter to skip)\n"

    if [[ "${secret}" == "secret" ]]; then
        printf "  > "
        read -r -s value
        printf "\n"
    else
        printf "  > "
        read -r value
    fi

    # Trim whitespace
    value="$(echo "${value}" | xargs)"

    if [[ -n "${value}" ]]; then
        eval "${varname}=\"${value}\""
        ENV_VARS_SET+=("${varname}")
        success "${varname} set"
    else
        eval "${varname}="
        ENV_VARS_SKIPPED+=("${varname}")
        info "${varname} skipped"
    fi
}

prompt_environment_variables() {
    header "Environment variable configuration"
    info "Provide credentials for each service. Leave blank to skip."

    # Jenkins
    printf "\n${BOLD}  -- Jenkins --%s\n" "${RESET}"
    prompt_var JENKINS_URL   "Jenkins server URL"            "https://jenkins.example.com"
    prompt_var JENKINS_USER  "Jenkins username"               "admin"
    prompt_var JENKINS_TOKEN "Jenkins API token"              "(your API token)" secret

    # Confluence
    printf "\n${BOLD}  -- Confluence --%s\n" "${RESET}"
    prompt_var CONFLUENCE_URL   "Confluence server URL"       "https://confluence.example.com"
    prompt_var CONFLUENCE_USER  "Confluence username"          "admin"
    prompt_var CONFLUENCE_TOKEN "Confluence API token"         "(your API token)" secret

    # Nexus
    printf "\n${BOLD}  -- Nexus --%s\n" "${RESET}"
    prompt_var NEXUS_URL   "Nexus repository URL"             "https://nexus.example.com"
    prompt_var NEXUS_TOKEN "Nexus API token"                   "(your API token)" secret

    # GitHub
    printf "\n${BOLD}  -- GitHub --%s\n" "${RESET}"
    prompt_var GITHUB_TOKEN "GitHub Personal Access Token"     "(your PAT)" secret
}

# ---------------------------------------------------------------------------
# 4. Create .env file
# ---------------------------------------------------------------------------

create_env_file() {
    header "Creating .env file"

    local env_lines=()
    env_lines+=("# ============================================================")
    env_lines+=("# AI-Driven DevOps Auto-Fix Pipeline -- Environment Variables")
    env_lines+=("# Generated by scripts/setup-mcp.sh on $(date '+%Y-%m-%d %H:%M:%S')")
    env_lines+=("#")
    env_lines+=("# WARNING: This file contains secrets. Do NOT commit it to git.")
    env_lines+=("# ============================================================")
    env_lines+=("")

    local wrote_any=false

    write_var() {
        local name="$1"
        local value="${!name:-}"
        if [[ -n "${value}" ]]; then
            env_lines+=("${name}=${value}")
            wrote_any=true
        fi
    }

    # Jenkins
    env_lines+=("# -- Jenkins --")
    write_var JENKINS_URL
    write_var JENKINS_USER
    write_var JENKINS_TOKEN
    env_lines+=("")

    # Confluence
    env_lines+=("# -- Confluence --")
    write_var CONFLUENCE_URL
    write_var CONFLUENCE_USER
    write_var CONFLUENCE_TOKEN
    env_lines+=("")

    # Nexus
    env_lines+=("# -- Nexus --")
    write_var NEXUS_URL
    write_var NEXUS_TOKEN
    env_lines+=("")

    # GitHub
    env_lines+=("# -- GitHub --")
    write_var GITHUB_TOKEN
    env_lines+=("")

    if [[ "${wrote_any}" == true ]]; then
        printf "%s\n" "${env_lines[@]}" > "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"
        success "Wrote ${ENV_FILE}"
        warn "Do not commit .env to version control. Ensure it is listed in .gitignore."
    else
        info "No environment variables provided -- .env file not created."
    fi
}

# ---------------------------------------------------------------------------
# 5. Configure Windsurf MCP
# ---------------------------------------------------------------------------

configure_windsurf() {
    header "Configuring Windsurf MCP integration"

    local source_config="${PROJECT_ROOT}/mcp-config.json"

    if [[ ! -f "${source_config}" ]]; then
        warn "Source config not found at ${source_config} -- skipping Windsurf configuration."
        WINDSURF_STATUS="skipped (source config missing)"
        return
    fi

    # Ensure the Windsurf config directory exists
    if [[ ! -d "${WINDSURF_CONFIG_DIR}" ]]; then
        info "Creating Windsurf config directory: ${WINDSURF_CONFIG_DIR}"
        mkdir -p "${WINDSURF_CONFIG_DIR}"
    fi

    # Back up existing config
    if [[ -f "${WINDSURF_CONFIG_FILE}" ]]; then
        local backup="${WINDSURF_CONFIG_FILE}.backup.$(date '+%Y%m%d_%H%M%S')"
        cp "${WINDSURF_CONFIG_FILE}" "${backup}"
        info "Existing config backed up to: ${backup}"
    fi

    # Copy the project config into Windsurf location
    cp "${source_config}" "${WINDSURF_CONFIG_FILE}"
    success "Copied mcp-config.json -> ${WINDSURF_CONFIG_FILE}"
    WINDSURF_STATUS="configured"
}

# ---------------------------------------------------------------------------
# 6. Test MCP servers
# ---------------------------------------------------------------------------

test_mcp_servers() {
    header "Validating MCP server entry points"

    # Map of server name -> entry point (relative to PROJECT_ROOT)
    declare -A SERVER_ENTRIES=(
        ["jenkins-mcp"]="mcp-servers/jenkins-mcp/index.ts"
        ["confluence-mcp"]="mcp-servers/confluence-mcp/index.ts"
        ["nexus-mcp"]="mcp-servers/nexus-mcp/index.ts"
    )

    # Custom MCP servers with index.ts
    for server in jenkins-mcp confluence-mcp nexus-mcp; do
        local entry="${PROJECT_ROOT}/${SERVER_ENTRIES[${server}]}"

        if [[ -f "${entry}" ]]; then
            # Verify that tsx can at least parse the file (syntax check)
            if npx tsx --eval "import '${entry}'" &>/dev/null & then
                local pid=$!
                # Give it a few seconds to start, then kill it -- we just need
                # to know it does not crash immediately.
                sleep 2
                if kill -0 "${pid}" 2>/dev/null; then
                    # Process is still running -- that counts as a pass
                    kill "${pid}" 2>/dev/null || true
                    wait "${pid}" 2>/dev/null || true
                    success "${server}: entry point OK (${SERVER_ENTRIES[${server}]})"
                    SERVERS_PASSED+=("${server}")
                else
                    # Process exited -- check if it was a clean exit
                    wait "${pid}" 2>/dev/null
                    local exit_code=$?
                    if [[ ${exit_code} -eq 0 ]]; then
                        success "${server}: entry point OK (${SERVER_ENTRIES[${server}]})"
                        SERVERS_PASSED+=("${server}")
                    else
                        warn "${server}: process exited with code ${exit_code} (may need env vars)"
                        SERVERS_FAILED+=("${server}")
                    fi
                fi
            else
                warn "${server}: failed to start"
                SERVERS_FAILED+=("${server}")
            fi
        else
            warn "${server}: entry point not found at ${entry}"
            SERVERS_FAILED+=("${server}")
        fi
    done

    # github-mcp uses the upstream npm package, not a local index.ts
    info "github-mcp: uses @modelcontextprotocol/server-github (upstream package)"
    if npx -y @modelcontextprotocol/server-github --help &>/dev/null 2>&1; then
        success "github-mcp: package is available"
        SERVERS_PASSED+=("github-mcp")
    else
        # The package may not support --help; just verify it can be resolved
        if npm ls @modelcontextprotocol/server-github &>/dev/null 2>&1 \
           || npm view @modelcontextprotocol/server-github version &>/dev/null 2>&1; then
            success "github-mcp: package is resolvable via npm"
            SERVERS_PASSED+=("github-mcp")
        else
            warn "github-mcp: could not verify package availability"
            SERVERS_FAILED+=("github-mcp")
        fi
    fi
}

# ---------------------------------------------------------------------------
# 7. Print summary
# ---------------------------------------------------------------------------

print_summary() {
    header "Setup Summary"

    # Dependencies
    printf "\n  ${BOLD}Dependencies installed:${RESET}\n"
    if [[ ${#DEPS_INSTALLED[@]} -gt 0 ]]; then
        for item in "${DEPS_INSTALLED[@]}"; do
            printf "    [+] %s\n" "${item}"
        done
    else
        printf "    (none)\n"
    fi
    if [[ ${#DEPS_SKIPPED[@]} -gt 0 ]]; then
        printf "  ${BOLD}Dependencies skipped:${RESET}\n"
        for item in "${DEPS_SKIPPED[@]}"; do
            printf "    [-] %s\n" "${item}"
        done
    fi

    # Environment variables
    printf "\n  ${BOLD}Environment variables configured:${RESET}\n"
    if [[ ${#ENV_VARS_SET[@]} -gt 0 ]]; then
        for item in "${ENV_VARS_SET[@]}"; do
            printf "    [+] %s\n" "${item}"
        done
    else
        printf "    (none)\n"
    fi
    if [[ ${#ENV_VARS_SKIPPED[@]} -gt 0 ]]; then
        printf "  ${BOLD}Environment variables skipped:${RESET}\n"
        for item in "${ENV_VARS_SKIPPED[@]}"; do
            printf "    [-] %s\n" "${item}"
        done
    fi

    # Windsurf
    printf "\n  ${BOLD}Windsurf MCP:${RESET} %s\n" "${WINDSURF_STATUS}"

    # Server validation
    printf "\n  ${BOLD}MCP server validation:${RESET}\n"
    if [[ ${#SERVERS_PASSED[@]} -gt 0 ]]; then
        for item in "${SERVERS_PASSED[@]}"; do
            printf "    [PASS] %s\n" "${item}"
        done
    fi
    if [[ ${#SERVERS_FAILED[@]} -gt 0 ]]; then
        for item in "${SERVERS_FAILED[@]}"; do
            printf "    [FAIL] %s\n" "${item}"
        done
    fi
    if [[ ${#SERVERS_PASSED[@]} -eq 0 && ${#SERVERS_FAILED[@]} -eq 0 ]]; then
        printf "    (no servers tested)\n"
    fi

    # Next steps
    printf "\n${BOLD}Next steps:${RESET}\n"
    printf "  1. Review and edit %s if you need to adjust credentials.\n" "${ENV_FILE}"
    printf "  2. Open the project in Windsurf to use the MCP servers.\n"
    printf "  3. Run individual servers manually for debugging:\n"
    printf "       npx tsx mcp-servers/jenkins-mcp/index.ts\n"
    printf "  4. See docs/ and README.md for full documentation.\n"
    printf "\n"
    success "Setup complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf "\n${BOLD}AI-Driven DevOps Auto-Fix Pipeline -- MCP Setup${RESET}\n"
    printf "=================================================\n\n"
    info "Project root: ${PROJECT_ROOT}"

    check_prerequisites
    install_dependencies
    prompt_environment_variables
    create_env_file
    configure_windsurf
    test_mcp_servers
    print_summary
}

main "$@"
