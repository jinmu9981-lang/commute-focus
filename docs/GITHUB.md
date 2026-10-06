# 把「途间」分享给别人

这个仓库包含两种使用方式：

**直接使用：[途间网页体验版](https://jinmu9981-lang.github.io/commute-focus/)**

| 版本 | 使用方法 | 已有能力 |
|---|---|---|
| 网页体验版 | 打开 GitHub Pages 链接 | 编辑任务、自动排程、前台计时、进度记录；数据保存在各自浏览器 |
| iPhone 原生源码 | 用 Mac 和 Xcode 编译安装 | SwiftUI 界面、SwiftData、本地通知、可配置的 Supabase 账号同步 |

网页不是微信小程序，也不是可直接安装的 iPhone 安装包。网页不登录、不做云同步；浏览器被关闭或手机锁屏时不保证提醒。预置任务都是示例，访问者的修改保存在其自己的浏览器，不会回传仓库。清除浏览器数据会清除这些记录。

## 发布网页

1. 将本项目上传到自己的 GitHub 仓库，建议名称 `commute-focus`，默认分支 `main`。
2. 若希望所有人查看源码和使用网页，将仓库设为 Public。
3. 打开仓库 **Settings → Pages → Build and deployment → Source**，选择 **Deploy from a branch**。
4. 在 Branch 选择 **main**，目录选择 **/docs**，点击 **Save**。
5. 等部署完成，从 **Settings → Pages** 中复制 GitHub 给出的实际网页地址，发给朋友。

之后修改 `docs/index.html` 并推送到 main 会自动更新网页。为自己的副本开启 Pages 后，请等部署成功再分享实际地址。网页由 GitHub 内置发布流程部署，不需要填写密钥或运行自定义工作流。

## 不使用插件，通过网页上传

1. 将 `commute-focus-upload.zip` 解压，打开里面的 `commute-focus` 文件夹。
2. 打开 [GitHub 新建仓库](https://github.com/new)，名称填写 `commute-focus`，选择 Public，点击 Create repository。
3. 在新仓库页面点击 **uploading an existing file**（上传已有文件）。将 `commute-focus` 文件夹内的文件和子文件夹一起拖进去，再点 Commit changes。
4. 按上面的 Pages 设置步骤开启网页。

**不要只上传 ZIP 文件，也不要把外层 `commute-focus` 文件夹整体嵌套进去。** 上传完成后，仓库首页应直接看到 `README.md`、`docs`、`CommuteFocus` 等条目，且 `docs` 内有 `index.html`。

压缩包不包含依赖缓存和任何登录授权。看不到以点开头的文件时，可以在 macOS Finder 中按 Command＋Shift＋句号显示隐藏文件；这些文件包含忽略规则和自动检查配置。

官方说明：[设置 GitHub Pages 发布来源](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)。

## 给普通使用者的说明

打开 Pages 链接后，点击「安排这次通勤」。计时页中的「演示：快进到本段结束」用于快速体验完成确认，不代表真实投入时长。想用于日常通勤时，不使用快进即可正常倒计时。

## 给开发者的说明

原生工程和 Supabase 部署见仓库 README。GitHub Actions 的 Project checks 检查网页交互和数据库规则；iPhone build and tests 在 macOS Xcode 环境运行原生 XCTest。最新验证结果见 [验证记录](VALIDATION.md)。

网页源文件为 `web/commute-experience.html`，发布文件为 `docs/index.html`。生成的发布文件可以直接托管，不需要线上安装 Node、Python 或配置数据库。

## 上传内容

包含应用源码、测试、数据库迁移、网页发布文件和使用说明。不包含 `node_modules`、个人登录凭据、真实数据库密钥或本地用户任务记录。仓库不需要 Supabase service_role 密钥，也不需要 Apple 开发者证书。
