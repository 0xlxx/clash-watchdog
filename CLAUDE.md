# CLAUDE.md

## Project

clash-watchdog — monitors `verge-mihomo` CPU usage and auto-restarts Clash Verge when it goes rogue.

- `clash-watchdog.sh` — bash watchdog script (10s interval, 80% threshold, 3 consecutive checks)
- `com.bjorn.clash-watchdog.plist` — macOS LaunchAgent for auto-start on boot
- Logs to `~/.local/var/log/clash-watchdog.log`

## Commands

```sh
launchctl start com.bjorn.clash-watchdog
launchctl stop com.bjorn.clash-watchdog
launchctl unload ~/Library/LaunchAgents/com.bjorn.clash-watchdog.plist
tail -f ~/.local/var/log/clash-watchdog.log
```
