#!/usr/bin/env bash
###############################################################################
# validate-fix.sh
#
# Validates AI-generated fixes locally by checking out the fix branch,
# detecting the project build tool, running the build and tests, and
# reporting a clear pass/fail summary.
#
# Usage:
#   validate-fix.sh <branch-name> [--no-checkout] [--project-dir <dir>]
#
# Options:
#   <branch-name>        Required. The git branch containing the fix to validate.
#   --no-checkout        Skip branch checkout (assume already on the correct branch).
#   --project-dir <dir>  Run validation in the specified directory instead of cwd.
#
# Exit codes:
#   0  All validations passed (build + tests).
#   1  One or more validations failed, or a runtime error occurred.
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
BRANCH_NAME=""
NO_CHECKOUT=false
PROJECT_DIR=""
ORIGINAL_BRANCH=""
DID_STASH=false
DID_CHECKOUT=false

BUILD_TOOL=""
BUILD_CMD=""
TEST_CMD=""

BUILD_EXIT_CODE=1
TEST_EXIT_CODE=1
BUILD_OUTPUT_FILE=""
TEST_OUTPUT_FILE=""

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info() {
    printf "[INFO]  %s\n" "$1"
}

log_warn() {
    printf "[WARN]  %s\n" "$1" >&2
}

log_error() {
    printf "[ERROR] %s\n" "$1" >&2
}

log_section() {
    printf "\n"
    printf "========================================\n"
    printf "  %s\n" "$1"
    printf "========================================\n"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <branch-name> [--no-checkout] [--project-dir <dir>]

Validate an AI-generated fix by building and testing the specified branch.

Arguments:
  <branch-name>        The git branch containing the fix (required).

Options:
  --no-checkout        Do not checkout the branch; assume the working tree is
                       already on the correct branch.
  --project-dir <dir>  Path to the project directory. Defaults to the current
                       working directory.
  -h, --help           Show this help message and exit.

Exit codes:
  0  Build and tests both passed.
  1  Build or tests failed, or a runtime error occurred.
EOF
    exit 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        log_error "No arguments provided."
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            --no-checkout)
                NO_CHECKOUT=true
                shift
                ;;
            --project-dir)
                if [[ -z "${2:-}" ]]; then
                    log_error "--project-dir requires a directory argument."
                    usage
                fi
                PROJECT_DIR="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                if [[ -z "$BRANCH_NAME" ]]; then
                    BRANCH_NAME="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$BRANCH_NAME" ]]; then
        log_error "Branch name is required."
        usage
    fi
}

# ---------------------------------------------------------------------------
# Change to project directory
# ---------------------------------------------------------------------------
enter_project_dir() {
    if [[ -n "$PROJECT_DIR" ]]; then
        if [[ ! -d "$PROJECT_DIR" ]]; then
            log_error "Project directory does not exist: $PROJECT_DIR"
            exit 1
        fi
        log_info "Changing to project directory: $PROJECT_DIR"
        cd "$PROJECT_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Verify git repository
# ---------------------------------------------------------------------------
verify_git_repo() {
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        log_error "Current directory is not inside a git repository."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Checkout branch (with stash if needed)
# ---------------------------------------------------------------------------
checkout_branch() {
    if [[ "$NO_CHECKOUT" == true ]]; then
        log_info "Skipping branch checkout (--no-checkout specified)."
        log_info "Current branch: $(git branch --show-current 2>/dev/null || echo 'detached HEAD')"
        return 0
    fi

    ORIGINAL_BRANCH="$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD)"
    log_info "Current branch: $ORIGINAL_BRANCH"

    # Check if the target branch exists locally or in remotes.
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
        # Try fetching from remote.
        log_info "Branch '$BRANCH_NAME' not found locally. Fetching from remote..."
        if ! git fetch origin "$BRANCH_NAME" 2>/dev/null; then
            log_error "Branch '$BRANCH_NAME' does not exist locally or on remote."
            exit 1
        fi
    fi

    # Stash uncommitted changes if the working tree is dirty.
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        log_info "Working tree has uncommitted changes. Stashing..."
        git stash push -m "validate-fix: auto-stash before checkout" --include-untracked
        DID_STASH=true
        log_info "Changes stashed successfully."
    fi

    log_info "Checking out branch: $BRANCH_NAME"
    if ! git checkout "$BRANCH_NAME" 2>/dev/null; then
        log_error "Failed to checkout branch '$BRANCH_NAME'."
        restore_stash
        exit 1
    fi
    DID_CHECKOUT=true
    log_info "Now on branch: $(git branch --show-current 2>/dev/null || echo 'detached HEAD')"
}

# ---------------------------------------------------------------------------
# Detect build tool
# ---------------------------------------------------------------------------
detect_build_tool() {
    log_section "Detecting Build Tool"

    if [[ -f "pom.xml" ]]; then
        BUILD_TOOL="Maven"
        if [[ -x "./mvnw" ]]; then
            BUILD_CMD="./mvnw clean compile -B"
            TEST_CMD="./mvnw test -B"
            log_info "Detected Maven project (using Maven wrapper: ./mvnw)."
        else
            BUILD_CMD="mvn clean compile -B"
            TEST_CMD="mvn test -B"
            log_info "Detected Maven project (using system mvn)."
        fi
    elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
        BUILD_TOOL="Gradle"
        if [[ -x "./gradlew" ]]; then
            BUILD_CMD="./gradlew clean build"
            TEST_CMD="./gradlew test"
            log_info "Detected Gradle project (using Gradle wrapper: ./gradlew)."
        else
            BUILD_CMD="gradle clean build"
            TEST_CMD="gradle test"
            log_info "Detected Gradle project (using system gradle)."
        fi
    elif [[ -f "package.json" ]]; then
        BUILD_TOOL="npm"
        BUILD_CMD="npm ci && npm run build"
        TEST_CMD="npm test"
        log_info "Detected Node.js project (using npm)."
    elif [[ -f "Makefile" ]]; then
        BUILD_TOOL="Make"
        BUILD_CMD="make all"
        TEST_CMD="make test"
        log_info "Detected Makefile-based project."
    else
        log_error "No supported build tool detected."
        log_error "Looked for: pom.xml, build.gradle, build.gradle.kts, package.json, Makefile"
        cleanup
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Run build
# ---------------------------------------------------------------------------
run_build() {
    log_section "Running Build"
    log_info "Build tool: $BUILD_TOOL"
    log_info "Build command: $BUILD_CMD"

    BUILD_OUTPUT_FILE="$(mktemp)"

    set +e
    eval "$BUILD_CMD" > "$BUILD_OUTPUT_FILE" 2>&1
    BUILD_EXIT_CODE=$?
    set -e

    if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
        log_info "Build completed successfully."
    else
        log_error "Build failed with exit code $BUILD_EXIT_CODE."
    fi
}

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
run_tests() {
    log_section "Running Tests"

    # Only run tests if the build succeeded.
    if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
        log_warn "Skipping tests because the build failed."
        TEST_EXIT_CODE=1
        return
    fi

    log_info "Test command: $TEST_CMD"

    TEST_OUTPUT_FILE="$(mktemp)"

    set +e
    eval "$TEST_CMD" > "$TEST_OUTPUT_FILE" 2>&1
    TEST_EXIT_CODE=$?
    set -e

    if [[ $TEST_EXIT_CODE -eq 0 ]]; then
        log_info "Tests completed successfully."
    else
        log_error "Tests failed with exit code $TEST_EXIT_CODE."
    fi
}

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
report_results() {
    log_section "Validation Results"

    local build_status="FAIL"
    local test_status="FAIL"
    local overall_status="FAIL"

    if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
        build_status="PASS"
    fi

    if [[ $TEST_EXIT_CODE -eq 0 ]]; then
        test_status="PASS"
    fi

    if [[ $BUILD_EXIT_CODE -eq 0 && $TEST_EXIT_CODE -eq 0 ]]; then
        overall_status="PASS"
    fi

    printf "  %-20s %s\n" "Build Tool:" "$BUILD_TOOL"
    printf "  %-20s %s\n" "Branch:" "$BRANCH_NAME"
    printf "  %-20s %s\n" "Build Result:" "$build_status"
    printf "  %-20s %s\n" "Test Result:" "$test_status"
    printf "\n"
    printf "  %-20s %s\n" "Overall Result:" "$overall_status"
    printf "\n"

    # Show tail of output on failure for debugging.
    if [[ "$build_status" == "FAIL" && -n "$BUILD_OUTPUT_FILE" && -f "$BUILD_OUTPUT_FILE" ]]; then
        printf "  --- Last 20 lines of build output ---\n"
        tail -n 20 "$BUILD_OUTPUT_FILE" | sed 's/^/    /'
        printf "  --- End of build output ---\n"
        printf "\n"
        log_info "Full build output: $BUILD_OUTPUT_FILE"
    fi

    if [[ "$test_status" == "FAIL" && -n "$TEST_OUTPUT_FILE" && -f "$TEST_OUTPUT_FILE" ]]; then
        printf "  --- Last 20 lines of test output ---\n"
        tail -n 20 "$TEST_OUTPUT_FILE" | sed 's/^/    /'
        printf "  --- End of test output ---\n"
        printf "\n"
        log_info "Full test output: $TEST_OUTPUT_FILE"
    fi

    # Clean up temp files on success (keep them on failure for inspection).
    if [[ "$overall_status" == "PASS" ]]; then
        [[ -n "$BUILD_OUTPUT_FILE" && -f "$BUILD_OUTPUT_FILE" ]] && rm -f "$BUILD_OUTPUT_FILE"
        [[ -n "$TEST_OUTPUT_FILE" && -f "$TEST_OUTPUT_FILE" ]] && rm -f "$TEST_OUTPUT_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Stash restore helper
# ---------------------------------------------------------------------------
restore_stash() {
    if [[ "$DID_STASH" == true ]]; then
        log_info "Restoring stashed changes..."
        if git stash pop 2>/dev/null; then
            log_info "Stash restored successfully."
        else
            log_warn "Failed to restore stash automatically. Your changes are still in the stash."
            log_warn "Run 'git stash list' to find them and 'git stash pop' to restore manually."
        fi
        DID_STASH=false
    fi
}

# ---------------------------------------------------------------------------
# Cleanup: restore previous branch and stash
# ---------------------------------------------------------------------------
cleanup() {
    log_section "Cleanup"

    if [[ "$DID_CHECKOUT" == true && -n "$ORIGINAL_BRANCH" ]]; then
        log_info "Returning to original branch: $ORIGINAL_BRANCH"
        if git checkout "$ORIGINAL_BRANCH" 2>/dev/null; then
            log_info "Restored to branch: $ORIGINAL_BRANCH"
            DID_CHECKOUT=false
        else
            log_warn "Could not return to original branch '$ORIGINAL_BRANCH'."
            log_warn "You are still on branch '$BRANCH_NAME'. Switch back manually with:"
            log_warn "  git checkout $ORIGINAL_BRANCH"
        fi
    fi

    restore_stash

    log_info "Cleanup complete."
}

# ---------------------------------------------------------------------------
# Trap handler for unexpected exits
# ---------------------------------------------------------------------------
on_exit() {
    local exit_code=$?
    if [[ "$DID_CHECKOUT" == true || "$DID_STASH" == true ]]; then
        log_warn "Script interrupted or encountered an error. Running cleanup..."
        cleanup
    fi
    exit "$exit_code"
}

trap on_exit EXIT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_section "Validate AI-Generated Fix"

    parse_arguments "$@"
    enter_project_dir
    verify_git_repo
    checkout_branch
    detect_build_tool
    run_build
    run_tests
    report_results

    # Disable the EXIT trap cleanup since we will handle it explicitly.
    trap - EXIT
    cleanup

    # Determine final exit code.
    if [[ $BUILD_EXIT_CODE -eq 0 && $TEST_EXIT_CODE -eq 0 ]]; then
        log_info "Validation PASSED. The fix on branch '$BRANCH_NAME' builds and tests successfully."
        exit 0
    else
        log_error "Validation FAILED. Review the output above for details."
        exit 1
    fi
}

main "$@"
