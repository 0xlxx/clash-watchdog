#!/usr/bin/env bash
# Clash Verge CPU watchdog — monitors verge-mihomo CPU and restarts if abnormal
set -euo pipefail

APP_NAME="Clash Verge"
PROCESS_NAME="verge-mihomo"
CPU_THRESHOLD=80          # trigger if CPU% > this
CONSECUTIVE_CHECKS=3      # must exceed threshold this many times in a row
CHECK_INTERVAL=10         # seconds between checks
LOG_FILE="$HOME/.local/var/log/clash-watchdog.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

restart_clash() {
    log "Restarting $APP_NAME..."
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    sleep 3
    # If verge-mihomo still alive, force-kill with sudo
    if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
        log "Process still alive after quit, trying sudo kill..."
        sudo kill "$(pgrep -x "$PROCESS_NAME")" 2>/dev/null || true
        sleep 2
    fi
    open -a "$APP_NAME" 2>/dev/null || true
    log "$APP_NAME relaunched."
}

count=0
log "Watchdog started. Monitoring $PROCESS_NAME — threshold: ${CPU_THRESHOLD}% × ${CONSECUTIVE_CHECKS} checks."

while true; do
    pid=$(pgrep -x "$PROCESS_NAME" 2>/dev/null || echo "")
    if [ -z "$pid" ]; then
        log "No $PROCESS_NAME process found. Starting $APP_NAME..."
        open -a "$APP_NAME" 2>/dev/null || true
        count=0
        sleep "$CHECK_INTERVAL"
        continue
    fi

    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
    cpu_int=$(printf "%.0f" "${cpu:-0}")

    if [ "${cpu_int:-0}" -gt "$CPU_THRESHOLD" ]; then
        count=$((count + 1))
        log "HIGH CPU: ${cpu}% — ${count}/${CONSECUTIVE_CHECKS}"
        if [ "$count" -ge "$CONSECUTIVE_CHECKS" ]; then
            log "Threshold exceeded for ${CONSECUTIVE_CHECKS} consecutive checks — restarting!"
            restart_clash
            count=0
        fi
    else
        count=0
    fi

    sleep "$CHECK_INTERVAL"
done
