import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var auth: AuthService
    @State private var showAccount = false
    @State private var confirmSignOut = false
    var body: some View {
        Form {
            Section("通勤偏好") {
                Stepper("去程 \(store.preferences.outboundMinutes) 分钟", value: preference(\.outboundMinutes), in: 10...360, step: 5)
                Stepper("返程 \(store.preferences.inboundMinutes) 分钟", value: preference(\.inboundMinutes), in: 10...360, step: 5)
                Stepper("到站收尾 \(store.preferences.bufferMinutes) 分钟", value: preference(\.bufferMinutes), in: 0...10)
                Text("时长和收尾设置从下一次通勤生效。当前通勤可在首页延长。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("提醒") {
                Toggle("专注结束与到站收尾提醒", isOn: Binding(get: { store.preferences.reminders }, set: { value in
                    var preferences = store.preferences
                    preferences.reminders = value
                    store.savePreferences(preferences)
                    if value {
                        Task { _ = await store.notifications.requestPermission(); store.refreshNotifications() }
                    }
                }))
                Text("锁屏提醒由系统投递，显示和声音受通知权限、静音及系统专注模式影响。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("账号与同步") {
                LabeledContent("当前账号", value: auth.email)
                Text(store.syncStatus).font(.subheadline).foregroundStyle(.secondary)
                if auth.session == nil {
                    Button("登录或注册") { showAccount = true }.disabled(store.active != nil)
                    Text("本机模式与登录账号的数据分别保存，不会自动合并或上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button(store.syncing ? "正在同步…" : "立即同步") { store.requestSync() }.disabled(store.syncing)
                    Button("修改密码") { showAccount = true }.disabled(store.active != nil)
                    Button("退出登录", role: .destructive) { confirmSignOut = true }.disabled(store.active != nil || store.syncing)
                }
                if store.active != nil {
                    Text("请先结束通勤，再切换账号。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if CloudConfiguration.current == nil {
                    Text("此构建尚未连接云服务。任务、排程与计时可在本机使用；账号功能需完成工程配置。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("通勤专注助手 · 1.0\n给重要的事留一点时间，也给自己留一点余地。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("按你的节奏")
        .sheet(isPresented: $showAccount) { AccountView() }
        .confirmationDialog("退出后，本机未同步的数据仍保留在此账号空间，下次登录可继续同步。", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                do { try auth.signOut() }
                catch { store.error = error.localizedDescription }
            }
        }
    }
    private func preference(_ keyPath: WritableKeyPath<Preferences, Int>) -> Binding<Int> {
        Binding(get: { store.preferences[keyPath: keyPath] }, set: { value in
            var preferences = store.preferences
            preferences[keyPath: keyPath] = value
            store.savePreferences(preferences)
        })
    }
}

struct AccountView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var mode = "登录"
    @State private var verificationType: String?
    @State private var recoveryVerified = false
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                if auth.session != nil && verificationType == nil {
                    Section("设置新密码") {
                        SecureField("至少 8 个字符", text: $password).textContentType(.newPassword)
                        Button("保存新密码") {
                            run { try await auth.updatePassword(password); dismiss() }
                        }.disabled(password.count < 8 || busy)
                    }
                } else if let type = verificationType {
                    Section("输入邮件验证码") {
                        Text("已向 \(email) 发送邮件，请输入其中的验证码。")
                        TextField("验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        if type == "recovery" {
                            SecureField("新密码，至少 8 个字符", text: $password).textContentType(.newPassword)
                        }
                        Button("验证并继续") {
                            run {
                                if !recoveryVerified { try await auth.verify(email: email, code: code, type: type) }
                                if type == "recovery" {
                                    recoveryVerified = true
                                    try await auth.updatePassword(password)
                                }
                                dismiss()
                            }
                        }.disabled(code.isEmpty || busy || (type == "recovery" && password.count < 8))
                    }
                } else {
                    Picker("账号操作", selection: $mode) {
                        Text("登录").tag("登录")
                        Text("注册").tag("注册")
                        Text("重置密码").tag("重置密码")
                    }.pickerStyle(.segmented)
                    TextField("邮箱", text: $email).keyboardType(.emailAddress)
                        .textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if mode != "重置密码" {
                        SecureField(mode == "注册" ? "密码，至少 8 个字符" : "密码", text: $password)
                            .textContentType(mode == "注册" ? .newPassword : .password)
                    }
                    Button(busy ? "请稍候…" : mode) {
                        run {
                            email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            if mode == "登录" { try await auth.login(email: email, password: password); dismiss() }
                            else if mode == "注册" {
                                let signedIn = try await auth.signup(email: email, password: password)
                                if signedIn { dismiss() }
                                else { verificationType = "signup" }
                            } else {
                                try await auth.sendRecovery(email: email)
                                verificationType = "recovery"
                                password = ""
                            }
                        }
                    }.disabled(busy || !email.contains("@") || (mode != "重置密码" && password.isEmpty) || (mode == "注册" && password.count < 8))
                }
                if let message { Text(message).foregroundStyle(.red) }
            }
            .navigationTitle("你的专注空间")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
            .disabled(CloudConfiguration.current == nil || busy)
            .interactiveDismissDisabled(busy)
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }
}
