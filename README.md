# clash-watchdog

Clash Verge CPU 异常自动重启守护进程。

## 背景

Clash Verge 的代理核心进程 `verge-mihomo` 会以 root 权限运行。在特定条件下（可能是规则匹配死循环、内存泄漏、或长时间运行后的状态退化），该进程 CPU 会飙升至 140%+ 并持续不降，导致 Mac 严重发热、电池快速耗尽。

这个问题具有隐蔽性——代理仍然正常工作，网络没有任何异常表现，用户难以察觉是 Clash Verge 在后台烧 CPU。只有在 Mac 风扇狂转、外壳烫手时才会发现。

本 watchdog 持续监控 `verge-mihomo` 的 CPU 占用，一旦连续超标即自动重启 Clash Verge，无需人工干预。

## 安装

```sh
# 安装 LaunchAgent 到 ~/Library/LaunchAgents/
cp com.bjorn.clash-watchdog.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.bjorn.clash-watchdog.plist
```

## 卸载

```sh
launchctl unload ~/Library/LaunchAgents/com.bjorn.clash-watchdog.plist
rm ~/Library/LaunchAgents/com.bjorn.clash-watchdog.plist
```

## 工作逻辑

| 参数 | 值 |
|------|-----|
| 检测间隔 | 10 秒 |
| CPU 阈值 | 80% |
| 连续超标次数 | 3 次（共 30 秒） |
| 重启方式 | osascript 优雅退出 → 强制 kill → relaunch |

## 管理

```sh
# 查看日志
tail -f ~/.local/var/log/clash-watchdog.log

# 停止
launchctl stop com.bjorn.clash-watchdog

# 启动
launchctl start com.bjorn.clash-watchdog
```

## 日志示例

```
[2026-05-29 08:30:01] Watchdog started. Monitoring verge-mihomo — threshold: 80% × 3 checks.
[2026-05-29 08:35:22] HIGH CPU: 142.4% — 1/3
[2026-05-29 08:35:32] HIGH CPU: 141.8% — 2/3
[2026-05-29 08:35:42] HIGH CPU: 143.1% — 3/3
[2026-05-29 08:35:42] Threshold exceeded for 3 consecutive checks — restarting!
[2026-05-29 08:35:45] Clash Verge relaunched.
```
