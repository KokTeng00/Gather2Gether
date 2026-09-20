# 安全与 CI 检查记录 · 2026-09-13

范围：当前仓库、主要 API 的身份与输入边界、活动受众/RLS/私密媒体的现有回归、举报权限、管理员访问、公开依赖漏洞公告，以及 GitHub Actions 失败日志。首次代码审查没有修改生产；后续经所有者授权，已完成本文记录的 Supabase 生产修复、Cloudflare 部署、Google 密钥轮换和有限验证。这不构成“没有任何漏洞”的保证。

## 已修复

| 问题 | 证据与影响 | 修复 |
| --- | --- | --- |
| 举报字段权限过宽 | 在临时数据库中以 `authenticated` 身份，成功为新举报写入 `resolved` 状态；原入口也允许重复举报和对不可访问活动的举报 | 限制 INSERT 列，数据库检查身份和活动可见性，生成状态/时间/ID，重复提交幂等，每小时最多 20 个新活动举报 |
| 管理员 MFA 未强制 | 文档要求 MFA，但原 `_is_moderator()` 只检查角色；`aal1` 会话能进入管理权限边界 | 所有既有管理 RPC 共用的权限函数要求 `aal2`；增加移动端 TOTP 设置与验证入口，并重新检查服务器授权 |
| JSON 大请求可能耗尽内存 | 新测试证明没有 Content-Length 或伪造较小长度时，API 和模型服务会完整读取大请求再返回 413 | 共享流式字节上限，越界立即取消；同步用于 Supabase embedding 入口，并验证分片 UTF-8 |
| embedding 可被未登录调用 | 线上仅带公开 publishable key、不带用户会话的短请求返回 HTTP 200 和 384 维向量，尽管函数配置为 `verify_jwt = true` | 函数在读取请求体和初始化模型前，通过 Auth `/user` 验证用户会话；拒绝缺失、伪造、失效和匿名身份，认证服务故障时停止推理 |
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
- 143 项 Node 后端测试全部通过，包含生产复查新增的 11 项 embedding 身份与输入边界回归。
- 临时离线 Docker 数据库：28 个迁移、9 套 SQL 回归通过；检查后删除容器。
- 6 项 Python 下载恢复测试通过，覆盖缓存、备用源、超时、重试及全部失败后的非零退出边界。
- Pages、模型 Worker、推送 Worker 的构建/部署预检查通过；后续 Pages 与模型 Worker 的生产发布见下文。远程推送仍关闭。
- npm 审计为 0 个已知漏洞；OSV 查询 144 个 hosted Dart 包，没有匹配公告。这不覆盖 SDK、原生二进制或本地 MapLibre 修改的完整安全审计。
- Gitleaks 8.30.1 扫描 HEAD 可达历史；8 个命中经核对为 6 个测试缓存键及 2 个公开 Supabase publishable key。没有发现新增有效私密凭据；未扫描远端缓存、旧克隆与不可达历史。

## 仍需落实

1. **凭据维护**：数据库密码已替换，新密码连接成功、旧密码认证失败；失效的本地 Supabase 管理凭据已替换为仅限本项目的令牌，到期日为 2027-09-12。Cloudflare token 已通过供应商控制台滚动替换，Google 旧密钥已停用，实际登录验证通过。其他部署机器如仍保存旧凭据，需要更新；不要从旧计划或备份恢复已失效的凭据。
2. **移动端发布**：Supabase 三个缺失迁移、embedding v4、Cloudflare API 和模型 Worker 均已部署，TOTP 配置已启用。移动端修复的发布，以及真实设备登录/MFA 验证仍需完成；旧客户端未建立 `aal2` 会话时无法使用管理功能。
3. **运营边界**：公网注册/请求的整体滥用防护、图片内容审核、恢复演练、监控告警和长期负载表现仍需在上线准备中验证。现有测试不等于这些项目已经完成。

## Supabase 生产修复

- 目标仅为 `gather2gether`（`zpxwzpdjyvvbpywbrnpr`），没有读取或修改其他项目的生产数据。
- 变更前创建受保护的数据库备份，包含 public、auth、storage 和迁移记录。备份目录可读取，但尚未完成完整恢复演练。
- 在一个事务内补齐 `20260912000300_event_audiences`、`20260913000100_report_security`、`20260913000200_moderator_mfa`，迁移数从 25 变成 28。活动 1、用户资料 2、举报 0，变更前后数量一致。
- 只读权限检查确认：举报状态不可由普通用户 INSERT；受众成员表 RLS 已开启；管理员 `aal1` 和伪造 user_metadata 角色被拒绝，可信管理员 `aal2` 被允许。
- 关闭与应用设计不符的邮箱登录；Google 保持开启，Apple/匿名登录保持关闭；密码最短长度修正为 10，TOTP 保持开启。
- 数据库密码通过 Terraform 定向更新，只有随机密码资源替换，Supabase 项目原地更新。计划前通过管理 API 核实项目身份，未重建项目。受限令牌不包含完整 Terraform 刷新所需的 API key/计费权限，此次经过审查的定向计划使用 `-refresh=false`。
- 强制 SSL 已开启且平台返回 `appliedSuccessfully: true`。客户端以 `verify-full` 验证官方 CA，使用 TLS 1.3；`sslmode=disable` 被服务器以 `ESSLREQUIRED` 拒绝。
- 新管理令牌由所有者批准，期限按约一年设置，最终日期为 2027-09-12（9 月 13 日被平台一年上限拒绝）。仅授予本项目 Project Settings/Migrations 只读，以及 Auth Config/Database Config/SSL/Edge Functions 读写；保存于忽略的本地配置，文件权限 0600。Auth 配置 PATCH 实测仍需额外项目权限，因此使用已登录控制台完成配置，没有扩大令牌权限。
- 已备份旧 embedding 函数，部署的 v4 为 ACTIVE 且 `verify_jwt = true`。复测确认：只有公开 key、把公开 key 当作 Bearer、伪造用户 JWT 三种请求均返回 401；认证健康端点使用应用公开 key 返回 200，项目为 ACTIVE_HEALTHY。通过 Auth 复核身份遵循[官方用户认证模式](https://supabase.com/docs/guides/functions/auth)。完整的 Google 登录、真实用户语义搜索和管理员 TOTP 流程仍需设备验证。

## Cloudflare 与 Google 后续处理

- Cloudflare 仅处理个人账户内 Gather2Gether 的现有 Terraform token，保留 Pages/R2 权限和原有不限期设置，其他 token 未修改。供应商的滚动替换流程使前一版本失效；新 token 的验证接口返回 `active`，读取项目及实际 Pages 发布成功。原本地值在轮换前已无法用于 API，因此没有声称直接验证了历史 token 的撤销响应。参见[Cloudflare 轮换说明](https://developers.cloudflare.com/fundamentals/api/how-to/roll-token/)。
- Pages/API 已发布安全修复提交 `1c44ec4776bc65c53575446d6f283c77a35b9e2b`，生产部署 `4a0cfcd3-00d0-47f9-92b3-1cb4d89d4002` 状态为 `success`。模型 Worker 版本为 `ed627b5c-b0a4-410e-9b9f-06e389601729`，流量为 100%。原有服务、R2 与模型密钥绑定保留。
- `npm run check:production` 通过：API 健康检查正常，匿名请求返回 401，浏览器来源请求返回 403。公开信息页面仍缺少所有者指定的运营者名称和联系邮箱；远程推送未启用。
- Google OAuth 在匹配现有客户端的 Gather2Gether 项目中新增密钥，先更新 Supabase 与受保护的本地变量，再验证登录并停用旧密钥；客户端 ID、回调 URI、权限范围保持不变，没有修改工作账户项目。过程遵循[Google 密钥轮换流程](https://support.google.com/cloud/answer/6158849#rotate-client-secret)。
- 旧密钥停用后，Google token 接口对旧密钥返回 `401 invalid_client`；新密钥配合虚构刷新令牌返回 `400 invalid_grant`，错误密钥对照返回 `401 invalid_client`。这组检查仅证明客户端凭据状态，不单独代表用户登录成功。
- 随后完成一次实际 Google → Supabase 登录。只读数据库确认既有 Google 用户的 `last_sign_in_at` 更新至 `2026-09-13T13:28:44.660509Z`，晚于停用旧密钥后的测试开始时间；用户和用户资料均仍为 2。浏览器无法打开应用自定义协议，因此该检查覆盖服务端 OAuth 登录，不代替手机上的回调、PKCE 与会话恢复测试。
- 新凭据只保存于忽略的本地部署配置（0600）；操作前配置保存在受保护的备份目录。受限 Supabase 管理令牌仍不具备部分 Auth 写入及完整 Terraform 刷新权限，本次通过已登录控制台更新 Auth，没有扩权或伪造 Terraform 状态。
