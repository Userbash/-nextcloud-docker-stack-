#!/usr/bin/env bash
# scripts/run-ci-local.sh
# Fully automated local CI runner using 'act'.
# No user input required.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACT_CMD="act"
PODMAN_SOCKET=""
ACT_EXTRA_ARGS=()
CONTAINER_CLI=""
REPORT_DIR=""
RUN_TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG=""

# Prints a single-line script header.
print_header() {
    echo -e "${BLUE}=== Automated Local CI Pipeline ===${NC}"
}

# Prints an informational line with timestamp.
log_info() {
    echo "[$(date +'%H:%M:%S')] $*"
}

# Ensures 'act' is present. If missing, installs it into ~/.local/bin.
ensure_act_installed() {
    if command -v act >/dev/null 2>&1; then
        ACT_CMD="act"
        return
    fi

    if [ -x "$HOME/.local/bin/act" ]; then
        ACT_CMD="$HOME/.local/bin/act"
        return
    fi

    echo -e "${BLUE}[*] 'act' not found. Installing locally...${NC}"
    mkdir -p "$HOME/.local/bin"

    # Install using official installer script.
    python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/nektos/act/master/install.sh', '/tmp/install_act.sh')"
    bash /tmp/install_act.sh -b "$HOME/.local/bin" >/dev/null 2>&1
    rm -f /tmp/install_act.sh

    ACT_CMD="$HOME/.local/bin/act"
    echo -e "${GREEN}[+] 'act' successfully installed.${NC}"
}

# Chooses the available container CLI.
detect_container_cli() {
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_CLI="podman"
        return
    fi

    if command -v docker >/dev/null 2>&1; then
        CONTAINER_CLI="docker"
        return
    fi

    if [ -n "$PODMAN_SOCKET" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        CONTAINER_CLI="api"
        return
    fi

    CONTAINER_CLI=""
}

# Calls the Docker-compatible API through the local Podman socket.
api_get() {
    local path="$1"
    curl --silent --show-error --unix-socket "$PODMAN_SOCKET" "http://d/v1.40${path}"
}

# Tries to ensure at least one container engine socket is available.
ensure_engine_socket() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] systemctl not found, skipping socket status check.${NC}"
        return
    fi

    if systemctl --user is-active --quiet podman.socket 2>/dev/null; then
        return
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        return
    fi

    echo -e "${YELLOW}[!] WARNING: No container engine socket detected (Docker or Podman).${NC}"
    echo -e "    Attempting to start user podman socket..."
    systemctl --user start podman.socket || echo -e "${YELLOW}    Could not start systemd socket, ignoring...${NC}"
}

# Detects the best local Podman socket path for rootless mode.
detect_podman_socket() {
    local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local candidate="${runtime_dir}/podman/podman.sock"

    if [ -S "$candidate" ]; then
        PODMAN_SOCKET="$candidate"
        return
    fi

    # Fallback used by some rootless setups.
    candidate="/run/user/$(id -u)/podman/podman.sock"
    if [ -S "$candidate" ]; then
        PODMAN_SOCKET="$candidate"
    fi
}

# Configures act to talk directly to local Podman daemon socket.
configure_act_for_podman() {
    detect_podman_socket

    if [ -z "$PODMAN_SOCKET" ]; then
        echo -e "${YELLOW}[!] Podman socket not detected; act will use its default engine settings.${NC}"
        return
    fi

    export DOCKER_HOST="unix://${PODMAN_SOCKET}"
    export ACT_DOCKER_HOST="unix://${PODMAN_SOCKET}"
    ACT_EXTRA_ARGS+=(--container-daemon-socket "unix://${PODMAN_SOCKET}")
    echo -e "${BLUE}[*] Using local Podman socket: ${PODMAN_SOCKET}${NC}"
}

# Runs the lint job from GitHub Actions via act.
run_lint_job() {
    echo -e "\n${BLUE}[*] Running GitHub Action: lint${NC}"
    "$ACT_CMD" -j lint --bind --container-architecture linux/amd64 "${ACT_EXTRA_ARGS[@]}"
}

# Writes a compact status report for all containers.
report_container_health() {
    if [ -z "$CONTAINER_CLI" ]; then
        log_info "Container CLI not found; skipping container health checks."
        return
    fi

    echo -e "\n${BLUE}[*] Container Health Summary (${CONTAINER_CLI})${NC}"

    if [ "$CONTAINER_CLI" = "api" ]; then
        api_get '/containers/json?all=1' | jq -r '
            ("NAME\tIMAGE\tSTATE\tSTATUS\tPORTS"),
            (.[] | [(.Names[0] // "" | ltrimstr("/")), .Image, .State, .Status, ((.Ports // []) | map((.PublicPort // "")|tostring + ":" + ((.PrivatePort // "")|tostring)) | join(","))] | @tsv)
        '
        return
    fi

    "$CONTAINER_CLI" ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
}

# Checks whether Portainer is running and reachable by container status.
check_portainer() {
    if [ -z "$CONTAINER_CLI" ]; then
        return
    fi

    echo -e "\n${BLUE}[*] Portainer Check${NC}"

    local state
    local health

    if [ "$CONTAINER_CLI" = "api" ]; then
        local portainer_json
        portainer_json=$(api_get '/containers/json?all=1' | jq -c '.[] | select((.Names // []) | any(. == "/portainer" or . == "/nextcloud-portainer"))' | head -1)
        if [ -z "$portainer_json" ]; then
            echo -e "${YELLOW}[!] Portainer container not found${NC}"
            return
        fi

        state=$(echo "$portainer_json" | jq -r '.State // "unknown"')
        health="n/a"
        if [ "$state" = "running" ]; then
            echo -e "${GREEN}[+] Portainer is running (health: ${health})${NC}"
        else
            echo -e "${YELLOW}[!] Portainer state: ${state} (health: ${health})${NC}"
        fi

        echo "$portainer_json" | jq -r '.Ports[]? | "  - " + ((.PublicPort // 0)|tostring) + " -> " + ((.PrivatePort // 0)|tostring) + "/" + (.Type // "")'
        return
    fi

    if ! "$CONTAINER_CLI" inspect portainer >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Portainer container not found${NC}"
        return
    fi

    state=$("$CONTAINER_CLI" inspect --format '{{.State.Status}}' portainer 2>/dev/null || echo "unknown")
    health=$("$CONTAINER_CLI" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' portainer 2>/dev/null || echo "unknown")

    if [ "$state" = "running" ]; then
        echo -e "${GREEN}[+] Portainer is running (health: ${health})${NC}"
    else
        echo -e "${YELLOW}[!] Portainer state: ${state} (health: ${health})${NC}"
    fi

    "$CONTAINER_CLI" port portainer 2>/dev/null || true
}

# Prints currently open listening ports.
check_open_ports() {
    echo -e "\n${BLUE}[*] Open Listening Ports${NC}"

    if command -v ss >/dev/null 2>&1; then
        ss -tuln | sed -n '1,120p'
        return
    fi

    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | sed -n '1,120p'
        return
    fi

    echo -e "${YELLOW}[!] Neither ss nor netstat is available${NC}"
}

# Saves logs for each running container into a timestamped report directory.
collect_container_logs() {
    if [ -z "$CONTAINER_CLI" ]; then
        return
    fi

    mkdir -p "$REPORT_DIR/container-logs"
    echo -e "\n${BLUE}[*] Collecting Container Logs${NC}"

    local names
    if [ "$CONTAINER_CLI" = "api" ]; then
        names=$(api_get '/containers/json?all=1' | jq -r '.[].Names[0] | ltrimstr("/")' || true)
    else
        names=$("$CONTAINER_CLI" ps -a --format '{{.Names}}' 2>/dev/null || true)
    fi

    if [ -z "$names" ]; then
        echo -e "${YELLOW}[!] No containers found to collect logs from${NC}"
        return
    fi

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local out_file="$REPORT_DIR/container-logs/${name}.log"
        echo "  - $name -> $out_file"
        if [ "$CONTAINER_CLI" = "api" ]; then
            local id
            id=$(api_get '/containers/json?all=1' | jq -r --arg n "$name" '.[] | select((.Names[0] // "" | ltrimstr("/")) == $n) | .Id' | head -1)
            if [ -n "$id" ]; then
                api_get "/containers/${id}/logs?stdout=1&stderr=1&timestamps=1&tail=1000" > "$out_file" 2>&1 || true
            fi
        else
            "$CONTAINER_CLI" logs "$name" > "$out_file" 2>&1 || true
        fi
    done <<EOF
$names
EOF
}

# Prepares reporting directory and enables full stdout/stderr logging to file.
init_logging() {
    REPORT_DIR="test-reports/ci-local-${RUN_TS}"
    mkdir -p "$REPORT_DIR"
    RUN_LOG="$REPORT_DIR/run.log"

    # Mirror all script output to file while keeping stdout visible.
    exec > >(tee -a "$RUN_LOG") 2>&1
    log_info "Log file: $RUN_LOG"
}

# Entry point for local CI execution.
main() {
    init_logging
    print_header
    ensure_act_installed
    ensure_engine_socket
    configure_act_for_podman
    detect_container_cli

    log_info "Container CLI: ${CONTAINER_CLI:-not found}"
    run_lint_job

    report_container_health
    check_portainer
    check_open_ports
    collect_container_logs

    log_info "Artifacts directory: $REPORT_DIR"
    echo -e "\n${GREEN}=== Local CI Completed Successfully ===${NC}"
}

main "$@"