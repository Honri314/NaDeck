import SwiftUI

struct SnapshotsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false
    @State private var confirmDelete: Snapshot?
    @State private var confirmRollback: Snapshot?
    @State private var confirmRollbackRecursive = false
    @State private var cloneTarget: Snapshot?
    @State private var cloneDst = ""

    var body: some View {
        List {
            Section("복제 작업 (\(model.replications.count))") {
                if model.replications.isEmpty {
                    Text("복제 작업이 없습니다. (TrueNAS 웹 UI에서 생성 가능)").foregroundStyle(.secondary)
                }
                ForEach(model.replications, id: \.id) { task in
                    HStack {
                        Image(systemName: task.enabled ?? true ? "arrow.left.arrow.right.circle.fill" : "pause.circle")
                            .foregroundStyle(task.enabled ?? true ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.name ?? "Task #\(task.id)").bold()
                            if let t = task.targetDataset {
                                Text("→ \(t)").mono().font(.caption)
                            }
                        }
                        Spacer()
                        Text(task.direction ?? "").mono().foregroundStyle(.secondary)
                    }
                }
            }

            Section("스냅샷 (\(model.snapshots.count))") {
                if model.snapshots.isEmpty && !model.isBusy {
                    Text("스냅샷이 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(model.snapshots, id: \.name) { snap in
                    HStack {
                        Image(systemName: cameraIcon(for: snap))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snap.name ?? "-").mono()
                            HStack(spacing: 8) {
                                Text("데이터셋: \(snap.dataset ?? "-")").font(.caption).foregroundStyle(.secondary)
                                Text("생성: \(Fmt.date(epoch: snap.takenAt))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            cloneTarget = snap
                            cloneDst = (snap.dataset ?? "") + "_clone"
                        } label: {
                            Image(systemName: "plus.rectangle.on.rectangle")
                        }
                        .buttonStyle(.borderless)
                        .help("이 스냅샷을 데이터셋으로 클론")
                        Button {
                            confirmRollback = snap
                            confirmRollbackRecursive = false
                        } label: {
                            Image(systemName: "arrow.uturn.left.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("롤백")
                        Button(role: .destructive) {
                            confirmDelete = snap
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("스냅샷 삭제")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("스냅샷 / 복제")
        .toolbar {
            ToolbarItem {
                HStack {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("스냅샷 생성")
                    RefreshToolbar { Task { await model.loadSnapshots() } }
                }
            }
        }
        .task { await model.loadSnapshots() }
        .sheet(isPresented: $showAdd) {
            CreateSnapshotSheet()
        }
        .confirmationDialog(
            "스냅샷 삭제",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("삭제", role: .destructive) {
                if let s = confirmDelete { Task { await model.deleteSnapshot(s) } }
                confirmDelete = nil
            }
            Button("취소", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("'\(confirmDelete?.name ?? "")' 스냅샷을 삭제할까요? 이 작업은 되돌릴 수 없습니다.")
        }
        .confirmationDialog(
            "스냅샷 롤백",
            isPresented: Binding(get: { confirmRollback != nil }, set: { if !$0 { confirmRollback = nil } })
        ) {
            Button("롤백 실행", role: .destructive) {
                if let s = confirmRollback, let id = s.name {
                    Task { await model.rollbackSnapshot(id: id, recursive: confirmRollbackRecursive) }
                }
                confirmRollback = nil
            }
            Button("취소", role: .cancel) { confirmRollback = nil }
        } message: {
            Text("이 데이터셋을 스냅샷 시점으로 되돌립니다.\n'이후 스냅샷/변경사항 즉시 삭제' \(confirmRollbackRecursive ? "(하위 재귀 포함)" : "")  — 되돌릴 수 없습니다.")
        }
        .sheet(isPresented: Binding(get: { cloneTarget != nil }, set: { if !$0 { cloneTarget = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("스냅샷 클론").font(.title3).bold()
                Text("원본: \(cloneTarget?.name ?? "-")").mono().font(.caption)
                VStack(alignment: .leading, spacing: 3) {
                    Text("새 데이터셋 이름(경로)").bold()
                    TextField("pool/dataset_clone", text: $cloneDst)
                }
                HStack {
                    Spacer()
                    Button("취소") { cloneTarget = nil }
                    Button("클론 생성") {
                        let id = cloneTarget?.name ?? ""
                        let dst = cloneDst
                        cloneTarget = nil
                        Task { await model.cloneSnapshot(id: id, to: dst) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cloneDst.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 440)
        }
    }

    private func cameraIcon(for snap: Snapshot) -> String {
        if let ds = snap.dataset, ds.hasPrefix("boot-pool") {
            return "desktopcomputer"
        }
        return "camera.on.rectangle"
    }
}

struct CreateSnapshotSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var dataset = ""
    @State private var name = ""
    @State private var recursive = false

    private var valid: Bool {
        !name.isEmpty && (dataset.isEmpty ? false : true) || !dataset.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("스냅샷 생성").font(.title3).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("데이터셋").bold()
                Picker("", selection: $dataset) {
                    Text("선택...").tag("")
                    ForEach(model.datasets.filter {
                        ($0.type ?? "FILESYSTEM") == "FILESYSTEM" && !($0.name ?? "").isEmpty
                    }, id: \.name) { ds in
                        Text(ds.name ?? "").tag(ds.name ?? "")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("스냅샷 이름").bold()
                TextField("예: before_upgrade", text: $name)
                Text("생성되는 전체 이름: \(dataset.isEmpty ? "dataset" : dataset)@\(name.isEmpty ? "이름" : name)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("하위 데이터셋 모두 재귀 생성", isOn: $recursive)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("생성") {
                    let ds = dataset, n = name, r = recursive
                    dismiss()
                    Task { await model.createSnapshot(dataset: ds, name: n, recursive: r) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(dataset.isEmpty || name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
