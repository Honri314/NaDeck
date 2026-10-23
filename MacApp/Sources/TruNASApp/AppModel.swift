import SwiftUI

// MARK: - 앱 모델

@MainActor
final class AppModel: ObservableObject {
    /// 다중 TrueNAS 프로파일 저장소.
    /// config는 활성 프로파일의 작업 사본(설정 화면에서 편집)이고,
    /// 프로파일 전환/저장 시 이 사본을 ProfileStore에 반영한다.
    @Published var profiles: [NasProfile] = []
    @Published var activeProfileName: String = "" {
        didSet { persistProfiles() }
    }

    /// 편집 중인 config가 바뀔 때마다 활성 프로파일에 즉시 반영(자동 저장).
    @Published var config: TruenasConfig = TruenasConfig() {
        didSet { persistProfiles() }
    }

    init() {
        let store = ConfigStore.load()
        profiles = store.profiles
        config = store.profiles.first(where: { $0.name == store.activeName })?.asConfig()
            ?? store.profiles.first?.asConfig()
            ?? TruenasConfig()
        activeProfileName = store.profiles.first(where: { $0.name == store.activeName })?.name
            ?? store.profiles.first?.name
            ?? ""
        // 초기화 중 didSet이 불필요하게 다시 저장하는 것은 무해(같은 값)하므로 그대로 둔다.
    }

    /// 편집 중인 config가 바뀔 때마다 활성 프로파일에 즉시 반영(자동 저장).
    /// 이전의 ConfigStore.save(config)와 같은 효과지만 다중 프로파일 구조로 저장한다.
    private func persistProfiles() {
        var store = ProfileStore(activeName: activeProfileName, profiles: profiles)
        if let index = store.profiles.firstIndex(where: { $0.name == activeProfileName }) {
            store.profiles[index] = NasProfile(name: activeProfileName, from: config)
        } else if !activeProfileName.isEmpty {
            store.profiles.append(NasProfile(name: activeProfileName, from: config))
        }
        ConfigStore.save(store)
    }

    /// 언어의 단일 상태 소스: UI에서 이 값을 바꾸면 전역 저장소에 즉시 반영된다.
    /// (뷰별 @State와 전역 값이 서로 덮어쓰던 반대 동작 버그 수정)
    @Published var language: String = AppLanguage.current {
        didSet { AppLanguage.current = language }
    }

    @Published var nav: NavItem = .dashboard
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var isError = false
    /// 상태 메시지가 바뀔 때마다 증가. 오버레이는 이 값이 바뀔 때마다 2초 타이머를 다시 시작한다.
    @Published var statusSeq = 0

    // 대시보드
    @Published var systemInfo: SystemInfo?
    @Published var pools: [Pool] = []
    @Published var alerts: [Alert] = []
    @Published var cpuUsage: Double?
    @Published var coreUsages: [(name: String, percent: Double)] = []   // cpuN 별 %
    @Published var diskTemps: [String: Double] = [:]                    // 디스크 온도(섭씨)

    // 웹 대시보드 대응 확장 데이터
    @Published var bootEnvs: [[String: Any]] = []       // 부팅 환경
    @Published var apiKeys: [[String: Any]] = []        // API 키
    @Published var catalogApps: [[String: Any]] = []    // 앱 카탈로그(465여 개)
    @Published var auditRows: [[String: Any]] = []      // 감사 로그
    @Published var updateStatus: [String: Any] = [:]    // /update/status
    @Published var nasOverview: [[String: Any]] = []    // 전체 NAS 현황(프로파일별 요약)
    @Published var updateVersions: [Any] = []           // /update/available_versions
    @Published var memoryUsage: [String: Double] = [:]

    // 공유
    @Published var smbShares: [SMBShare] = []
    @Published var nfsShares: [NFSShare] = []

    // 스냅샷
    @Published var snapshots: [Snapshot] = []
    @Published var datasets: [Dataset] = []
    @Published var replications: [ReplicationTask] = []

    // 사용자
    @Published var users: [NasUser] = []

    var client: TruenasClient? {
        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty else { return nil }
        return TruenasClient(config: config)
    }

    var isConfigured: Bool { client != nil }

    private func run(_ label: String, _ block: (TruenasClient) async throws -> Void) async {
        guard let client = client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await block(client)
            statusMessage = T("\(label) 완료", "\(label) completed")
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
        statusSeq += 1
    }

    // MARK: 연결 테스트

    func testConnection() async {
        await run(T("연결 테스트", "Connection test")) { client in
            let info: SystemInfo = try await client.get("/system/info")
            self.systemInfo = info
        }
    }

    /// 단계별 연결 진단: 주소 해석 -> API 키 요약 -> 실제 서버 응답
    func diagnose() async -> [String] {
        guard let client = client else {
            return [T("주소와 API 키를 먼저 입력하세요.", "Enter the address and API key first.")]
        }
        var lines: [String] = []

        let resolved = TruenasClient.resolveBaseURL(config.baseURL, config.port)
        lines.append(T("단계 1 - 해석된 주소: ", "Step 1 - resolved URL: ") + resolved)

        let key = config.apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if key.count > 8 {
            let head = key.prefix(4)
            let tail = key.suffix(4)
            lines.append(T("단계 2 - API 키: ", "Step 2 - API key: ")
                + "\(head)...\(tail) "
                + T("(길이 \(key.count))", "(length \(key.count))"))
        } else {
            lines.append(T("단계 2 - API 키: (입력값이 너무 짧습니다 - 웹 UI Copy 버튼으로 전체 키를 붙여넣었는지 확인)",
                           "Step 2 - API key: (too short - paste the full key copied via the web UI Copy button)"))
        }

        lines.append(T("단계 3 - 서버 요청 시도 중... (/system/info)",
                       "Step 3 - contacting server... (/system/info)"))
        do {
            let info: SystemInfo = try await client.get("/system/info")
            lines.append(T("성공: ", "OK: ")
                + "\(info.hostname ?? "?") (\(info.version ?? "?")) "
                + T("- 인증 정상", "- authentication OK"))
        } catch TruenasError.http(let code, let body) {
            // 서버 응답 코드와 원문을 그대로 표시해 원인 판별을 돕는다
            lines.append(T("실패: 서버 응답 코드 ", "FAILED: HTTP status ") + "\(code)")
            if !body.isEmpty {
                lines.append(T("서버 원문: ", "Server response: ") + body)
            }

            // 401/403이면 인증 방식별 폴백 실험(X-API-Key/Bearer/Basic)
            if code == 401 || code == 403 {
                lines.append(T("- 인증 방식별 자동 실험을 시작합니다...", "- Trying alternate auth methods..."))
                let variants: [(AuthMode, String)] = [
                    (.apiKey, "X-API-Key"),
                    (.bearer, "Bearer"),
                    (.basic, "Basic"),
                ]
                var found: AuthMode?
                for (candidate, label) in variants {
                    let username = (candidate == .basic) ? (config.basicUser ?? "") : nil
                    if candidate == .basic && (username ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                        lines.append(T("- 인증 방식 Basic: (사용자 이름 미입력 - 건너뜀)",
                                       "- Auth Basic: (no username - skipped)"))
                        continue
                    }
                    let (status, resBody) = await client.probeAuth(candidate, username: username)
                    if (200..<300).contains(status) {
                        lines.append(T("- 인증 방식 ", "- Auth ") + label
                            + T(" -> HTTP ", " -> HTTP ") + "\(status) "
                            + T("- 성공! 이 방식을 저장합니다.", "- SUCCESS! Saving this method."))
                        found = candidate
                        break
                    } else {
                        lines.append(T("- 인증 방식 ", "- Auth ") + label
                            + T(" -> HTTP ", " -> HTTP ") + "\(status) (\(resBody))")
                    }
                }
                if let winner = found {
                    // 발견한 인증 방식을 저장해 이후 연결에 자동 사용한다
                    config.authMode = winner.rawValue
                    persistProfiles()
                    if let info: SystemInfo = try? await client.get("/system/info") {
                        lines.append(T("재연결 성공: ", "Reconnect OK: ")
                            + "\(info.hostname ?? "?") (\(info.version ?? "?"))")
                        self.systemInfo = info
                    }
                    lines.append(T("이제 '연결 저장'을 누르면 이 인증 방식으로 계속 사용됩니다.",
                                   "Press 'Save' to keep using this auth method."))
                } else {
                    lines.append(T("- 모든 인증 방식 실패. 키를 재발급(Copy 버튼)하거나,\n  Basic 인증용 TrueNAS 사용자 이름을 입력하고 다시 진단하세요.",
                                   "- All auth variants failed. Re-issue the key (Copy button) or set your TrueNAS username for Basic auth."))
                }
            } else {
                lines.append(T("도움말: 본 프로그램은 복사한 키를 자동 정리해 전송합니다. 원문에 'API key invalid'가 있으면 키 값 자체가 거부된 것입니다.",
                               "Tip: if the server response says 'API key invalid', the key value itself is being rejected."))
            }
        } catch {
            lines.append(T("실패: ", "FAILED: ") + error.localizedDescription)
            lines.append(T("도움말: 주소/포트, TrueNAS와 이 기기가 같은 네트워크(또는 테일스케일)에 있는지,", "Tip: check address/port, network reachability (LAN or Tailscale),"))
            lines.append(T("키를 웹 UI Copy 버튼으로 복사했는지 순서대로 확인하세요.", "and that the key was copied with the web UI Copy button."))
        }
        return lines
    }

    // MARK: 대시보드

    func loadDashboard() async {
        await run("대시보드 새로고침") { client in
            async let info: SystemInfo = client.get("/system/info")
            async let pools: [Pool] = client.getArray("/pool")
            self.systemInfo = try await info
            self.pools = try await pools
            self.alerts = ((try? await client.getArray("/alert/list") as [Alert]) ?? [])
                .filter { $0.dismissed != true }

            // CPU/메모리는 "선택 데이터": 구버전(24.x)의 /system/cpu, /system/memory를
            // 먼저 시도하고, 25.10 처럼 REST에 없으면 /reporting/get_data로 폴백 계산한다.
            // 실패해도 대시보드 전체가 죽지 않는다.
            var cpu: Double? = nil
            if let cpus: [CPUStat] = try? await client.getArray("/system/cpu"),
               let samples = cpus.first?.data,
               let last = samples.last.map({ $0 / 100 }) {
                cpu = min(max(last, 0), 100)
            } else {
                cpu = await Self.cpuFromReporting(client)
            }
            self.cpuUsage = cpu
            self.coreUsages = await Self.fetchCoreUsages(client)
            self.diskTemps = await Self.fetchDiskTemps(client)

            var mem: [String: Double]
            if let m = try? await client.get("/system/memory") as MemoryUsage {
                mem = m.usage
            } else {
                mem = await Self.usageFromReporting(client)
            }
            self.memoryUsage = mem
        }
    }

    // MARK: reporting/get_data 폴백 (25.10 REST 제거 대상 엔드포인트 대체)

    private static func reportValue(_ obj: Any) -> Double? {
        if let d = obj as? Double { return d }
        if let i = obj as? Int { return Double(i) }
        if let s = obj as? String { return Double(s) }
        return nil
    }

    /// reporting/get_data 응답 -> 컴포넌트 list로 정규화
    private static func reportingComponents(_ obj: Any) -> [[String: Any]] {
        if let list = obj as? [[String: Any]] { return list }
        if let single = obj as? [String: Any] { return [single] }
        return []
    }

    /// 최신 샘플을 [시리즈명: 값] 사전으로 반환.
    /// v25.10 문서 기준 data는 딕셔너리 배열이며, aggregations.mean도 사용 가능.
    /// 구형(리스트 행 + legend) 형식도 함께 지원한다.
    private static func reportingSample(_ comp: [String: Any]) -> [String: Any] {
        guard let data = comp["data"] as? [Any], !data.isEmpty else {
            if let aggs = comp["aggregations"] as? [String: Any],
               let mean = aggs["mean"] as? [String: Any], !mean.isEmpty {
                return mean
            }
            return [:]
        }
        let last = data[data.count - 1]
        if let dict = last as? [String: Any] { return dict }
        let legend = comp["legend"] as? [String] ?? []
        if let row = last as? [Any], !legend.isEmpty {
            var map: [String: Any] = [:]
            for (i, name) in legend.enumerated() where i < row.count { map[name] = row[i] }
            return map
        }
        return [:]
    }

    /// 시리즈 키 매칭: 키 마지막 세그먼트(예: "cpu.user" -> "user")로 찾는다.
    private static func pickSeries(_ sample: [String: Any], _ want: String) -> [Double] {
        var out: [Double] = []
        for (k, v) in sample {
            let suffix = k.split(separator: ".").last.map(String.init)?.lowercased() ?? k.lowercased()
            if suffix == want.lowercased(), let n = reportValue(v) {
                out.append(n)
            }
        }
        return out
    }

    private static func cpuFromReporting(_ client: TruenasClient) async -> Double? {
        // v25.10 실측: cpu 그래프 시리즈 = [time, cpu(전체 %), cpu0..N(코어별 %)]
        guard let obj = try? await client.postAny("/reporting/get_data",
                                                 ["graphs": [["name": "cpu"]]]) else { return nil }
        for comp in reportingComponents(obj) where (comp["name"] as? String) == "cpu" {
            let sample = reportingSample(comp)
            guard !sample.isEmpty else { continue }
            // 전체 시리즈('cpu')가 있으면 그 값을 그대로 사용한다.
            let overall = pickSeries(sample, "cpu")
            if !overall.isEmpty {
                var pct = overall.last ?? 0
                if let maxRaw = overall.max(), maxRaw <= 1.0 {
                    pct *= 100
                }
                return min(max(pct, 0), 100)
            }
            // 구형 스키마 호환(user/system/idle 시리즈)
            var samples: [Double] = []
            var rawValues: [Double] = []
            let users = pickSeries(sample, "user")
            let systems = pickSeries(sample, "system")
            let idles = pickSeries(sample, "idle")
            if !users.isEmpty || !systems.isEmpty {
                let count = max(users.count, systems.count)
                for i in 0..<count {
                    let u = i < users.count ? users[i] : (users.last ?? 0)
                    let s = i < systems.count ? systems[i] : (systems.last ?? 0)
                    samples.append(u + s)
                }
                rawValues.append(contentsOf: users + systems)
            } else if !idles.isEmpty {
                samples = idles.map { 100 - $0 }
                rawValues.append(contentsOf: idles)
            }
            if !samples.isEmpty {
                var pct = samples.reduce(0, +) / Double(samples.count)
                // 값이 0~1 분율로 오는 경우 백분율로 보정
                if let maxRaw = rawValues.max(), maxRaw > 0, maxRaw <= 1.0 {
                    pct *= 100
                }
                return min(max(pct, 0), 100)
            }
        }
        return nil
    }

    // MARK: 코어별 사용률/디스크 온도 조회

    private static func fetchCoreUsages(_ client: TruenasClient) async -> [(name: String, percent: Double)] {
        guard let obj = try? await client.postAny("/reporting/get_data",
                                                 ["graphs": [["name": "cpu"]]]) else { return [] }
        for comp in reportingComponents(obj) where (comp["name"] as? String) == "cpu" {
            var cores = coreUsages(from: comp)
            // 0~1 분율일 수 있는 구버전 대비: 전체 값이 1 이하면 % 보정
            let maxVal = cores.map { $0.percent }.max() ?? 0
            if maxVal <= 1.0 {
                cores = cores.map { ($0.name, $0.percent * 100) }
            }
            if !cores.isEmpty { return cores }
        }
        return []
    }

    private static func fetchDiskTemps(_ client: TruenasClient) async -> [String: Double] {
        guard let obj = try? await client.postAny("/disk/temperatures", [String: Any]()) else { return [:] }
        return temps(from: obj)
    }

    /// cpu 그래프의 마지막 행(legend 순서 cpu0..cpuN)을 코어별 % 로 반환
    static func coreUsages(from component: [String: Any]) -> [(name: String, percent: Double)] {
        guard let data = component["data"] as? [Any], !data.isEmpty,
              let legend = component["legend"] as? [String] else { return [] }
        let last = data[data.count - 1]
        guard let row = last as? [Any], row.count == legend.count else { return [] }
        var out: [(String, Double)] = []
        for (i, key) in legend.enumerated() where i < row.count {
            let name = String(key)
            guard name.range(of: "^cpu\\d+$", options: .regularExpression) != nil,
                  let v = reportValue(row[i]) else { continue }
            out.append((name, min(max(v, 0), 100)))
        }
        out.sort { $0.0 < $1.0 }
        return out
    }

    /// POST /disk/temperatures 응답을 [장치명: 섭씨] 로 정규화
    static func temps(from obj: Any) -> [String: Double] {
        guard let dict = obj as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, v) in dict {
            if let n = reportValue(v) { out[k] = n }
        }
        return out
    }

    private static func usageFromReporting(_ client: TruenasClient) async -> [String: Double] {
        // v25.10 실측: memory 그래프 시리즈 = [time, available(바이트)].
        // 전체 크기는 /system/info 의 physmem 으로 구한다.
        var physmem: Double?
        if let info: SystemInfo = try? await client.get("/system/info") {
            physmem = info.physmem
        }
        guard let obj = try? await client.postAny("/reporting/get_data",
                                                 ["graphs": [["name": "memory"]]]) else { return [:] }
        for comp in reportingComponents(obj) where (comp["name"] as? String) == "memory" {
            let sample = reportingSample(comp)
            guard !sample.isEmpty else { continue }
            let avail = pickSeries(sample, "available")
            if let a = avail.last, let total = physmem, total > 0 {
                let usedPct = min(max((1 - a / total) * 100, 0), 100)
                let labelUsed = T("사용", "used")
                let labelFree = T("남음", "free")
                return [labelUsed: usedPct, labelFree: 100 - usedPct]
            }
            // 구형 스키마 호환(used/free/total 시리즈)
            let used = pickSeries(sample, "used") + pickSeries(sample, "kern_used") + pickSeries(sample, "arc_size")
            let free = pickSeries(sample, "free") + pickSeries(sample, "kern_free")
            let total = pickSeries(sample, "total")
            var usedPct: Double?
            let u = used.reduce(0, +)
            let f = free.reduce(0, +)
            let t = total.first
            if !used.isEmpty && !free.isEmpty, u + f > 0 {
                usedPct = u / (u + f) * 100
            } else if let t, !free.isEmpty {
                usedPct = (t - f) / t * 100
            } else if let t, !used.isEmpty {
                usedPct = u / t * 100
            }
            if var pct = usedPct {
                let raw = used + free + total
                if let maxRaw = raw.max(), maxRaw > 0, maxRaw <= 1.0 {
                    pct *= 100
                }
                pct = min(max(pct, 0), 100)
                let labelUsed = T("사용", "used")
                let labelFree = T("남음", "free")
                return [labelUsed: pct, labelFree: 100 - pct]
            }
        }
        return [:]
    }

    // MARK: 풀

    func loadPools() async {
        await run("풀 새로고침") { client in
            self.pools = try await client.getArray("/pool")
        }
    }

    // MARK: 공유

    func loadShares() async {
        await run("공유 새로고침") { client in
            self.smbShares = try await client.getArray("/sharing/smb")
            self.nfsShares = try await client.getArray("/sharing/nfs")
        }
    }

    func addSMBShare(name: String, path: String, comment: String) async {
        await run("SMB 공유 추가") { client in
            var body: [String: Any] = ["name": name, "path": path]
            if !comment.isEmpty { body["comment"] = comment }
            _ = try await client.post("/sharing/smb", body: body) as SMBShare
            await self.loadSharesSilently(client)
        }
    }

    func deleteSMBShare(_ share: SMBShare) async {
        await run("SMB 공유 삭제") { client in
            try await client.delete("/sharing/smb/id/\(share.id)")
            await self.loadSharesSilently(client)
        }
    }

    func deleteNFSShare(_ share: NFSShare) async {
        await run("NFS 공유 삭제") { client in
            try await client.delete("/sharing/nfs/id/\(share.id)")
            await self.loadSharesSilently(client)
        }
    }

    private func loadSharesSilently(_ client: TruenasClient) async {
        smbShares = (try? await client.getArray("/sharing/smb")) ?? []
        nfsShares = (try? await client.getArray("/sharing/nfs")) ?? []
    }

    // MARK: 스냅샷

    func loadSnapshots() async {
        await run("스냅샷 새로고침") { client in
            // 스냅샷 목록은 필수, 복제/데이터셋은 선택 데이터(한 곳이 404여도 목록 전체가 안 비도록)
            self.snapshots = try await client.getArray("/pool/snapshot")
            self.datasets = (try? await client.getArray("/pool/dataset")) ?? []
            self.replications = (try? await client.getArray("/replication")) ?? self.replications
        }
    }

    func createSnapshot(dataset: String, name: String, recursive: Bool) async {
        await run("스냅샷 생성") { client in
            let _: Snapshot = try await client.post(
                "/pool/snapshot",
                body: ["dataset": dataset, "name": name, "recursive": recursive]
            )
            await self.loadSnapshotsSilently(client)
        }
    }

    func deleteSnapshot(_ snap: Snapshot) async {
        await run("스냅샷 삭제") { client in
            let enc = snap.name ?? ""
                .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
            try await client.delete("/pool/snapshot/id/\(enc)")
            await self.loadSnapshotsSilently(client)
        }
    }

    private func loadSnapshotsSilently(_ client: TruenasClient) async {
        snapshots = (try? await client.getArray("/pool/snapshot")) ?? []
        replications = (try? await client.getArray("/replication")) ?? []
    }

    // MARK: 사용자

    func loadUsers() async {
        await run("사용자 새로고침") { client in
            self.users = try await client.getArray("/user")
        }
    }

    func addUser(username: String, fullName: String, password: String, samba: Bool) async {
        await run("사용자 추가") { client in
            var body: [String: Any] = [
                "username": username,
                "password": password,
                "group_create": true,
            ]
            if !fullName.isEmpty { body["full_name"] = fullName }
            if samba { body["smb"] = true }
            _ = try await client.post("/user", body: body) as NasUser
            await self.loadUsersSilently(client)
        }
    }

    func deleteUser(_ user: NasUser) async {
        await run("사용자 삭제") { client in
            guard let id = user.id else { return }
            try await client.delete("/user/id/\(id)")
            await self.loadUsersSilently(client)
        }
    }

    private func loadUsersSilently(_ client: TruenasClient) async {
        users = (try? await client.getArray("/user")) ?? []
    }

    // MARK: - 프로파일 관리 (여러 TrueNAS 다중 관리)

    /// 활성 프로파일을 전환하고 해당 NAS 설정으로 데이터를 다시 불러온다.
    func selectProfile(_ name: String) {
        guard let profile = profiles.first(where: { $0.name == name }),
              name != activeProfileName else { return }
        activeProfileName = name
        config = profile.asConfig()
        // 이전 NAS의 캐시된 데이터를 전부 치운다.
        systemInfo = nil; pools = []; alerts = []
        cpuUsage = nil; memoryUsage = [:]
        coreUsages = []; diskTemps = [:]
        smbShares = []; nfsShares = []
        snapshots = []; datasets = []; replications = []
        users = []
        services = []; apps = []; vms = []; scrubs = []
        entities = [:]
        statusMessage = T("\(name) 연결로 전환했습니다. 대시보드에서 새로고침하세요.",
                          "Switched to \(name). Refresh the dashboard.")
        isError = false
        statusSeq += 1
    }

    func hasProfile(_ name: String) -> Bool {
        profiles.contains { $0.name == name }
    }

    /// 현재 편집 중인 설정을 프로파일로 저장(덮어쓰기).
    func saveCurrentProfile() {
        guard !activeProfileName.isEmpty else { return }
        let profile = NasProfile(name: activeProfileName, from: config)
        if let index = profiles.firstIndex(where: { $0.name == activeProfileName }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persistProfiles()
    }

    /// 현재 설정을 새 프로파일로 저장하고 그 이름으로 전환한다.
    /// 중복 이름이면 뒤에 번호를 붙인다.
    func saveNewProfile(name rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "새 연결" }
        var candidate = name
        var n = 2
        while hasProfile(candidate) {
            candidate = "\(name) (\(n))"
            n += 1
        }
        let profile = NasProfile(name: candidate, from: config)
        profiles.append(profile)
        activeProfileName = candidate
        return candidate
    }

    func deleteProfile(_ name: String) {
        profiles.removeAll { $0.name == name }
        if activeProfileName == name {
            activeProfileName = profiles.first?.name ?? ""
            config = profiles.first?.asConfig() ?? TruenasConfig()
            systemInfo = nil; pools = []; alerts = []
            cpuUsage = nil; memoryUsage = [:]
        coreUsages = []; diskTemps = [:]
        }
        persistProfiles()
    }

    // MARK: - 사양 기반 범용 엔티티 (카테고리 확장 기능)

    @Published var services: [[String: Any]] = []
    @Published var apps: [[String: Any]] = []
    @Published var vms: [[String: Any]] = []
    @Published var scrubs: [[String: Any]] = []
    @Published var entities: [String: [[String: Any]]] = [:]
    @Published var datasetOptions: [String] = []

    func loadServices() async {
        await run("서비스 새로고침") { client in
            self.services = try await client.getAnyList("/service")
        }
    }

    // v25.10: /service/start, /service/stop 본문 = 서비스 이름 문자열
    func toggleService(name: String, currentlyRunning: Bool) async {
        guard !name.isEmpty else { return }
        await run(currentlyRunning ? "서비스 중지" : "서비스 시작") { client in
            _ = try await client.postAny("/service/\(currentlyRunning ? "stop" : "start")", name)
            await self.loadServices()
        }
    }

    // v25.10: /service/restart 본문 = {service: 이름}
    func restartService(name: String) async {
        guard !name.isEmpty else { return }
        await run("서비스 재시작 \(name)") { client in
            _ = try await client.postAny("/service/restart", ["service": name])
            await self.loadServices()
        }
    }

    // MARK: 시스템 전원 (웹 대시보드 동급)

    func systemReboot() async {
        await run("시스템 재부팅") { client in
            _ = try await client.postAny("/system/reboot", ["reason": "NaDeck 앱에서 요청한 재부팅"])
        }
    }

    func systemShutdown() async {
        await run("시스템 종료") { client in
            _ = try await client.postAny("/system/shutdown", ["reason": "NaDeck 앱에서 요청한 종료"])
        }
    }

    // MARK: 스냅샷 롤백/클론 (웹 대시보드 동급)

    func rollbackSnapshot(id: String, recursive: Bool) async {
        await run("스냅샷 롤백") { client in
            var body: [String: Any] = ["id": id]
            if recursive { body["options"] = ["recursive": true] }
            _ = try await client.postAny("/pool/snapshot/rollback", body)
            await self.loadSnapshots()
        }
    }

    func cloneSnapshot(id: String, to dst: String) async {
        await run("스냅샷 클론") { client in
            _ = try await client.postAny("/pool/snapshot/clone",
                                        ["snapshot": id, "dataset_dst": dst])
            await self.loadSnapshots()
        }
    }

    // MARK: 앱(Applications)

    func loadApps() async {
        await run("앱 새로고침") { client in
            self.apps = try await client.getAnyList("/app")
        }
    }

    func appAction(_ app: [String: Any], action: String) async {
        let raw = Fmt.anyString(app["name"])
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? raw
        guard !encoded.isEmpty else { return }
        await run("앱 \(action)") { client in
            if action == "delete" {
                // v25.10: DELETE /app/id/<app_name>
                try await client.delete("/app/id/\(encoded)")
            } else if action == "upgrade" {
                // v25.10: POST /app/upgrade 본문 = {app_name, options?}
                _ = try await client.postAny("/app/upgrade", ["app_name": raw])
            } else {
                // v25.10: POST /app/<action> 본문 = 앱 이름 문자열
                _ = try await client.postAny("/app/\(action)", raw)
            }
            await self.loadApps()
        }
    }

    // MARK: 가상머신(VM)

    func loadVMs() async {
        await run("가상머신 새로고침") { client in
            self.vms = try await client.getAnyList("/vm")
        }
    }

    func vmAction(_ vm: [String: Any], action: String) async {
        guard let id = Fmt.toInt(vm["id"]) else { return }
        await run("VM \(action)") { client in
            if action == "delete" {
                // v25.10: DELETE /vm/id/<id>
                try await client.delete("/vm/id/\(id)")
            } else {
                // v25.10: POST /vm/id/<id>/<action>
                _ = try await client.postAny("/vm/id/\(id)/\(action)", [String: Any]())
            }
            await self.loadVMs()
        }
    }

    /// v25.10: POST /vm 으로 기본 VM 생성, 이후 /vm/device 로 장치 부착
    func createVM(name: String, vcpus: Int, memoryGB: Int, diskGB: Int,
                  pool: String, isoPath: String, nicAttach: String, autostart: Bool) async {
        await run("VM 생성") { client in
            // v25.10.7 스키마: DISK = {dtype, path(null 가능), type, create_zvol, zvol_name, zvol_volsize}
            var devices: [[String: Any]] = [
                ["dtype": "DISK",
                 "path": NSNull(),
                 "type": "AHCI",
                 "create_zvol": true,
                 "zvol_name": "\(pool)/\(name)-disk",
                 "zvol_volsize": diskGB * 1024 * 1024 * 1024],
            ]
            if !isoPath.isEmpty {
                devices.append(["dtype": "CDROM", "path": isoPath])
            }
            var nicAttrs: [String: Any] = ["dtype": "NIC", "type": "VIRTIO"]
            if !nicAttach.isEmpty { nicAttrs["nic_attach"] = nicAttach }
            devices.append(nicAttrs)
            let body: [String: Any] = [
                "name": name,
                "vcpus": vcpus,
                "cores": vcpus,
                "threads": 1,
                "memory": memoryGB * 1024,
                "autostart": autostart,
            ]
            // v25.10: POST /vm 은 장치 없는 기본 VM만 생성하고,
            // 장치는 POST /vm/device 로 하나씩 부착한다.
            let vm = try await client.postAny("/vm", body)
            guard let vmId = Fmt.toInt((vm as? [String: Any])?["id"]) else {
                throw TruenasError.clientMessage("VM 생성 응답에 id가 없어 장치를 부착하지 못했습니다.")
            }
            var order = 0
            for attrs in devices {
                _ = try await client.postAny("/vm/device",
                                            ["vm": vmId, "attributes": attrs, "order": order])
                order += 1
            }
            await self.loadVMs()
        }
    }

    func loadScrubs() async {
        await run("스크럽 작업 새로고침") { client in
            self.scrubs = try await client.getAnyList("/pool/scrub")
        }
    }

    func runScrub(id: Int) async {
        await run("스크럽 실행") { client in
            // v25.10: POST /pool/scrub/run 본문 = {name: 풀 이름}
            var poolName = ""
            for scrub in (try? await client.getAnyList("/pool/scrub")) ?? [] {
                if Fmt.toInt(scrub["id"]) == id {
                    poolName = Fmt.anyString((scrub["pool"] as? [String: Any])?["name"])
                    break
                }
            }
            guard !poolName.isEmpty else {
                throw TruenasError.clientMessage("스크럽 id \(id)에 해당하는 풀을 찾지 못했습니다.")
            }
            _ = try await client.postAny("/pool/scrub/run", ["name": poolName])
            await self.loadScrubs()
        }
    }

    func dismissAlert(id: String?) async {
        let uuidStr = id.map { "\($0)" } ?? ""
        guard !uuidStr.isEmpty else { return }
        await run("알림 무시") { client in
            // v25.10: POST /alert/dismiss 본문 = alert uuid 문자열
            _ = try await client.postAny("/alert/dismiss", uuidStr)
            await self.loadDashboard()
        }
    }

    // MARK: 편집(PUT) — 범용

    func updateEntity(_ spec: EntitySpec, _ row: [String: Any], fields: [String: Any]) async {
        await run("\(spec.title) 편집") { client in
            let raw = Fmt.anyString(row[spec.idField])
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? raw
            _ = try await client.putAny("\(spec.endpoint)/id/\(encoded)", fields)
            await self.refreshEntitySilently(spec)
        }
    }

    // MARK: 부팅 환경 (웹 대시보드 동급)

    func loadBootEnvs() async {
        await run("부팅 환경 새로고침") { client in
            self.bootEnvs = try await client.getAnyList("/boot/environment/query")
        }
    }

    func activateBootEnv(id: String) async {
        await run("부팅 환경 활성화") { client in
            _ = try await client.postAny("/boot/environment/activate", ["id": id])
            await self.loadBootEnvs()
        }
    }

    func destroyBootEnv(id: String) async {
        await run("부팅 환경 삭제") { client in
            _ = try await client.postAny("/boot/environment/destroy", ["id": id])
            await self.loadBootEnvs()
        }
    }

    func keepBootEnv(id: String, keep: Bool) async {
        await run(keep ? "부팅 환경 유지" : "유지 해제") { client in
            _ = try await client.postAny("/boot/environment/keep", ["id": id, "value": keep])
            await self.loadBootEnvs()
        }
    }

    // MARK: 전체 NAS 현황

    /// 등록된 모든 프로파일에 대해 각각 임시 클라이언트로 요약(버전/풀/알림)을 병렬 조회한다.
    /// 응답이 하나도 없는 NAS는 연결 불가 상태로 표시한다.
    func loadNasOverview() async {
        guard !profiles.isEmpty else { nasOverview = []; return }
        var results: [[String: Any]] = []
        await withTaskGroup(of: [String: Any].self) { group in
            for profile in profiles {
                let cfg = profile.asConfig()
                let name = profile.name
                group.addTask {
                    var row: [String: Any] = ["name": name]
                    let client = TruenasClient(config: cfg)
                    let info: SystemInfo? = try? await client.get("/system/info")
                    let pools: [Pool] = (try? await client.getArray("/pool")) ?? []
                    let alerts: [Alert] = (try? await client.getArray("/alert/list")) ?? []
                    if let info {
                        row["version"] = info.version ?? "-"
                    }
                    row["pools"] = pools.map { pool in
                        ["name": pool.name ?? "-", "status": pool.status ?? "-",
                         "size": pool.size ?? 0, "allocated": pool.allocated ?? 0,
                         "healthy": pool.healthy ?? false] as [String: Any]
                    }
                    row["alerts"] = alerts.filter { $0.dismissed != true }.count
                    row["ok"] = (info != nil) || !pools.isEmpty
                    return row
                }
            }
            for await row in group { results.append(row) }
        }
        nasOverview = results
    }

    // MARK: API 키

    func loadApiKeys() async {
        await run("API 키 새로고침") { client in
            self.apiKeys = try await client.getAnyList("/api_key")
        }
    }

    /// 생성이 성공하면 본문의 cleartext 키(1회 표시용)를 반환한다.
    func createApiKey(name: String, username: String) async -> String? {
        var key: String?
        await run("API 키 생성") { client in
            let out = try await client.postAny("/api_key", ["name": name, "username": username])
            key = (out as? [String: Any])?["key"] as? String
            self.apiKeys = (try? await client.getAnyList("/api_key")) ?? []
        }
        return key
    }

    func revokeApiKey(id: String) async {
        await run("API 키 폐기") { client in
            try await client.delete("/api_key/id/\(id)")
            self.apiKeys = (try? await client.getAnyList("/api_key")) ?? []
        }
    }

    // MARK: 앱 카탈로그 (auth 검색용)

    func loadCatalog() async {
        await run("카탈로그 새로고침") { client in
            let rows = try await client.getAnyList("/app/available")
            // readme 등 대형 필드 제외(대화상자는 name/버전/설명/카테고리만 사용)
            self.catalogApps = rows.map { row in
                var r: [String: Any] = [:]
                for k in ["name", "train", "latest_human_version", "latest_app_version",
                          "description", "categories", "location", "healthy", "support"]
                { if let v = row[k] { r[k] = v } }
                return r
            }
        }
    }

    // MARK: 감사 로그

    func loadAudit() async {
        await run("감사 로그 새로고침") { client in
            // 25.10.7 실측: services [] 는 500, limit 포함 + MIDDLEWARE 만 200
            var body: [String: Any] = ["services": ["MIDDLEWARE"]]
            body["query-options"] = ["limit": 100, "order_by": ["-timestamp"]]
            let obj = try await client.postAny("/audit/query", body)
            self.auditRows = (obj as? [[String: Any]]) ?? []
        }
    }

    // MARK: 시스템 업데이트

    func loadUpdateStatus() async {
        await run("업데이트 상태 확인") { client in
            self.updateStatus = (try? await client.getAny("/update/status") as? [String: Any]) ?? [:]
        }
    }

    func runSystemUpdate() async {
        await run("시스템 업데이트 실행") { client in
            _ = try await client.postAny("/update/run", ["reboot": true])
        }
    }

    /// 네트워크 요약 텍스트(요약 + 설정 조회)
    func networkReport() async -> String {
        var lines: [String] = []
        if let client = client {
            if let sum = try? await client.getAny("/network/general/summary") as? [String: Any] {
                if let ips = sum["ips"] as? [String: Any] {
                    for (iface, raw) in ips {
                        lines.append("인터페이스 \(iface): \(Fmt.anyString(raw))")
                    }
                }
                if let gates = sum["default_routes"] as? [Any], !gates.isEmpty {
                    lines.append("기본 게이트웨이: " + gates.map { Fmt.anyString($0) }.joined(separator: ", "))
                }
                if let ns = sum["nameservers"] as? [Any], !ns.isEmpty {
                    lines.append("DNS: " + ns.map { Fmt.anyString($0) }.joined(separator: ", "))
                }
            }
            if let cfg = try? await client.getAny("/network/configuration") as? [String: Any] {
                lines.append("호스트명: \(Fmt.anyString(cfg["hostname"])) / 도메인: \(Fmt.anyString(cfg["domain"]))")
            }
        }
        return lines.isEmpty ? "데이터 없음" : lines.joined(separator: "\n")
    }

    func loadEntity(_ spec: EntitySpec) async {
        await run("\(spec.title) 새로고침") { client in
            var rows = try await client.getAnyList(spec.endpoint)
            // 디스크 목록에는 POST /disk/temperatures 결과를 온도 열로 병합한다.
            if spec.endpoint == "/disk", !rows.isEmpty {
                let tempDict = Self.temps(from: (try? await client.postAny("/disk/temperatures", [String: Any]())) ?? [:])
                if !tempDict.isEmpty {
                    rows = rows.map { row in
                        var r = row
                        let name = Fmt.anyString(r["name"])
                        if let t = tempDict[name] { r["temperature"] = t }
                        return r
                    }
                }
            }
            self.entities[spec.key] = rows
        }
    }

    func refreshEntitySilently(_ spec: EntitySpec) async {
        guard let client = client else { return }
        entities[spec.key] = (try? await client.getAnyList(spec.endpoint)) ?? []
    }

    func deleteEntity(_ spec: EntitySpec, _ row: [String: Any]) async {
        await run("\(spec.title) 삭제") { client in
            let raw = row[spec.idField].map { "\($0)" } ?? ""
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? raw
            let base = spec.deleteBasePath ?? "\(spec.endpoint)/id/"
            try await client.delete("\(base)\(encoded)")
            await self.refreshEntitySilently(spec)
        }
    }

    func createEntity(_ spec: EntitySpec, fields: [String: Any]) async {
        await run("\(spec.title) 추가") { client in
            var body = spec.createDefaults
            for (key, value) in fields {
                if let s = value as? String {
                    if !s.isEmpty { body[key] = s }
                } else {
                    body[key] = value
                }
            }
            _ = try await client.postAny(spec.endpoint, body)
            await self.refreshEntitySilently(spec)
        }
    }

    func fetchDatasetNames() async -> [String] {
        guard let client = client else { return [] }
        let rows = (try? await client.getAnyList("/pool/dataset")) ?? []
        return rows
            .filter { (($0["type"] as? String) ?? "FILESYSTEM").uppercased() == "FILESYSTEM" }
            .compactMap { $0["name"] as? String }
            .filter { !$0.isEmpty }
            .sorted()
    }
}

// MARK: - 포맷 헬퍼

enum Fmt {
    static func bytes(_ value: Int?) -> String {
        guard let value, value > 0 else { return "0 B" }
        let units: [String] = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var v = Double(value)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: "%0.1f %@", v, units[i])
    }

    static func percentString(used: Int?, total: Int?) -> Double {
        guard let used, let total, total > 0 else { return 0 }
        return min(max(Double(used) / Double(total) * 100, 0), 100)
    }

    static func toInt(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let i64 as Int64: return Int(i64)
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    static func anyString(_ value: Any?) -> String {
        switch value {
        case nil: return "-"
        case let s as String: return s.isEmpty ? "-" : s
        case let b as Bool: return b ? "예" : "아니오"
        case let arr as [[String: Any]]: return "\(arr.count) 항목"
        case let arr as [Any]: return arr.map { "\($0)" }.joined(separator: ", ")
        case let dict as [String: Any]: return "\(dict.count) 항목"
        default: return "\(value!)"
        }
    }

    static func date(epoch: Int?) -> String {
        guard let epoch, epoch > 0 else { return "-" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    // Any 타입의 epoch(초) 값을 그대로 룬짜 문자열로 바꾼다(Int/Int64/Double 모두 지원).
    static func epochString(_ value: Any?) -> String? {
        guard let epoch = toInt(value), epoch > 0 else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }
}
