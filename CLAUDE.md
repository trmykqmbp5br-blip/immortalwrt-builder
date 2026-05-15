## Agent skills

### Issue tracker

Issues are tracked on GitHub. See `docs/agents/issue-tracker.md`.

### Triage labels

五角色中文标签体系 — 需要评估、等待报告人回复、准备好给 AI 处理、需要人工处理、不修复。详见 `docs/agents/triage-labels.md`。

### Domain docs

Single-context — 单个 `CONTEXT.md` + `docs/adr/` 在项目根目录。详见 `docs/agents/domain.md`。

### Build workflow

完整构建流程文档见 `docs/使用说明.md`，包括缓存策略、第三方包处理架构、BINARY_SOURCE 声明格式等。

**维护注意事项（必须遵守）：**
1. 新增 BINARY 包时 → `package/custom-provides/Makefile` 的 `PROVIDES:=` 里加上包名，否则编译期依赖检查会断裂
2. `apply_manifest()` 之后**绝对不要**再次执行 `make defconfig`，否则 Kconfig 引擎会根据 `depends on`/`select` 把 BINARY 包复活，导致编译报错
