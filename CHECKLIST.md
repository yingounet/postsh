# PostSH 开发 Checklist

基于 [docs/DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md)、[docs/SESSION_RECOVERY.md](docs/SESSION_RECOVERY.md)、[docs/UI_DESIGN.md](docs/UI_DESIGN.md)。完成某项后将 `[ ]` 改为 `[x]`。

---

## 阶段 0：项目初始化

- [x] 创建 Flutter 项目
- [x] 集成 dartssh2
- [x] 配置 Riverpod
- [x] 配置 shared_preferences、flutter_secure_storage

---

## 阶段 1：连接与终端核心

- [x] 连接配置输入页
- [x] SSH 连接与 shell
- [x] 命令输入框
- [x] 命令队列
- [x] 回显展示区
- [x] 会话状态展示

---

## 阶段 2：会话恢复基础

- [ ] 断线检测
- [ ] 自动重连（指数退避 1s/2s/4s... 上限 30s）
- [ ] 未发命令保留
- [ ] 重连后重放
- [ ] 手动重连入口（「重连」按钮）

---

## 阶段 3：连接管理与智能补全

### 3.1 连接管理

- [x] 连接配置存储
- [x] 快速连接列表（最近 5 条）
- [x] 私钥认证（已实现）

### 3.2 智能补全

- [ ] 历史命令存储
- [ ] 静态命令列表（约 1000 条 Unix 命令）
- [ ] 补全引擎
- [ ] 补全 UI

---

## 阶段 4：多端与弱网优化

- [ ] 桌面三端打包（macOS/Linux/Windows）
- [ ] 移动端适配（iOS/Android）
- [ ] PTY 可选/可配置（支持 tmux/screen，连接页开关）
- [ ] 会话恢复增强（tmux/screen 建议）
- [ ] 已发未回显提示
- [ ] 弱网测试

---

---

## MVP 验收检查表

- [x] 可保存连接配置并快速连接
- [x] 支持密码与私钥认证
- [x] 输入命令可提交，回显正确展示
- [ ] 弱网/断网时命令可排队，恢复后自动发送
- [ ] 断线后自动重连，未发命令自动重放
- [ ] 输入时出现补全提示，右方向键可补齐
- [ ] 至少一种桌面端可打包运行
