# 途间 · 通勤专注助手

**[点这里直接使用网页版](https://jinmu9981-lang.github.io/commute-focus/)** · [查看 GitHub 源码](https://github.com/jinmu9981-lang/commute-focus)

无需安装：任务编辑、通勤排程、专注计时和进度记录都可以在浏览器操作。自己的任务保存在自己的浏览器中。想发布自己的副本，见 [GitHub 分享指南](docs/GITHUB.md)。

网页版本的数据只保存在当前浏览器，不提供账号同步和锁屏通知；iPhone 原生源码提供相应实现，已通过云端 Xcode 编译和自动测试，真机安装与云同步仍需配置。

面向 iPhone 的原生 SwiftUI 应用。手动维护大任务与步骤，按优先级和通勤时长安排 10–30 分钟专注段，支持暂停、到站收尾、进度确认、离线使用和独立账号同步。

## 打开与运行

1. 在安装完整 Xcode 16 或更新版本的 Mac 上打开 `CommuteFocus.xcodeproj`。
2. 选择 `CommuteFocus` scheme 和 iOS 17 或更新版本的 iPhone 模拟器，运行。
3. 真机运行时，在 Signing & Capabilities 中选择自己的开发团队，并将 `com.example.CommuteFocus` 改为唯一的 Bundle Identifier。
4. 初次可直接使用本机模式：新建大任务 → 添加步骤 → 通勤页安排计划 → 确认开始。无需云端配置即可使用本机任务、计时和历史。

工程没有第三方 Swift 依赖。Node 仅用于开发期数据库测试和工程生成，不参与 iPhone 应用运行。工程文件已生成，不需要先运行脚本。

**验证结果：GitHub Actions 已通过 Xcode 16.4 编译及 iPhone 模拟器中的 19 项 XCTest；网页交互与数据库规则的 10 项测试也全部通过。** 真机锁屏通知、签名安装和真实 Supabase 账号同步尚待配置与联调，自动测试不替代这些验证。详细结果见 [验证记录](docs/VALIDATION.md)。

## 功能与约定

- 默认去程和返程各 60 分钟，预留 3 分钟到站收尾；可以调整单程时长和 0–10 分钟收尾。
- 大任务有高、中、低优先级。同优先级按用户拖动顺序；任务内部按步骤顺序。
- 默认每段 25 分钟，长任务拆分为 10–30 分钟单元。35 分钟拆为 25＋10，31 分钟拆为 21＋10。若本次截断会产生不足 10 分钟的孤立尾段，则暂缓该步骤，尝试其他任务。
- 不足 10 分钟的步骤只与同一任务的后续相邻步骤合并。不自动理解或拆解任务内容。
- 预览是基于完成前序步骤的预估。每段保存进度后重新生成计划；没有确认完成，不会自动启动后续步骤。
- 暂停不移动到站时间；暂停恢复后放不下原段剩余时长时，进入进度确认。通勤延长按钮每次增加 10 分钟。
- 跳过会在本次通勤排除整个大任务，避免绕过前置步骤；下次通勤重新参与安排。
- 完成确认支持逐步勾选，后一步只能在前一步已勾选后勾选。没完成的步骤需保留剩余预计时长；默认值可修改。
- 通知只调度当前段及本次收尾。关闭提醒、暂停、改期、结束通勤会重算或取消通知。无通知权限仍可前台计时；系统静音和专注模式可能影响提醒。
- 到站收尾停止当前专注并等待确认；不会自动替用户确认任务完成。记录中的进行中通勤需要在原设备结束。
- 本机模式数据和登录账号数据彼此隔离，不自动迁移。退出账号保留该账号本机未同步数据，重新登录后可重试。
- 专注计时只保存在启动设备，其他设备仅同步业务数据与历史。不提供跨设备接管或全局互斥锁。

## 云端配置

详见 [Supabase 配置](docs/SUPABASE.md)。需要自己的 Supabase 项目，未提供的账号、开发团队和云端项目不包含在仓库中。

1. 执行 `supabase/migrations/202610060001_initial.sql`。
2. 配置邮箱认证、验证邮件和密码重置邮件的验证码模板。
3. 在 `Config/Development.xcconfig` 中填写项目 URL 与公开 anon/publishable key。URL 中的 `https:/$()/` 是 xcconfig 转义写法，不能改成直接的 `https://` 注释形式。
4. 真机或模拟器中注册、验证邮箱并登录，测试两台设备同步。

登录实现使用 Supabase Auth REST API；访问令牌与刷新令牌保存在此设备 Keychain，数据库通过 PostgREST 调用。**不得填写 service_role key。**

## 工程结构

| 目录 | 内容 |
|---|---|
| `CommuteFocus/Core` | Codable 业务模型、纯排程器、可恢复计时状态机 |
| `CommuteFocus/App` | SwiftUI 入口、全局状态与操作编排 |
| `CommuteFocus/Views` | 通勤、任务、记录、设置及账号界面 |
| `CommuteFocus/Services` | SwiftData 本地持久化、同步队列、云端认证与本地通知 |
| `CommuteFocusTests` | XCTest 排程、计时和本地存储测试 |
| `supabase/migrations` | PostgreSQL 表、账号隔离策略及幂等同步函数 |

记录保存在 SwiftData 的 `LocalRecord` 中，每个业务对象独立一条记录；`dirty + mutationID` 是持久化待同步队列。完成步骤变更和专注日志在同一次本地保存中提交，随后清理设备计时状态，崩溃恢复用日志 ID 防止重复扣减。

## 测试命令

```sh
npm ci --ignore-scripts
npm run check
npm run check:syntax
npm run test:database
npm run test:web
```

数据库测试通过 PGlite 执行真实 PostgreSQL 迁移和函数，认证上下文由测试桩提供；不访问真实 Supabase，也不发送邮件。

安装 Xcode 后：

```sh
xcodebuild -list -project CommuteFocus.xcodeproj
xcodebuild -showdestinations -project CommuteFocus.xcodeproj -scheme CommuteFocus
# 把下方 SIMULATOR_ID 换成上一步列出的可用 iPhone 模拟器 ID。
xcodebuild test -project CommuteFocus.xcodeproj -scheme CommuteFocus \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' CODE_SIGNING_ALLOWED=NO
```

增加或删除 Swift 文件后，运行 `npm run project` 重新生成确定性的工程文件，再执行检查。签名和 Bundle Identifier 等长期配置应同时更新生成脚本，避免再生成时丢失。当前未包含 App Store 发布所需的正式图标、隐私政策页面或上架配置。
