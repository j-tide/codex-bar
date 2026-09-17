# 通知提示清单

以下是 codex-bar 目前会发送到 macOS 通知中心的全部正式场景。任务名称、对话标题和内容不会写入通知。

| 场景 | 触发条件 | 标题 | 正文 | 点按后 |
| --- | --- | --- | --- | --- |
| 等待授权 | Codex 任务进入 `needs_attention`，阶段为 `awaiting_permission`，15 秒后仍在等待 | Codex 等待授权 | Codex 正在等待你批准操作，点按前往处理。 | 打开 Codex |
| 等待回复 | Codex 任务进入 `needs_attention`，阶段为 `waiting_input`，15 秒后仍在等待 | Codex 等待回复 | Codex 需要你的输入才能继续，点按前往回复。 | 打开 Codex |
| 其他待处理 | Codex 任务进入 `needs_attention`，但阶段未明确指向授权或输入，15 秒后仍在等待 | Codex 需要处理 | 任务需要你处理，点按前往 Codex。 | 打开 Codex |
| 任务完成 | 收到尚未提醒过的 `Stop` 完成事件 | Codex 任务已完成 | 任务已完成，点按查看结果。 | 打开 Codex |
| 发现新版本 | GitHub 发布比当前版本更新的可安装版本 | codex-bar 有新版本 | `<版本>` 已发布，点按打开菜单并安装。 | 打开 codex-bar 菜单 |
| 更新完成 | 应用重启后确认安装成功 | codex-bar 更新完成 | 已升级至 `<版本>`。 | 打开 codex-bar 菜单 |

开发版的 `--notification-status --test-task-notification` 额外发送一条手动诊断通知，标题为“codex-bar 通知测试”，正文为“看到绿色图标即表示新通知通道生效。”，点按打开 codex-bar 菜单。

运行中、恢复、打断和结束事件不会作为“任务完成”通知。任务提醒须由用户开启通知并获得 macOS 权限；尚未授权或系统拒绝时不会将事件记为已发送。更新提醒仅在通知中心接受后才记为已提醒，同一版本不重复提醒。更新完成提示只对应当前正在运行的构建；升级到更高版本后，旧的完成记录会自动清理。

通知由内置的独立标识 `xmasdong.codexAppBar.notifications` 发送，以使用当前绿色应用图标；主应用标识 `xmasdong.codexAppBar` 不变。升级前已开启任务通知的用户会收到一次新标识的系统授权请求。若 macOS 通知设置中出现两个同名条目，应允许绿色图标的 codex-bar。
