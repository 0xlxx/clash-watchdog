# CLAUDE.md

## Project

clash-watchdog — monitors `verge-mihomo` CPU usage and auto-restarts Clash Verge when it goes rogue.

- `clash-watchdog.sh` — bash watchdog (10s interval, 80% threshold, 3 consecutive checks)
- `com.bjorn.clash-watchdog.plist` — macOS LaunchAgent (paths hardcoded to `/Users/bjorn/`)

All operations go through the script — no need to remember launchctl commands.

## Commands

```sh
./clash-watchdog.sh start       # start monitoring
./clash-watchdog.sh stop        # stop running instance
./clash-watchdog.sh status      # show status
./clash-watchdog.sh restart     # stop then start
./clash-watchdog.sh install     # install as LaunchAgent (auto-start on boot)
./clash-watchdog.sh uninstall   # remove LaunchAgent
./clash-watchdog.sh log         # tail the log
./clash-watchdog.sh test        # test mode: auto-stop, 1% threshold, 2s interval, simulated restart
```

## Install

```sh
./clash-watchdog.sh install
```

## Telegram notifications

```sh
export TELEGRAM_BOT_TOKEN="..."
export TELEGRAM_CHAT_ID="..."
```

If unset, notifications are silently skipped. Restart and cooldown events are pushed.
