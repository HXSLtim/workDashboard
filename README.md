# workDashboard

个人工作中枢：把 GitHub + AI 用量聚合到一处，最终显示在 macOS 刘海（模拟灵动岛）。

## 架构

```
NotchApp (Swift/SwiftUI, NSPanel 贴刘海)   ← 前端，只读 state.json
        ↑ 读
~/.workhub/state.json                       ← 统一数据契约
        ↑ 写
hub-daemon (Node/TS)                         ← 后端，定时聚合
   ├─ sources/github.ts   gh api graphql + /notifications
   ├─ sources/ai.ts       Anthropic 账单 + 其他平台 (Phase 2)
   └─ sources/inbox.ts    (并入 github notifications)
```

前后端通过 `~/.workhub/state.json` 解耦：后端原子写，前端只读。
数据契约定义在 `daemon/src/types.ts`，Swift 侧用 Codable 镜像同样结构。

## 进度

- [x] **Phase 1** hub-daemon 骨架 + GitHub 模块（profile 头像 / 贡献热力图 / PR / review / CI / 通知）
- [x] **Phase 2** 本地用量（订阅用户）：Claude Code（`~/.claude`）+ Codex（`~/.codex`）token 聚合
- [x] **Phase 3** inbox 去重折叠（同 仓库+类型+标题 折叠为一条带计数，取前 15）
- [x] **Phase 4** Swift 灵动岛 app（DynamicNotchKit，横版面板：头像+热力图 / Claude / Codex / 待办）
- [x] **待办** macOS 提醒事项，app 内用 EventKit 直读（不走 daemon），需授权一次
- [x] **翻页** 展开面板两页（GitHub+待办 / Claude+Codex），触控板两指横滑 + 箭头/圆点
- [x] **交互** 点 GitHub 头像/统计开网页、待办点圈勾完成、点标题开提醒事项、右键菜单（刷新/退出）
- [x] **CI 实时活动** 紧凑区跑 CI 时脉冲指示；新失败时刘海短暂自动展开提醒
- [x] **健康指示** 某 source 挂了面板底部红点提示
- [x] **开机自启** `install.sh` 装 LaunchAgent，daemon+app 登录自启；用量扫描按 mtime 增量缓存
- [ ] **Phase 4** Swift NotchApp：贴刘海 + 读 JSON + 收起/展开
- [ ] **Phase 5** 实时活动动画、预算预警、点击跳转

## 安装（开机自启）

```bash
./install.sh     # 编译 app、装到 /Applications、装 LaunchAgent、立即启动
./uninstall.sh   # 卸载（保留 ~/.workhub 数据）
```

装完 daemon + 灵动岛 app 登录自启。首次会弹"提醒事项"授权，点允许。
退出/刷新：右键刘海面板。日志：`~/.workhub/daemon.log`。

前提：`gh` CLI 已登录、Node ≥ 22.18、Xcode/CLT 可编译 Swift。

## 单独跑后端（调试）

```bash
cd daemon
npm run once    # 拉一次，打印结果，写 state.json
npm start       # 每 60s 轮询
```

认证交给 gh（daemon 不碰 token）。

可选环境变量：`WORKHUB_AI_LIMIT`（月度 AI 预算 USD，用于刘海预警百分比）。

## 用量数据（订阅用户，本地解析）

不走任何账单 API，直接读本地日志（适合 Claude/Codex 订阅用户，零配置）：

- **Claude**：`~/.claude/projects/**/*.jsonl` 里 `type:"assistant"` 记录的 `message.usage`，按天/模型聚合，按 message id + request id 去重（同 ccusage 思路）。见 [claudeUsage.ts](daemon/src/sources/claudeUsage.ts)。
- **Codex**：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 里 `event_msg → token_count` 的 `total_token_usage`（每会话取最后一条累计值）。见 [codexUsage.ts](daemon/src/sources/codexUsage.ts)。

费用是**估算**（订阅不计费），用粗略单价表 [pricing.ts](daemon/src/sources/pricing.ts)；主指标是 token 量。

> 注：日期按本地时区归到"今天/本月"，所以跨午夜的会话会落到对应自然日。要组织级账单（API 用户）可改用 Anthropic Usage/Cost Admin API。
