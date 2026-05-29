#!/usr/bin/env bash
# Clash Verge CPU watchdog — monitors verge-mihomo CPU and restarts if abnormal
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Clash Verge"
PROCESS_NAME="verge-mihomo"
TEST_MODE=false
CPU_THRESHOLD=80
CONSECUTIVE_CHECKS=3
CHECK_INTERVAL=10
LOG_FILE="$HOME/.local/var/log/clash-watchdog.log"
PID_FILE="$HOME/.local/var/run/clash-watchdog.pid"
COOLDOWN_FILE="$HOME/.local/var/run/clash-watchdog.cooldown"
COOLDOWN_WINDOW=300
COOLDOWN_MAX_RESTARTS=3
PLIST_NAME="com.bjorn.clash-watchdog.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"
LAUNCHD_LABEL="com.bjorn.clash-watchdog"
LAUNCHD_DOMAIN="gui/$(id -u)"
ENV_FILE="$HOME/.config/clash-watchdog/env"

# Source local secrets if present (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID)
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$PID_FILE")" "$(dirname "$ENV_FILE")"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2; }

notify() {
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" -d "text=$*" >/dev/null 2>&1 || true
    fi
}

# ── daemon helpers ──

is_launchd_loaded() {
    launchctl list "$LAUNCHD_LABEL" &>/dev/null
}

is_launchd_installed() {
    [[ -f "$PLIST_DST" ]]
}

acquire_lock() {
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            warn "Already running (PID $old_pid)."
            exit 1
        fi
        log "Removing stale PID file (PID $old_pid)."
        rm -f "$PID_FILE"
    fi
    echo $$ > "$PID_FILE"
}

release_lock() {
    rm -f "$PID_FILE"
    log "Watchdog stopped."
}

# ── cooldown ──

check_cooldown() {
    local now recent=0
    now=$(date +%s)
    if [[ -f "$COOLDOWN_FILE" ]]; then
        while read -r ts; do
            [[ -z "$ts" ]] && continue
            (( now - ts < COOLDOWN_WINDOW )) && (( recent++ )) || true
        done < "$COOLDOWN_FILE"
    fi
    if (( recent >= COOLDOWN_MAX_RESTARTS )); then
        log "Cooldown: ${recent} restarts in last $((COOLDOWN_WINDOW/60))min — skipping."
        notify "[clash-watchdog] Cooldown: ${recent} restarts in last $((COOLDOWN_WINDOW/60))min — skipping restart."
        return 1
    fi
    return 0
}

record_restart() {
    date +%s >> "$COOLDOWN_FILE"
    local cutoff tmp
    cutoff=$(( $(date +%s) - COOLDOWN_WINDOW * 2 ))
    tmp=$(mktemp)
    if [[ -f "$COOLDOWN_FILE" ]]; then
        while read -r ts; do
            [[ -z "$ts" ]] && continue
            (( ts > cutoff )) && echo "$ts" || true
        done < "$COOLDOWN_FILE" > "$tmp"
        mv "$tmp" "$COOLDOWN_FILE"
    fi
}

# ── actions ──

restart_clash() {
    if $TEST_MODE; then
        log "[test] Would restart $APP_NAME (simulated)"
        notify "[clash-watchdog] [test] Would restart $APP_NAME (simulated)"
        return
    fi
    check_cooldown || return
    log "Restarting $APP_NAME..."
    notify "[clash-watchdog] Restarting $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 3
    if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
        log "Process still alive after quit, trying sudo kill..."
        sudo kill "$(pgrep -x "$PROCESS_NAME")" 2>/dev/null || true
        sleep 2
    fi
    open -a "$APP_NAME" 2>/dev/null || true
    record_restart
    log "$APP_NAME relaunched."
    notify "[clash-watchdog] $APP_NAME relaunched."
}

start_clash() {
    if $TEST_MODE; then
        log "[test] Would start $APP_NAME (simulated)"
        return
    fi
    open -a "$APP_NAME" 2>/dev/null || true
}

# ── main loop ──

run_loop() {
    acquire_lock
    trap release_lock INT TERM EXIT

    local count=0
    log "Watchdog started. Monitoring $PROCESS_NAME — threshold: ${CPU_THRESHOLD}% × ${CONSECUTIVE_CHECKS} checks."

    while true; do
        local pid cpu cpu_int
        pid=$(pgrep -x "$PROCESS_NAME" 2>/dev/null || echo "")
        if [[ -z "$pid" ]]; then
            log "No $PROCESS_NAME process found. Starting $APP_NAME..."
            start_clash
            count=0
            sleep "$CHECK_INTERVAL"
            continue
        fi

        cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
        cpu_int=$(printf "%.0f" "${cpu:-0}")

        if (( cpu_int > CPU_THRESHOLD )); then
            count=$((count + 1))
            log "HIGH CPU: ${cpu}% — ${count}/${CONSECUTIVE_CHECKS}"
            if (( count >= CONSECUTIVE_CHECKS )); then
                log "Threshold exceeded for ${CONSECUTIVE_CHECKS} consecutive checks — restarting!"
                restart_clash
                count=0
            fi
        else
            count=0
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# ── commands ──

cmd_daemon() {
    # Internal: called by launchd, just runs the loop
    run_loop
}

cmd_start() {
    if is_launchd_installed; then
        if is_launchd_loaded; then
            echo "Already running via LaunchAgent."
        else
            launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST_DST"
            echo "Started via LaunchAgent."
        fi
    else
        run_loop
    fi
}

cmd_stop() {
    if is_launchd_loaded; then
        launchctl bootout "$LAUNCHD_DOMAIN/$LAUNCHD_LABEL"
        echo "Stopped LaunchAgent."
    elif [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "Stopped (PID $pid)."
        else
            rm -f "$PID_FILE"
            echo "Not running (stale PID removed)."
        fi
    else
        echo "Not running."
    fi
}

cmd_status() {
    echo "Label:    $LAUNCHD_LABEL"
    echo "Log:      $LOG_FILE"

    # Check launchd
    if is_launchd_installed; then
        echo "LaunchAgent: installed"
        if is_launchd_loaded; then
            local pids
            pids=$(pgrep -f "clash-watchdog.sh.*daemon" 2>/dev/null || echo "")
            if [[ -n "$pids" ]]; then
                echo "  Status:  running (PID $(echo "$pids" | xargs))"
            else
                echo "  Status:  loaded (waiting for launchd)"
            fi
        else
            echo "  Status:  not loaded"
        fi
    else
        echo "LaunchAgent: not installed"
    fi

    # Check standalone (only if not managed by launchd)
    if ! is_launchd_loaded && [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Standalone:  running (PID $pid)"
        else
            echo "Standalone:  stopped (stale PID)"
        fi
    fi
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_install() {
    if is_launchd_installed; then
        echo "Already installed."
        return
    fi
    local src="$SCRIPT_DIR/$PLIST_NAME"
    if [[ ! -f "$src" ]]; then
        echo "Plist not found: $src" >&2
        exit 1
    fi
    cp "$src" "$PLIST_DST"
    launchctl bootstrap "$LAUNCHD_DOMAIN" "$PLIST_DST"
    echo "Installed and started."
}

cmd_uninstall() {
    if is_launchd_loaded; then
        launchctl bootout "$LAUNCHD_DOMAIN/$LAUNCHD_LABEL" 2>/dev/null || true
    fi
    if [[ -f "$PLIST_DST" ]]; then
        rm -f "$PLIST_DST"
        echo "Uninstalled."
    else
        echo "Was not installed."
    fi
}

cmd_log() {
    tail -f "$LOG_FILE"
}

cmd_test() {
    cmd_stop
    sleep 1

    TEST_MODE=true
    CPU_THRESHOLD=1
    CHECK_INTERVAL=2
    log "[test] CPU threshold lowered to ${CPU_THRESHOLD}%, interval set to ${CHECK_INTERVAL}s. Will simulate restart."
    echo "Running in test mode. Ctrl-C to stop."
    run_loop

    echo ""
    echo "Test finished. Restart with: $(basename "$0") start"
}

cmd_help() {
    echo "Usage: $(basename "$0") <command>"
    echo ""
    echo "  start      Start monitoring (via LaunchAgent if installed, else foreground)"
    echo "  stop       Stop running instance"
    echo "  status     Show status"
    echo "  restart    Stop then start"
    echo "  install    Install as LaunchAgent (auto-start on boot)"
    echo "  uninstall  Remove LaunchAgent"
    echo "  log        Tail the log file"
    echo "  test       Run in test mode (low threshold, fast interval, simulated restart)"
    echo "  help       Show this help"
}

# ── dispatch ──

case "${1:-help}" in
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    status)    cmd_status ;;
    restart)   cmd_restart ;;
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    log)       cmd_log ;;
    test)      cmd_test ;;
    daemon)    cmd_daemon ;;
    help|--help|-h) cmd_help ;;
    *)         echo "Unknown command: ${1:-}"; echo ""; cmd_help; exit 1 ;;
esac
