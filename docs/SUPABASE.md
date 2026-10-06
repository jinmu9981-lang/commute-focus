# Supabase 配置与同步合同

## 创建环境

使用自己的 Supabase 项目，在 SQL Editor 执行仓库中的初始迁移。已有 Supabase CLI 工程也可通过迁移机制执行，切勿重复运行初始建表脚本。

从项目设置复制 Project URL 和公开的 anon 或 publishable key 至 `Config/Development.xcconfig`。移动端不持有数据库密码或 service_role key。未配置时显示本机模式，云服务不会被伪装为可用。

## 邮箱登录与验证

在 Authentication 中开启邮箱密码登录，并开启 Confirm email，密码最低长度设为 8 或更高（若提高，请同时调整客户端提示）。生产环境配置可实际投递邮件的 SMTP 服务；Supabase 开发邮件服务可能限制收件人和频率。

此版本在应用内输入邮件验证码，不使用网页深链接。将 **Confirm signup** 和 **Reset password** 两种邮件模板的正文配置为包含 `{{ .Token }}`，例如：

```html
<h2>通勤专注助手</h2>
<p>你的验证码：<strong>{{ .Token }}</strong></p>
<p>请返回应用输入此验证码。如果不是你发起的操作，请忽略这封邮件。</p>
```

不要仅保留默认 `{{ .ConfirmationURL }}` 链接，否则用户无法在本应用输入验证码。遵循项目配置的验证码有效期和限流。注册验证调用 `/auth/v1/verify`，类型为 `signup`；密码恢复类型为 `recovery`，验证成功后调用 `/auth/v1/user` 修改密码。

使用真实服务验证：注册 → 收到验证码 → 验证并登录 → 退出 → 密码登录 → 重置密码 → 旧密码失效 → 新密码登录。账号枚举保护可能令重复注册返回通用提示，这是服务行为。

## 数据结构与权限

`records` 使用 `(owner_id, id)` 复合主键，字段包括：

- `kind`：task、step、journey、focus、preferences。
- `payload`：Codable 业务对象 JSON；UUID 为字符串，日期使用 Swift Codable 默认参考纪元秒数（2001-01-01 UTC），客户端和服务端均将其视为不透明业务数据。
- `deleted`：永久删除标记。当前没有恢复已删除记录功能。
- `revision`：服务器全局递增版本，用于客户端拒绝旧版本覆盖。
- `mutation_id`：客户端操作 ID；`updated_at` 为服务器提交时间。

`mutation_receipts` 保存操作去重凭证。它与记录均随账号删除而级联删除；第一版不自动清理凭证或 tombstone，以免旧设备离线数据恢复或旧请求重放。

客户端只有当前账号记录的 SELECT 权限。INSERT/UPDATE/DELETE 均不直接授权；所有变更走 `apply_changes(changes jsonb)`，最多 100 条，事务提交。该 SECURITY DEFINER 函数固定空 search_path，身份始终取 `auth.uid()`，忽略客户端伪造的 owner_id。函数只授权 authenticated 角色。

## 同步行为

1. 每次本地写入持久化 `dirty` 和新的 `mutationID`。
2. 联网、进入前台、写入成功或点击同步时，先提交待同步记录，再按 ID 分页拉取该账号全部记录。
3. 正常可编辑对象采用服务器后提交版本；永久 tombstone 优先，focus 历史写入后不可修改。
4. 同一操作重复提交只返回当前记录，不重新应用旧 payload，即使其他设备在此期间已提交新版本。
5. 请求期间产生的新本地修改不会被旧请求回执清除；随后继续提交新的操作。
6. 完成步骤和专注日志的本地写入为原子操作。远端每批提交原子，但超过 100 条的同步可能分批；下一次同步补齐。
7. 网络错误不清空队列；展示“待同步”及错误信息。恢复网络、进入前台或手动点击时重试，不做无限后台轮询。

首次运行无需注册。为了避免把本机模式任务上传到错误账号，登录不会自动导入本机模式数据。当前没有导入导出和跨账号迁移功能。

## 验证边界

PGlite 测试覆盖迁移 SQL、函数、RLS、幂等和 tombstone，但不覆盖真实 Supabase Auth 邮件、令牌刷新、PostgREST 网络、服务区域连通性或两台 iPhone 的生命周期。上线前必须用目标网络环境完成这些联调，不把本地 SQL 测试当作云同步实测。
