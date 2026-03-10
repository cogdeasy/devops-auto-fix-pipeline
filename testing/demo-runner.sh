#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# AI Auto-Fix Pipeline — Interactive Demo Runner
# ============================================================================
# This script guides you through testing scenarios step-by-step.
# It displays the data you need to paste into Windsurf at each stage.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIOS_DIR="${SCRIPT_DIR}/scenarios"

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

divider() {
    echo ""
    printf "${BLUE}%s${NC}\n" "$(printf '=%.0s' {1..72})"
    echo ""
}

header() {
    divider
    printf "${BOLD}${CYAN}  %s${NC}\n" "$1"
    divider
}

step() {
    printf "\n${BOLD}${GREEN}  STEP %s: %s${NC}\n\n" "$1" "$2"
}

info() {
    printf "  ${YELLOW}%s${NC}\n" "$1"
}

prompt() {
    printf "\n${BOLD}  Press Enter to continue (or 'q' to quit)...${NC}"
    read -r choice
    if [[ "${choice}" == "q" ]]; then
        echo "  Exiting."
        exit 0
    fi
}

show_file() {
    local file="$1"
    local label="$2"
    printf "\n${BOLD}  --- %s ---${NC}\n\n" "${label}"
    if [[ -f "${file}" ]]; then
        sed 's/^/    /' "${file}"
    else
        printf "    ${RED}File not found: %s${NC}\n" "${file}"
    fi
    echo ""
}

# ============================================================================
# Scenario Selection
# ============================================================================

header "AI Auto-Fix Pipeline — Demo Runner"

echo "  Available scenarios:"
echo ""
echo "    1) Java Compilation Failure (Maven / BigDecimal type mismatch)"
echo "    2) Node.js Test Failure (Jest / response format change)"
echo "    3) Dependency Vulnerability (Nexus / Log4Shell CVE)"
echo "    4) Kubernetes Deployment Failure (wrong image tag + resource limits)"
echo ""
printf "  ${BOLD}Select scenario [1-4]: ${NC}"
read -r scenario_num

case "${scenario_num}" in
    1) SCENARIO_DIR="${SCENARIOS_DIR}/01-java-compilation-failure"
       SCENARIO_NAME="Java Compilation Failure" ;;
    2) SCENARIO_DIR="${SCENARIOS_DIR}/02-nodejs-test-failure"
       SCENARIO_NAME="Node.js Test Failure" ;;
    3) SCENARIO_DIR="${SCENARIOS_DIR}/03-dependency-vulnerability"
       SCENARIO_NAME="Dependency Vulnerability" ;;
    4) SCENARIO_DIR="${SCENARIOS_DIR}/04-k8s-deployment-failure"
       SCENARIO_NAME="Kubernetes Deployment Failure" ;;
    *) echo "  Invalid selection."; exit 1 ;;
esac

if [[ ! -d "${SCENARIO_DIR}" ]]; then
    echo "  ${RED}Scenario directory not found: ${SCENARIO_DIR}${NC}"
    exit 1
fi

header "Scenario: ${SCENARIO_NAME}"

# Show README
if [[ -f "${SCENARIO_DIR}/README.md" ]]; then
    show_file "${SCENARIO_DIR}/README.md" "Scenario Description"
fi

prompt

# ============================================================================
# Stage 1: Failure Detection
# ============================================================================

step "1" "Failure Detection — Paste the Jenkins log into Windsurf"

info "In Windsurf, type:  @workflow auto-fix-paste"
info "When prompted for the build failure, copy-paste the following log:"

prompt

show_file "${SCENARIO_DIR}/jenkins-console.log" "Jenkins Console Log (copy this into Windsurf)"

info "Copy the above log and paste it into Windsurf."
info "Wait for the AI to extract the job name, build number, and error type."

prompt

# ============================================================================
# Stage 2: Log Analysis
# ============================================================================

step "2" "Log Analysis — Provide Confluence known issues (if available)"

if [[ -f "${SCENARIO_DIR}/confluence-known-issue.md" ]]; then
    info "When Windsurf asks about Confluence/known issues, paste this:"
    show_file "${SCENARIO_DIR}/confluence-known-issue.md" "Confluence Known Issue"
elif [[ -f "${SCENARIO_DIR}/nexus-policy-report.json" ]]; then
    info "When Windsurf asks about dependency info, paste this:"
    show_file "${SCENARIO_DIR}/nexus-policy-report.json" "Nexus Policy Report"
else
    info "No Confluence data for this scenario. Type 'skip' when prompted."
fi

info "Wait for the AI to produce a structured diagnosis."
echo ""
info "Expected diagnosis:"
if [[ -f "${SCENARIO_DIR}/expected-diagnosis.json" ]]; then
    show_file "${SCENARIO_DIR}/expected-diagnosis.json" "Expected Diagnosis (for comparison)"
fi

prompt

# ============================================================================
# Stage 3: Patch Generation
# ============================================================================

step "3" "Patch Generation — Provide source files"

info "When Windsurf asks for source files, paste each file below:"
echo ""

if [[ -d "${SCENARIO_DIR}/source-files" ]]; then
    for src_file in "${SCENARIO_DIR}/source-files/"*; do
        show_file "${src_file}" "Source: $(basename "${src_file}")"
        prompt
    done
fi

info "Wait for the AI to generate a patch."
echo ""
info "Expected fix for comparison:"
if [[ -f "${SCENARIO_DIR}/expected-fix.diff" ]]; then
    show_file "${SCENARIO_DIR}/expected-fix.diff" "Expected Fix"
fi

prompt

# ============================================================================
# Stage 4: Validation
# ============================================================================

step "4" "Validation — Confirm the fix works"

info "When Windsurf asks you to validate, respond with:"
echo ""
case "${scenario_num}" in
    1) info "  'Build validated: mvn clean install — BUILD SUCCESS, 127 tests pass, 0 failures.'" ;;
    2) info "  'Tests pass: npm test — 50 tests, 50 passed, 0 failed.'" ;;
    3) info "  'Build validated: mvn clean install — BUILD SUCCESS, no Nexus policy violations.'" ;;
    4) info "  'Deployment validated: kubectl rollout status — deployment successfully rolled out.'" ;;
esac

prompt

# ============================================================================
# Stage 5: PR Creation
# ============================================================================

step "5" "PR Creation — Review the generated PR"

info "Choose option 3 (Manual copy-paste) when asked how to create the PR."
info "Compare the generated PR body against the expected structure:"
echo ""
info "Required PR sections:"
info "  - Root Cause"
info "  - Changes Made"
info "  - Files Modified"
info "  - Risk Assessment"
info "  - Validation"
info "  - Original Failure"

prompt

# ============================================================================
# Complete
# ============================================================================

header "Demo Complete!"

echo "  Evaluation checklist:"
echo ""
echo "    [ ] Detection:  Correct job, build number, error type"
echo "    [ ] Analysis:   Root cause accurately identified"
echo "    [ ] Patch:      Fix is correct and minimal"
echo "    [ ] Validation: Appropriate steps suggested"
echo "    [ ] PR:         All required sections present"
echo ""
echo "  To test retry logic, re-run and say 'build failed' at Step 4."
echo "  The AI should re-analyse and generate a revised patch."
echo ""

divider
