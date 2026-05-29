# clash-watchdog

Auto-restart Clash Verge when the proxy core `verge-mihomo` goes rogue and burns CPU.

> macOS only. Requires [Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev).

## Install

```sh
./clash-watchdog.sh install
```

This copies the LaunchAgent plist and starts it. The watchdog runs on boot and keeps running.

## Usage

```sh
./clash-watchdog.sh start       # start
./clash-watchdog.sh stop        # stop
./clash-watchdog.sh status      # show status
./clash-watchdog.sh log         # tail the log
./clash-watchdog.sh test        # test mode (auto-stop, fast checks, simulated restart)
./clash-watchdog.sh uninstall   # remove LaunchAgent
```

## Why

Clash Verge's `verge-mihomo` sometimes spikes to 140%+ CPU and stays there — the proxy still works, so you won't notice until your Mac is on fire. This catches it and restarts automatically.

- **Check interval:** 10 seconds
- **CPU threshold:** 80%
- **Trigger:** 3 consecutive readings (30 seconds total)
- **Restart cooldown:** 3 restarts in 5 minutes → suppress to avoid restart loops

## Telegram notifications

```sh
mkdir -p ~/.config/clash-watchdog
cat > ~/.config/clash-watchdog/env << 'EOF'
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
EOF
chmod 600 ~/.config/clash-watchdog/env
```

Restart and cooldown events are pushed to you. If the file doesn't exist, notifications are silently skipped.

## Logs

```
[2026-05-29 08:30:01] Watchdog started. Monitoring verge-mihomo — threshold: 80% × 3 checks.
[2026-05-29 08:35:22] HIGH CPU: 142.4% — 1/3
[2026-05-29 08:35:32] HIGH CPU: 141.8% — 2/3
[2026-05-29 08:35:42] HIGH CPU: 143.1% — 3/3
[2026-05-29 08:35:42] Threshold exceeded for 3 consecutive checks — restarting!
[2026-05-29 08:35:45] Clash Verge relaunched.
```
