import SwiftUI

// MARK: - 앱 진입점

@main
struct TruNASApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(AppModel())
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        // 툴바는 한 줄 통합 스타일로 고정(전체화면에서 넓어지는 상단줄 방지)
        .windowToolbarStyle(.unified)
    }
}

// MARK: - 탐색 항목

enum NavItem: String, CaseIterable, Identifiable {
    // 시스템
    case nasOverview, dashboard, alerts, services
    // 스토리지
    case pools, datasets, disks, snapshots, replications, scrubs
    // 공유
    case sharesSMB, sharesNFS, iscsi
    // 네트워크
    case interfaces, networkSummary, staticRoutes
    // 앱/가상머신
    case apps, appCatalog, vms
    // 계정
    case users, groups, apiKeys
    // 작업
    case cronjobs, rsyncTasks, cloudSyncs
    // 보안
    case certificates
    // 기타 시스템 관리
    case bootEnvs, sysUpdate, audit
    // 설정
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nasOverview: return "NAS 현황"
        case .dashboard: return "대시보드"
        case .alerts: return "알림"
        case .services: return "서비스"
        case .pools: return "스토리지 풀"
        case .datasets: return "데이터셋"
        case .disks: return "디스크"
        case .snapshots: return "스냅샷"
        case .replications: return "복제 작업"
        case .scrubs: return "스크럽 작업"
        case .sharesSMB: return "SMB"
        case .sharesNFS: return "NFS"
        case .iscsi: return "iSCSI 대상"
        case .interfaces: return "인터페이스"
        case .apps: return "앱 관리"
        case .vms: return "가상머신"
        case .users: return "사용자"
        case .groups: return "그룹"
        case .cronjobs: return "Cron 작업"
        case .rsyncTasks: return "Rsync 작업"
        case .cloudSyncs: return "Cloud Sync"
        case .certificates: return "인증서"
        case .bootEnvs: return "부팅 환경"
        case .sysUpdate: return "시스템 업데이트"
        case .audit: return "감사 로그"
        case .networkSummary: return "네트워크 요약"
        case .staticRoutes: return "정적 라우트"
        case .appCatalog: return "앱 카탈로그"
        case .apiKeys: return "API 키"
        case .settings: return "연결 설정"
        }
    }

    var icon: String {
        switch self {
        case .nasOverview: return "server.rack"
        case .dashboard: return "gauge"
        case .alerts: return "bell.badge"
        case .services: return "switch.2"
        case .pools: return "externaldrive.connected.to.line.below"
        case .datasets: return "folder.badge.plus"
        case .disks: return "internaldrive"
        case .snapshots: return "camera.on.rectangle"
        case .replications: return "arrow.left.arrow.right"
        case .scrubs: return "sparkles"
        case .sharesSMB: return "person.2.gobackward"
        case .sharesNFS: return "shared.with.you"
        case .iscsi: return "cylinder.split.1x2"
        case .interfaces: return "network"
        case .apps: return "shippingbox"
        case .vms: return "desktopcomputer"
        case .users: return "person.2"
        case .groups: return "person.3"
        case .cronjobs: return "clock.badge"
        case .rsyncTasks: return "arrow.triangle.2.circlepath"
        case .cloudSyncs: return "icloud.and.arrow.down"
        case .certificates: return "lock.shield"
        case .bootEnvs: return "drive.disk"
        case .sysUpdate: return "arrow.up.circle"
        case .audit: return "doc.plaintext"
        case .networkSummary: return "globe"
        case .staticRoutes: return "arrow.turn.up.right"
        case .appCatalog: return "square.grid.2x2"
        case .apiKeys: return "key"
        case .settings: return "gearshape"
        }
    }

    static let sections: [(name: String, items: [NavItem])] = [
        ("기기", [.nasOverview]),
        ("시스템", [.dashboard, .alerts, .services, .bootEnvs, .sysUpdate, .audit]),
        ("스토리지", [.pools, .datasets, .disks, .snapshots, .replications, .scrubs]),
        // WebDAV는 TrueNAS 25.10에서 라우트가 존재하지 않아 목록에서 뺐다
        ("공유", [.sharesSMB, .sharesNFS, .iscsi]),
        ("네트워크", [.interfaces, .networkSummary, .staticRoutes]),
        ("앱/가상머신", [.apps, .appCatalog, .vms]),
        ("계정", [.users, .groups, .apiKeys]),
        ("작업", [.cronjobs, .rsyncTasks, .cloudSyncs]),
        ("보안", [.certificates]),
        ("설정", [.settings]),
    ]
}

// MARK: - 루트

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.nav) {
                ForEach(NavItem.sections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.items) { item in
                            Label(item.label, systemImage: item.icon)
                                .tag(item)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // 사이드바 폭을 고정 범위로 유지해 상세 화면(예: 인터페이스)이 밀지 않게 한다
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .frame(minWidth: 190)
        } detail: {
            NavigationStack {
                switch model.nav {
                case .nasOverview: NasOverviewView()
                case .dashboard: DashboardView()
                case .alerts: AlertsView()
                case .services: ServicesView()
                case .pools: PoolsView()
                case .snapshots: SnapshotsView()
                case .scrubs: ScrubsView()
                case .settings: SettingsView()
                case .apps: AppsView()
                case .vms: VMsView()
                case .bootEnvs: BootEnvsView()
                case .sysUpdate: SystemUpdateView()
                case .audit: AuditView()
                case .appCatalog: AppCatalogView()
                case .apiKeys: ApiKeysView()
                case .networkSummary: NetworkSummaryView()
                default:
                    if let spec = model.nav.spec {
                        GenericEntityView(spec: spec)
                    } else {
                        Text("지원하지 않는 화면입니다.")
                    }
                }
            }
        }
        .statusOverlay()
        .task {
            // 연결이 없는 상태로 시작하면 자동으로 연결 설정 화면으로 이동
            if !model.isConfigured {
                model.nav = .settings
            }
            // 시작 시 자동 업데이트 확인 (실패해도 조용히 넘어감)
            if let latest = try? await AppUpdate.checkLatest(),
               AppUpdate.isNewer(latest, than: AppUpdate.currentVersion) {
                model.statusMessage = T("새 버전 \(latest) 이 있습니다. 설정 - 앱 업데이트에서 확인하세요.",
                                        "New version \(latest) available. See Settings - App update.")
                model.isError = false
                model.statusSeq += 1
            }
        }
        .onChange(of: model.isConfigured) { configured in
            // API 키 삭제/연결 지우기 등으로 연결이 깨지면
            // 사이드바를 유지한 채 연결 설정 화면으로만 이동한다.
            if !configured {
                model.nav = .settings
            }
        }
    }
}

// MARK: - 상태 표시 공통

struct StatusOverlay: ViewModifier {
    @EnvironmentObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let msg = model.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: model.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        Text(msg)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: .capsule)
                    .overlay(Capsule().strokeBorder(model.isError ? Color.orange : Color.green, lineWidth: 1))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    // 상태/오류 메시지는 2초 후 자동으로 사라진다.
                    // statusSeq가 새 메시지마다 증가하므로 바뀔 때마다 타이머가 다시 시작된다.
                    .task(id: model.statusSeq) {
                        let seq = model.statusSeq
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled, model.statusSeq == seq,
                              model.statusMessage != nil else { return }
                        withAnimation { model.statusMessage = nil }
                    }
                }
            }
    }
}

extension View {
    func statusOverlay() -> some View { modifier(StatusOverlay()) }
}

struct RefreshToolbar: View {
    @EnvironmentObject var model: AppModel
    let action: () -> Void

    var body: some View {
        HStack {
            if model.isBusy { ProgressView().controlSize(.small) }
            Button {
                action()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - 대시보드

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmPower: String? = nil   // "reboot" | "shutdown"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 전체화면에서 툴바 제목과 콘텐츠 제목이 겹쳐 상단이 두꺼워지는 문제 방지:
                // 화면 제목은 툴바(navigationTitle) 하나로만 표시한다.
                HStack {
                    Spacer()
                    RefreshToolbar { Task { await model.loadDashboard() } }
                }

                if let info = model.systemInfo {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "server.rack")
                                Text(info.hostname ?? "-").bold()
                            }
                            Text("버전: \(info.version ?? "-")")
                            if let up = info.uptime {
                                Text("가동 시간: \(up)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 12) {
                    GroupBox(label: Label("CPU", systemImage: "cpu")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.cpuUsage.map { String(format: "%0.1f %%", $0) } ?? "-")
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                            if let info = model.systemInfo, let m = info.cpuModel {
                                Text("\(m) · 코어 " + (info.cores.map { "\($0)스레드" } ?? ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if !model.coreUsages.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(model.coreUsages, id: \.name) { core in
                                        HStack(spacing: 6) {
                                            Text(core.name)
                                                .font(.caption2).mono()
                                                .frame(width: 42, alignment: .leading)
                                            UsageBar(percent: core.percent)
                                                .frame(height: 5)
                                            Text(String(format: "%0.0f%%", core.percent))
                                                .font(.caption2).mono()
                                                .frame(width: 34, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .frame(minWidth: 240, idealWidth: 320, maxHeight: .infinity)
                    }
                    GroupBox(label: Label("메모리", systemImage: "memorychip")) {
                        HStack(spacing: 22) {
                            let sorted = model.memoryUsage.sorted { $0.value > $1.value }
                            if sorted.isEmpty {
                                Text("-").foregroundStyle(.secondary)
                            }
                            ForEach(sorted.prefix(4), id: \.key) { key, value in
                                RingGauge(percent: value, label: key, diameter: 104)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .frame(minWidth: 300, idealWidth: 320)
                    }
                    Spacer()
                }

                GroupBox(label: Label("스토리지 풀", systemImage: "externaldrive.connected.to.line.below")) {
                    VStack(spacing: 8) {
                        if model.pools.isEmpty {
                            Text("연결된 풀이 없습니다.").foregroundStyle(.secondary)
                        }
                        ForEach(model.pools, id: \.name) { pool in
                            PoolRow(pool: pool)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    GroupBox(label: Label("시스템 작업", systemImage: "power")) {
                        HStack(spacing: 14) {
                            Button("재부팅") {
                                confirmPower = "reboot"
                            }
                            .disabled(model.isBusy)
                            Button("전원 끄기", role: .destructive) {
                                confirmPower = "shutdown"
                            }
                            .disabled(model.isBusy)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                }

                    GroupBox(label: Label("알림", systemImage: "bell.badge")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.alerts.isEmpty {
                            Text("활성 알림이 없습니다.").foregroundStyle(.secondary)
                        }
                        ForEach(model.alerts.suffix(4), id: \.id) { alert in
                            HStack(alignment: .top, spacing: 8) {
                                severityIcon(alert.severity)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.klass ?? "Alert").bold()
                                    if let text = alert.alert {
                                        Text(text).font(.callout).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .navigationTitle("대시보드")
        .task { await model.loadDashboard() }
        .confirmationDialog(
            "시스템 작업",
            isPresented: Binding(get: { confirmPower != nil }, set: { if !$0 { confirmPower = nil } })
        ) {
            Button(confirmPower == "reboot" ? "재부팅" : "전원 끄기", role: .destructive) {
                if confirmPower == "reboot" {
                    Task { await model.systemReboot() }
                } else if confirmPower == "shutdown" {
                    Task { await model.systemShutdown() }
                }
                confirmPower = nil
            }
            Button("취소", role: .cancel) { confirmPower = nil }
        } message: {
            Text(confirmPower == "reboot"
                 ? "TrueNAS를 재부팅할까요? 실행 중인 앱/서비스가 중단됩니다."
                 : "TrueNAS 전원을 끌까요? 실행 중인 앱/서비스가 중단됩니다.")
        }
    }
}

@ViewBuilder
func severityIcon(_ severity: String?) -> some View {
    switch (severity ?? "").uppercased() {
    case "CRITICAL", "ALERT":
        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
    case "WARNING":
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    default:
        Image(systemName: "info.circle.fill").foregroundStyle(.blue)
    }
}

// MARK: - 풀 행

struct PoolRow: View {
    let pool: Pool

    private var usedPercent: Double {
        Fmt.percentString(used: pool.allocated, total: pool.size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusDot(pool.status)
                Text(pool.name ?? "-").bold()
                Text(pool.status ?? "").mono().foregroundStyle(.secondary)
                Spacer()
                if pool.healthy == false {
                    Label("비정상", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Text("\(Fmt.bytes(pool.allocated)) / \(Fmt.bytes(pool.size))")
                    .mono()
                    .foregroundStyle(.secondary)
            }
            UsageBar(percent: usedPercent)
            HStack {
                Text("\(String(format: "%0.1f%%", usedPercent)) 사용")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let frag = pool.fragmentation {
                    Text("단편화 \(String(format: "%0.0f%%", frag))").font(.caption).foregroundStyle(.secondary)
                }
                if let trim = pool.autotrim, trim != "OFF" {
                    Text("autotrim: \(trim)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let free = pool.free {
                    Text("남음 \(Fmt.bytes(free))").font(.caption).mono().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusDot(_ status: String?) -> some View {
        let color: Color = {
            switch (status ?? "").uppercased() {
            case "ONLINE": return .green
            case "DEGRADED": return .orange
            case "FAULTED", "OFFLINE", "REMOVED", "UNAVAIL": return .red
            default: return .gray
            }
        }()
        Circle().fill(color).frame(width: 10, height: 10)
    }
}

// MARK: - 공용 컴포넌트

struct UsageBar: View {
    let percent: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(6, geo.size.width * percent / 100))
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return .blue
    }
}

extension Text {
    func mono() -> some View {
        font(.system(.caption, design: .monospaced))
    }
}

// 막대 대신 원형(도넛) 게이지로 램 사용량을 표시한다.
struct RingGauge: View {
    let percent: Double
    let label: String
    var diameter: CGFloat = 72

    private var clamped: Double { min(max(percent, 0), 100) }
    private var color: Color {
        if clamped >= 90 { return .red }
        if clamped >= 75 { return .orange }
        return .blue
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: max(6, diameter * 0.11))
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: max(6, diameter * 0.11), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%0.0f%%", clamped))
                    .font(.system(size: max(12, diameter * 0.19), weight: .semibold, design: .rounded))
                    .mono()
            }
            .frame(width: diameter, height: diameter)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 풀 상세 목록

struct PoolsView: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded: Set<String> = []

    var body: some View {
        List {
            ForEach(model.pools, id: \.name) { pool in
                VStack(alignment: .leading, spacing: 8) {
                    PoolRow(pool: pool)
                    if let topo = pool.topology, hasDisks(topo) {
                        diskSection(topo, poolName: pool.name ?? "")
                            .padding(.leading, 14)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let name = pool.name ?? ""
                    if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
                }
            }
            if model.pools.isEmpty && !model.isBusy {
                Text("풀 데이터가 없습니다. 새로고침을 눌러 주세요.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("스토리지 풀")
        .toolbar { ToolbarItem { RefreshToolbar { Task { await model.loadPools() } } } }
        .task { await model.loadPools() }
    }

    private func hasDisks(_ topo: PoolTopology) -> Bool {
        !(topo.data ?? []).isEmpty
    }

    @ViewBuilder
    private func diskSection(_ topo: PoolTopology, poolName: String) -> some View {
        if expanded.contains(poolName) {
            VStack(alignment: .leading, spacing: 4) {
                Text("디스크 (vdev)").font(.caption).bold().foregroundStyle(.secondary)
                ForEach(topo.data ?? [], id: \.name) { disk in
                    HStack {
                        Image(systemName: "internaldrive")
                        Text(disk.name ?? "-").mono()
                        if let st = disk.status {
                            Text(st).mono().foregroundStyle(st.uppercased() == "ONLINE" ? .green : .orange)
                        }
                        if let path = disk.path {
                            Text(path).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
