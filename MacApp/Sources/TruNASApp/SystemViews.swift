import SwiftUI

// MARK: - 알림 화면

struct AlertsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmDismiss: Alert?

    var body: some View {
        List {
            if model.alerts.isEmpty && !model.isBusy {
                Text("활성 알림이 없습니다.").foregroundStyle(.secondary)
            }
            ForEach(model.alerts, id: \.id) { alert in
                HStack(alignment: .top, spacing: 10) {
                    severityIcon(alert.severity)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.klass ?? "Alert").bold()
                        Text(alert.alert ?? "").font(.callout).foregroundStyle(.secondary)
                        if let dt = alert.datetime {
                            Text(dt).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("무시") { confirmDismiss = alert }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("알림")
        .toolbar { ToolbarItem { RefreshToolbar { Task { await model.loadDashboard() } } } }
        .task { await model.loadDashboard() }
        .confirmationDialog(
            "알림 무시",
            isPresented: Binding(get: { confirmDismiss != nil }, set: { if !$0 { confirmDismiss = nil } })
        ) {
            Button("무시", role: .destructive) {
                if let a = confirmDismiss, let id = a.id { Task { await model.dismissAlert(id: id) } }
                confirmDismiss = nil
            }
            Button("취소", role: .cancel) { confirmDismiss = nil }
        } message: {
            Text("이 알림을 무시 목록으로 이동할까요?")
        }
    }
}

// MARK: - 서비스 화면 (시작/중지 토글)

struct ServicesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            if model.services.isEmpty && !model.isBusy {
                Text("서비스 데이터가 없습니다.").foregroundStyle(.secondary)
            }
            ForEach(Array(model.services.enumerated()), id: \.offset) { _, svc in
                let name = Fmt.anyString(svc["service"])
                let running = (svc["state"] as? String) == "RUNNING"
                HStack {
                    Image(systemName: running ? "play.circle.fill" : "pause.circle")
                        .foregroundStyle(running ? .green : .secondary)
                    Text(name).bold()
                    Text(Fmt.anyString(svc["state"])).mono().foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await model.restartService(name: name) }
                    } label: {
                        Image(systemName: "arrow.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy || name.isEmpty)
                    .help("서비스 재시작")
                    Toggle("실행 중", isOn: Binding(
                        get: { running },
                        set: { _ in Task { await model.toggleService(name: name, currentlyRunning: running) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(model.isBusy || name.isEmpty)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("서비스")
        .toolbar { ToolbarItem { RefreshToolbar { Task { await model.loadServices() } } } }
        .task { await model.loadServices() }
    }
}

// MARK: - 스크럽 작업 화면

struct ScrubsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmRun: [String: Any]?

    var body: some View {
        List {
            if model.scrubs.isEmpty && !model.isBusy {
                Text("스크럽 작업이 없습니다.").foregroundStyle(.secondary)
            }
            ForEach(Array(model.scrubs.enumerated()), id: \.offset) { _, scrub in
                let id = Fmt.toInt(scrub["id"]) ?? 0
                HStack {
                    Image(systemName: "sparkles")
                    let poolName = Fmt.anyString((scrub["pool"] as? [String: Any])?["name"])
                    VStack(alignment: .leading, spacing: 3) {
                        Text(poolName).bold()
                        Text("주기: \(Fmt.anyString(scrub["interval"])) · 설명: \(Fmt.anyString(scrub["description"]))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("지금 실행") { confirmRun = scrub }
                        .buttonStyle(.borderless)
                        .disabled(id == 0 || model.isBusy)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("스크럽 작업")
        .toolbar { ToolbarItem { RefreshToolbar { Task { await model.loadScrubs() } } } }
        .task { await model.loadScrubs() }
        .confirmationDialog(
            "스크럽 실행",
            isPresented: Binding(get: { confirmRun != nil }, set: { if !$0 { confirmRun = nil } })
        ) {
            Button("실행") {
                if let scrub = confirmRun, let id = Fmt.toInt(scrub["id"]) {
                    Task { await model.runScrub(id: id) }
                }
                confirmRun = nil
            }
            Button("취소", role: .cancel) { confirmRun = nil }
        } message: {
            Text("이 풀에 대해 지금 스크럽을 시작할까요? 백그라운드에서 실행됩니다.")
        }
    }
}
