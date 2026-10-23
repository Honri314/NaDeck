import SwiftUI

// MARK: - 앱(Applications) 관리 화면

struct AppsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDelete: [String: Any]?

    var body: some View {
        List {
            if model.apps.isEmpty && !model.isBusy {
                VStack(alignment: .leading, spacing: 4) {
                    Text("설치된 앱이 없습니다.")
                    Text("Docker 풀이 설정되지 않은 경우 TrueNAS 웹 UI의 '앱' 화면에서 풀을 지정하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(Array(model.apps.enumerated()), id: \.offset) { _, app in
                let name = Fmt.anyString(app["name"])
                let state = Fmt.anyString(app["state"])
                let running = state.uppercased().contains("RUNNING")
                let upgradeAvailable = (app["upgrade_available"] as? Bool) == true
                HStack {
                    Image(systemName: running ? "play.circle.fill" : "pause.circle")
                        .foregroundStyle(running ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).bold()
                        if upgradeAvailable {
                            Text("버전: \(Fmt.anyString(app["version"])) → 최신 \(Fmt.anyString(app["latest_version"]))")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Text("버전: \(Fmt.anyString(app["version"]))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let containers = app["containers"] as? [[String: Any]], !containers.isEmpty {
                            let hosts = containers.compactMap { $0["hostname"] as? String }
                                .joined(separator: ", ")
                            Text("컨테이너: \(hosts)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(state)
                        .mono()
                        .foregroundStyle(running ? .green : .secondary)
                    Menu("동작") {
                        Button("시작") { Task { await model.appAction(app, action: "start") } }
                            .disabled(running)
                        Button("정지") { Task { await model.appAction(app, action: "stop") } }
                            .disabled(!running)
                        Button("재배포") { Task { await model.appAction(app, action: "redeploy") } }
                        Button("업그레이드") { Task { await model.appAction(app, action: "upgrade") } }
                        Button("삭제", role: .destructive) { confirmDelete = app }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("앱 관리")
        .alert("앱 삭제", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let app = confirmDelete {
                    Task { await model.appAction(app, action: "delete") }
                }
                confirmDelete = nil
            }
            Button("취소", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("'\(confirmDelete.map { Fmt.anyString($0["name"]) } ?? "")' 앱과 그 데이터셋을 삭제할까요? 이 작업은 되돌릴 수 없습니다.")
        }
        .toolbar { ToolbarItem { RefreshToolbar { Task { await model.loadApps() } } } }
        .task { await model.loadApps() }
    }
}

// MARK: - 가상머신(VM) 관리 화면

struct VMsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showCreate = false
    @State private var confirmDelete: [String: Any]?

    var body: some View {
        List {
            if model.vms.isEmpty && !model.isBusy {
                Text("가상머신이 없습니다. 새로고침 후 'VM 생성'으로 만들 수 있습니다.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.vms.enumerated()), id: \.offset) { _, vm in
                let id = Fmt.toInt(vm["id"]) ?? 0
                let state = stateString(vm)
                let running = state.uppercased() == "RUNNING"
                HStack {
                    Image(systemName: running ? "power.circle.fill" : "power.circle")
                        .foregroundStyle(running ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.anyString(vm["name"])).bold()
                        Text("#\(id)  vCPU \(Fmt.anyString(vm["vcpus"]))  메모리 \(memGiB(vm))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(state)
                        .mono()
                        .foregroundStyle(running ? .green : .secondary)
                    Menu("동작") {
                        Button("시작") { Task { await model.vmAction(vm, action: "start") } }
                            .disabled(running)
                        Button("정지") { Task { await model.vmAction(vm, action: "stop") } }
                            .disabled(!running)
                        Button("재시작") { Task { await model.vmAction(vm, action: "restart") } }
                            .disabled(!running)
                        Button("전원 끄기") { Task { await model.vmAction(vm, action: "poweroff") } }
                        Button("삭제", role: .destructive) { confirmDelete = vm }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("가상머신")
        .toolbar {
            ToolbarItem {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .help("VM 생성")
            }
            ToolbarItem { RefreshToolbar { Task { await model.loadVMs() } } }
        }
        .sheet(isPresented: $showCreate) {
            CreateVMSheet()
        }
        .alert("VM 삭제", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let vm = confirmDelete {
                    Task { await model.vmAction(vm, action: "delete") }
                }
                confirmDelete = nil
            }
            Button("취소", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("'\(confirmDelete.map { Fmt.anyString($0["name"]) } ?? "")' VM을 삭제할까요? 디스크는 삭제되지 않습니다.")
        }
        .task { await model.loadVMs() }
    }

    private func stateString(_ vm: [String: Any]) -> String {
        if let status = vm["status"] as? [String: Any],
           let s = status["state"] as? String, !s.isEmpty {
            return s
        }
        if let s = vm["state"] as? String, !s.isEmpty {
            return s
        }
        return "-"
    }

    private func memGiB(_ vm: [String: Any]) -> String {
        guard let mem = Fmt.toInt(vm["memory"]) else { return "-" }
        return "\(mem / 1024) GiB"
    }
}

// MARK: - VM 생성 시트

struct CreateVMSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var vcpus = "1"
    @State private var memoryGB = "4"
    @State private var diskGB = "20"
    @State private var isoPath = ""
    @State private var nicAttach = ""
    @State private var autostart = true

    private var poolName: String {
        model.pools.first?.name ?? ""
    }

    var body: some View {
        Form {
            Section("VM 생성") {
                TextField("VM 이름", text: $name)
                TextField("vCPU 수", text: $vcpus)
                    .frame(maxWidth: 140)
                TextField("메모리 (GB)", text: $memoryGB)
                    .frame(maxWidth: 140)
                TextField("디스크 크기 (GB, ZVOL 신규 생성)", text: $diskGB)
                    .frame(maxWidth: 160)
                if model.pools.isEmpty {
                    Text("스토리지 풀 정보를 불러오지 못했습니다. 나중에 다시 시도해 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("디스크 생성 풀: \(poolName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("ISO 경로 (CD-ROM, 공란 가능, /mnt/...)", text: $isoPath)
                TextField("NIC 연결 (공란 가능, 예: br0)", text: $nicAttach)
                Toggle("부팅 시 자동 시작", isOn: $autostart)
                HStack {
                    Spacer()
                    Button("취소", role: .cancel) { dismiss() }
                    Button("생성") { create() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || poolName.isEmpty || model.isBusy)
                }
                Text("디스크는 \(poolName)/\(safeName)-disk ZVOL로 신규 생성됩니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 420)
        .task {
            await model.loadPools()
        }
    }

    private var safeName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<VM이름>" : trimmed
    }

    private func create() {
        Task {
            await model.createVM(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                vcpus: max(1, Int(vcpus) ?? 1),
                memoryGB: max(1, Int(memoryGB) ?? 4),
                diskGB: max(1, Int(diskGB) ?? 20),
                pool: poolName,
                isoPath: isoPath.trimmingCharacters(in: .whitespacesAndNewlines),
                nicAttach: nicAttach.trimmingCharacters(in: .whitespacesAndNewlines),
                autostart: autostart
            )
            dismiss()
        }
    }
}
