import SwiftUI
import SwiftData

@main
@MainActor
struct CommuteFocusApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    init() {
        do {
            container = try ModelContainer(for: LocalRecord.self)
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                AppRoot(container: container)
                    .modelContainer(container)
            } else {
                ContentUnavailableView("无法打开本机数据", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("请保留应用数据，重新启动后再试。\n\(startupError ?? "")"))
            }
        }
    }
}

@MainActor
struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth: AuthService
    @StateObject private var store: AppStore
    init(container: ModelContainer) {
        let auth = AuthService()
        _auth = StateObject(wrappedValue: auth)
        _store = StateObject(wrappedValue: AppStore(context: container.mainContext, auth: auth))
    }
    var body: some View {
        TabView {
            NavigationStack { CommuteView() }
                .tabItem { Label("通勤", systemImage: "tram.fill") }
            NavigationStack { TasksView() }
                .tabItem { Label("任务", systemImage: "checklist") }
            NavigationStack { HistoryView() }
                .tabItem { Label("记录", systemImage: "chart.bar.xaxis") }
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(.teal)
        .environmentObject(store)
        .environmentObject(auth)
        .onChange(of: auth.owner) { _, _ in store.changeOwner() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.foreground() }
            else { store.saveActive() }
        }
        .alert("提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

extension View {
    func primaryAction() -> some View {
        self.buttonStyle(.borderedProminent).controlSize(.large)
    }
}

func clockText(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}
