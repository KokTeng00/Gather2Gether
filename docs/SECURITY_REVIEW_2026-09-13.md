# 安全与 CI 检查记录 · 2026-09-13

范围：当前仓库、主要 API 的身份与输入边界、活动受众/RLS/私密媒体的现有回归、举报权限、管理员访问、公开依赖漏洞公告，以及 GitHub Actions 失败日志。本次没有对生产服务进行攻击性测试，也没有更改生产数据库或凭据；这不构成“没有任何漏洞”的保证。

## 已修复

| 问题 | 证据与影响 | 修复 |
| --- | --- | --- |
| 举报字段权限过宽 | 在临时数据库中以 `authenticated` 身份，成功为新举报写入 `resolved` 状态；原入口也允许重复举报和对不可访问活动的举报 | 限制 INSERT 列，数据库检查身份和活动可见性，生成状态/时间/ID，重复提交幂等，每小时最多 20 个新活动举报 |
| 管理员 MFA 未强制 | 文档要求 MFA，但原 `_is_moderator()` 只检查角色；`aal1` 会话能进入管理权限边界 | 所有既有管理 RPC 共用的权限函数要求 `aal2`；增加移动端 TOTP 设置与验证入口，并重新检查服务器授权 |
| JSON 大请求可能耗尽内存 | 新测试证明没有 Content-Length 或伪造较小长度时，API 和模型服务会完整读取大请求再返回 413 | 共享流式字节上限，越界立即取消；同步用于 Supabase embedding 入口，并验证分片 UTF-8 |
| 开发依赖已知漏洞 | npm 审计报告 `sharp` 的 libheif 公告以及 `miniflare`、`wrangler` 受影响，共 3 个高危依赖条目；属于同一依赖链，不代表 3 个独立线上漏洞 | Wrangler 4.125.0 → 4.131.1，更新锁文件；修复后 npm 审计为 0 |
| 私密文件检查可被名称误导 | 原检查跳过所有名字包含 `example` 的文件，包括保存的计划与签名文件 | 只允许明确列出的模板，并补齐本地配置忽略规则和回归测试 |

依赖公告：[GHSA-rgj7-g3m4-5g8c](https://github.com/advisories/GHSA-rgj7-g3m4-5g8c)。MFA 使用 Supabase 当前会话的 `aal`，参见[官方文档](https://supabase.com/docs/guides/auth/auth-mfa)。

## CI 原因与修改

- [最新失败运行](https://github.com/KokTeng00/Gather2Gether/actions/runs/34749998442)：Flutter 格式检查判定 `sign_in_screen_test.dart` 需要重新排版，退出码 1；同次 edge 和 database 任务成功。
- [前一轮失败](https://github.com/KokTeng00/Gather2Gether/actions/runs/34719121526)：两项窄屏导航单行布局测试失败。
- CI 原先使用 `latest`，实际为 Flutter 3.47.4 / Dart 3.13.3；本机为 Flutter 3.38.5 / Dart 3.10.4。现在固定到已在本机完整验证的 3.38.5，保留格式与布局断言。此修改不宣称已经兼容 3.47.4；后续 SDK 升级需同步处理新版布局差异。
- edge 任务增加 `npm audit --audit-level=high`，既有测试自动包含新增安全回归。
- [修复分支首次 GitHub 实跑](https://github.com/KokTeng00/Gather2Gether/actions/runs/34750960853)：Flutter 和 edge 全部通过；数据库在下载镜像时遇到 ECR 的 `toomanyrequests: Rate exceeded`，尚未进入 SQL 测试。数据库脚本现增加有限重试和官方 Docker Hub/ECR 备用源，两个来源使用已核对一致的 SHA-256 内容摘要；每个镜像下载最多五分钟，失败仍终止 CI，不跳过数据库断言。

## 本地验证

- Dart 格式检查、Flutter 分析通过；182 项 Flutter 测试通过。
- 132 项 Node 后端测试通过。
- 临时离线 Docker 数据库：28 个迁移、9 套 SQL 回归通过；检查后删除容器。
- 6 项 Python 下载恢复测试通过，覆盖缓存、备用源、超时、重试及全部失败后的非零退出边界。
- Pages、模型 Worker、推送 Worker 的构建/部署预检查通过，没有发布生产版本。
- npm 审计为 0 个已知漏洞；OSV 查询 144 个 hosted Dart 包，没有匹配公告。这不覆盖 SDK、原生二进制或本地 MapLibre 修改的完整安全审计。
- Gitleaks 8.30.1 扫描 HEAD 可达历史；8 个命中经核对为 6 个测试缓存键及 2 个公开 Supabase publishable key。没有发现新增有效私密凭据；未扫描远端缓存、旧克隆与不可达历史。

## 仍需落实

1. **历史凭据轮换**：`BETA_RELEASE.md` 记录的数据库密码、Supabase 管理凭据、Cloudflare token 和 Google OAuth secret 曾进入历史文件。删除历史和本次扫描不能撤销泄露，需要在供应商侧完成替换并验证登录/服务。这次只读验证现有 Supabase 管理凭据返回 HTTP 401，需要重新授权才能继续轮换；没有更改生产凭据。
2. **发布修复**：代码修复只有在部署对应迁移、API/模型/embedding 函数和移动端后才保护线上用户。管理员需启用 Supabase TOTP 并完成真实设备验证；旧客户端未建立 `aal2` 会话时无法使用管理功能。
3. **运营边界**：公网注册/请求的整体滥用防护、图片内容审核、恢复演练、监控告警和长期负载表现仍需在上线准备中验证。现有测试不等于这些项目已经完成。

新的变更没有读取或修改其他项目的生产数据。
