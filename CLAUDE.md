## Agent skills

### Issue tracker

Issues are tracked on GitHub. See `docs/agents/issue-tracker.md`.

### Triage labels

五角色中文标签体系 — 需要评估、等待报告人回复、准备好给 AI 处理、需要人工处理、不修复。详见 `docs/agents/triage-labels.md`。

### Domain docs

Single-context — 单个 `CONTEXT.md` + `docs/adr/` 在项目根目录。详见 `docs/agents/domain.md`。

## OpenWrt 加包规则

添加新包时必须依次完成三步：
1. **查依赖** — 确认包及其所有依赖都在 `.config` 中为 `=y`
2. **补 feed** — 确认 `diy-part1.sh` 中对应的第三方 feed 已启用
3. **改 .config** — 包名和依赖全部写入 `.config`，同步更新 `shell/custom-packages.sh`
