import SwiftUI

// MARK: - 전체 NAS 현황 (사이드바 맨 상단: 저장된 NAS들의 사용량을 한 화면에서)

struct NasOverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("저장된 NAS \(model.nasOverview.count) 개")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("연결 설정 열기") { model.nav = .settings }
                    RefreshToolbar { Task { await model.loadNasOverview() } }
                }
                if model.nasOverview.isEmpty && !model.isBusy {
                    Text("새로고침을 눌러 각 NAS 상태를 확인하세요.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.nasOverview.enumerated()), id: \.offset) { _, row in
                    NasOverviewCard(row: row)
                }
            }
            .padding(16)
        }
        .navigationTitle("NAS 현황")
        .task { await model.loadNasOverview() }
    }
}

private struct NasOverviewCard: View {
    @EnvironmentObject var model: AppModel
    let row: [String: Any]

    private var name: String { Fmt.anyString(row["name"]) }
    private var isActive: Bool { name == model.activeProfileName }
    private var ok: Bool { (row["ok"] as? Bool) == true }
    private var pools: [[String: Any]] { (row["pools"] as? [[String: Any]]) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: ok ? "server.rack" : "server.rack.badge.xmark")
                    .foregroundColor(ok ? .green : .red)
                Text(name).font(.title3).bold()
                if isActive { Text("현재 연결").font(.caption).padding(2)
                    .background(Capsule().fill(Color.blue.opacity(0.15))).foregroundColor(.blue) }
                Spacer()
                if !isActive {
                    Button("이 NAS로 전환") { switchTo() }
                } else {
                    Button("설정 열기") { model.nav = .settings }
                }
            }
            if ok {
                Text("버전 \(Fmt.anyString(row["version"])) · 활성 알림 \((row["alerts"] as? Int) ?? 0) 건")
                    .font(.caption).foregroundStyle(.secondary)
                if pools.isEmpty {
                    Text("풀 없음").font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    ForEach(Array(pools.enumerated()), id: \.offset) { _, pool in
                        let size = (pool["size"] as? Int) ?? 0
                        let used = (pool["allocated"] as? Int) ?? 0
                        let pct = size > 0 ? Double(used) / Double(size) * 100 : 0
                        RingGauge(percent: pct, label: Fmt.anyString(pool["name"]), diameter: 84)
                    }
                }
            } else {
                Text("연결 실패 — 연결 설정에서 주소/키를 확인하세요.")
                    .font(.callout).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private func switchTo() {
        model.selectProfile(name)
        model.nav = .dashboard
        Task { await model.loadDashboard() }
    }
}

// MARK: - 부팅 환경 (웹 대시보드의 Boot 화면 동급)

struct BootEnvsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDestroy: [String: Any]? = nil
    @State private var confirmActivate: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("부팅 환경 \(model.bootEnvs.count) 개").foregroundStyle(.secondary)
                    Spacer()
                    RefreshToolbar { Task { await model.loadBootEnvs() } }
                }
                if model.bootEnvs.isEmpty && !model.isBusy {
                    Text("부팅 환경 데이터가 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(Array(model.bootEnvs.enumerated()), id: \.offset) { _, env in
                    let id = Fmt.anyString(env["id"])
                    let activated = (env["activated"] as? String)?.uppercased().contains("ACTIVATED") ?? false
                    let keep = (env["keep"] as? Bool) == true
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if activated {
                                Label("부팅 활성", systemImage: "checkmark.seal.fill").font(.callout)
                            }
                            Spacer()
                            Text(Fmt.anyString(env["dataset"])).font(.caption).mono()
                        }
                        HStack(spacing: 10) {
                            Text("생성 " + (Fmt.epochString(env["created"]) ?? "-"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("용량 " + Fmt.anyString(env["used"]))
                                .font(.caption).foregroundStyle(.secondary)
                            if keep {
                                Text("유지").font(.caption).foregroundColor(.green)
                            }
                            Spacer()
                            if !activated {
                                Button("활성화") { confirmActivate = id }
                                    .confirmationDialog(
                                        "\(Fmt.anyString(env["dataset"])) 을(를) 다음 부팅에 활성화할까요? 현재 실행 중 시스템에는 영향 없음",
                                        isPresented: Binding(get: { confirmActivate != nil },
                                                             set: { if !$0 { confirmActivate = nil } })
                                    ) {
                                        Button("활성화") {
                                            let target = confirmActivate
                                            confirmActivate = nil
                                            if let target { Task { await model.activateBootEnv(id: target) } }
                                        }
                                        Button("취소", role: .cancel) { confirmActivate = nil }
                                    }
                            }
                            Button(keep ? "유지 해제" : "유지") { Task { await model.keepBootEnv(id: id, keep: !keep) } }
                            Button("삭제", role: .destructive) { confirmDestroy = env }
                                .confirmationDialog(
                                    "'\(id)' 부팅 환경 삭제",
                                    isPresented: Binding(get: { confirmDestroy != nil },
                                                         set: { if !$0 { confirmDestroy = nil } })
                                ) {
                                    Button("삭제", role: .destructive) {
                                        let target = confirmDestroy
                                        confirmDestroy = nil
                                        if let target { Task { await model.destroyBootEnv(id: Fmt.anyString(target["id"])) } }
                                    }
                                    Button("취소", role: .cancel) { confirmDestroy = nil }
                                } message: {
                                    Text("부팅 환경 삭제는 되돌릴 수 없습니다.")
                                }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
                }
            }
            .padding(16)
        }
        .navigationTitle("부팅 환경")
        .task { await model.loadBootEnvs() }
    }
}

// MARK: - 시스템 업데이트

struct SystemUpdateView: View {
    @EnvironmentObject var model: AppModel
    @State private var showRunConfirm = false

    var body: some View {
        Form {
            Section("상태") {
                if model.updateStatus.isEmpty {
                    Text("아직 확인하지 않았습니다.").foregroundStyle(.secondary)
                    Button("업데이트 확인") { Task { await model.loadUpdateStatus() } }
                } else {
                    Text(summary).font(.callout)
                    Button("다시 확인") { Task { await model.loadUpdateStatus() } }
                    Button("업데이트 설치(재부팅)", role: .destructive) { showRunConfirm = true }
                        .confirmationDialog("지금 업데이트를 설치하면 시스템이 재부팅됩니다.", isPresented: $showRunConfirm) {
                            Button("설치", role: .destructive) { Task { await model.runSystemUpdate() } }
                            Button("취소", role: .cancel) {}
                        } message: {
                            Text("실행 중인 서비스/앱은 중단됩니다.")
                        }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("시스템 업데이트")
        .task {
            if model.updateStatus.isEmpty { await model.loadUpdateStatus() }
        }
    }

    private var summary: String {
        let s = model.updateStatus
        var lines: [String] = []
        if let method = s["method"] { lines.append("메서드: \(Fmt.anyString(method))") }
        if let train = s["train"] { lines.append("트레인: \(Fmt.anyString(train))") }
        if let updated = s["updated"] as? [String: Any] {
            lines.append("최근 업데이트: \(Fmt.epochString(updated["created"]) ?? Fmt.anyString(updated["created"]))")
        }
        let nv = s["new_version"]
        if nv == nil || Fmt.anyString(nv).lowercased().contains("no update") {
            lines.append("새 버전: 없음 (최신)")
        } else if let nvDict = nv as? [String: Any] {
            lines.append("새 버전: \(Fmt.anyString(nvDict["version"] ?? nvDict["sequence"] ?? nvDict["description"]))")
        } else {
            lines.append("새 버전 확인됨")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 감사 로그

struct AuditView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("\(model.auditRows.count) 건 (최근 100건, MIDDLEWARE)").foregroundStyle(.secondary)
                    Spacer()
                    RefreshToolbar { Task { await model.loadAudit() } }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                if model.auditRows.isEmpty && !model.isBusy {
                    Text("감사 로그가 없습니다.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                ForEach(Array(model.auditRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(Fmt.epochString(row["timestamp"]) ?? "-").mono()
                            Text(Fmt.anyString(row["username"])).bold()
                            Text(Fmt.anyString(row["address"])).mono().foregroundStyle(.secondary)
                            Spacer()
                            Text((row["success"] as? Bool) == false ? "실패" : "성공")
                                .font(.caption)
                                .foregroundColor((row["success"] as? Bool) == false ? .red : .green)
                        }
                        Text("\(Fmt.anyString(row["service"])) · \(Fmt.anyString(row["event"]))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    Divider().opacity(0.4)
                }
            }
        }
        .navigationTitle("감사 로그")
        .task { await model.loadAudit() }
    }
}

// MARK: - 앱 카탈로그

struct AppCatalogView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""

    private var filtered: [[String: Any]] {
        let rows = model.catalogApps
        let q = search.lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            Fmt.anyString(row["name"]).lowercased().contains(q)
                || Fmt.anyString(row["description"]).lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("앱 이름/설명 검색", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Text("\(filtered.count) / \(model.catalogApps.count) 개").foregroundStyle(.secondary)
                Spacer()
                RefreshToolbar { Task { await model.loadCatalog() } }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Text("설치는 앱별 설정 스키마가 달라 TrueNAS 웹 UI를 권장합니다. 이 화면은 카탈로그 검색·버전 확인용입니다.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, app in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(Fmt.anyString(app["name"])).bold()
                                Text(Fmt.anyString(app["latest_human_version"])).mono().foregroundStyle(.secondary)
                                if let cats = app["categories"] as? [String], !cats.isEmpty {
                                    Text(cats.prefix(3).joined(separator: ", ")).font(.caption).foregroundStyle(.blue)
                                }
                                Spacer()
                            }
                            Text(Fmt.anyString(app["description"])).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .navigationTitle("앱 카탈로그")
        .task {
            if model.catalogApps.isEmpty { await model.loadCatalog() }
        }
    }
}

// MARK: - API 키

struct ApiKeysView: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""
    @State private var newUsername = ""
    @State private var showAdd = false
    @State private var showKeyOnce = false
    @State private var issuedKey = ""
    @State private var revokeTarget: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.apiKeys.count) 개").foregroundStyle(.secondary)
                Spacer()
                Button("키 생성") { showAdd = true }
                RefreshToolbar { Task { await model.loadApiKeys() } }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.apiKeys.enumerated()), id: \.offset) { _, key in
                        let id = Fmt.anyString(key["id"])
                        let revoked = (key["revoked"] as? Bool) == true
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(Fmt.anyString(key["name"])).bold()
                                    Text(Fmt.anyString(key["username"])).foregroundStyle(.secondary)
                                    if revoked { Text("폐기됨").font(.caption).foregroundColor(.gray) }
                                }
                                Text("생성 " + (Fmt.epochString(key["created_at"]) ?? "-"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !revoked {
                                Button("폐기", role: .destructive) { revokeTarget = id }
                                    .confirmationDialog(
                                        "API 키를 폐기할까요? 이 키로 연결된 기기는 더 이상 접속할 수 없습니다.",
                                        isPresented: Binding(get: { revokeTarget != nil },
                                                             set: { if !$0 { revokeTarget = nil } })
                                    ) {
                                        Button("폐기", role: .destructive) {
                                            let target = revokeTarget
                                            revokeTarget = nil
                                            if let target { Task { await model.revokeApiKey(id: target) } }
                                        }
                                        Button("취소", role: .cancel) { revokeTarget = nil }
                                    }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .navigationTitle("API 키")
        .task { await model.loadApiKeys() }
        .sheet(isPresented: $showAdd) {
            VStack(alignment: .leading, spacing: 14) {
                Text("API 키 생성").font(.title3).bold()
                TextField("키 이름", text: $newName)
                TextField("발급 사용자명 (예: truenas_admin)", text: $newUsername)
                HStack {
                    Spacer()
                    Button("취소") { showAdd = false }
                    Button("생성") {
                        let name = newName
                        let user = newUsername
                        showAdd = false
                        Task {
                            if let key = await model.createApiKey(name: name, username: user) {
                                issuedKey = key
                                showKeyOnce = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty || newUsername.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
        .sheet(isPresented: $showKeyOnce) {
            VStack(alignment: .leading, spacing: 14) {
                Text("발급된 키 (지금만 표시)").font(.title3).bold()
                Text(issuedKey)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("복사") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(issuedKey, forType: .string)
                        #endif
                    }
                    Button("닫기") { showKeyOnce = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 480)
        }
    }
}

// MARK: - 네트워크 요약

struct NetworkSummaryView: View {
    @EnvironmentObject var model: AppModel
    @State private var report = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("인터페이스 IP / 기본 게이트웨이 / DNS").foregroundStyle(.secondary)
                Spacer()
                RefreshToolbar {
                    Task { report = await model.networkReport() }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ScrollView {
                Text(report.isEmpty ? "새로고침을 누르세요." : report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .navigationTitle("네트워크 요약")
        .task {
            if report.isEmpty { report = await model.networkReport() }
        }
    }
}
