import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var diagLines: [String] = []
    @State private var diagCopied = false
    @State private var newProfileName = ""
    @State private var showDeleteConfirm = false
    @State private var latestVersion: String?
    @State private var updateError: String?
    @State private var checkingUpdate = false

    var body: some View {
        Form {
            // 여러 TrueNAS를 저장·선택해서 다중 관리한다.
            Section(T("NAS 선택 (다중 관리)", "NAS selection")) {
                if model.profiles.isEmpty {
                    Text(T("아직 저장된 NAS가 없습니다. 아래에서 연결을 입력하면 자동으로 저장됩니다.",
                           "No saved NAS yet. Enter a connection below to save it."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker(T("관리할 NAS", "NAS"), selection: Binding(
                        get: { model.activeProfileName },
                        set: { model.selectProfile($0) }
                    )) {
                        ForEach(model.profiles, id: \.name) { profile in
                            Text(profile.name).tag(profile.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .leading)

                    HStack {
                        TextField(T("새 NAS 이름", "New NAS name"), text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Button(T("지금 설정으로 새 NAS 저장", "Save as new NAS")) {
                            _ = model.saveNewProfile(name: newProfileName)
                            newProfileName = ""
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if model.profiles.count > 1 {
                        Button(T("이 NAS 프로파일 삭제", "Delete this NAS profile"), role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(model.activeProfileName.isEmpty)
                    }
                    Text(T("NAS를 전환하면 사이드바 화면 데이터가 새 NAS 기준으로 다시 불러와집니다.\n편집 중인 연결 내용은 활성 NAS에 즉시 자동 저장됩니다.",
                           "Switching reloads pages for the selected NAS. Edits are auto-saved to the active profile."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(T("TrueNAS 연결", "TrueNAS Connection")) {
                TextField(T("표시 이름 (선택)", "Display name (optional)"), text: $model.config.name)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(T("주소 (예: 192.168.1.100 또는 https://nas.local)", "Address (e.g. 192.168.1.100 or https://nas.local)"), text: $model.config.baseURL)
                        .textFieldStyle(.roundedBorder)
                    Text(T(
                        "기본 포트: https 443 / http 80 (보통 공란으로 두세요).\n"
                        + "관리 UI 포트를 바꾼 경우에만 입력하세요 (예: 8443).\n"
                        + "테일스케일(Tailscale) 사용 시 매직DNS 이름(예: nas.tailnet.ts.net) 또는 100.x.x.x IP를 입력하세요. 자체 서명 인증서면 하단 옵션을 켜세요.",
                        "Default ports: https 443 / http 80 (usually leave blank).\n"
                        + "Only enter the port field if you changed the management port (e.g. 8443).\n"
                        + "With Tailscale, use a MagicDNS name or a 100.x.x.x IP. Enable the self-signed option if needed."
                    ))
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField(T("포트 (선택)", "Port (optional)"), text: Binding(
                    get: { model.config.port ?? "" },
                    set: { model.config.port = $0.isEmpty ? nil : $0 }
                ))
                    .textFieldStyle(.roundedBorder)
                SecureField(T("API 키", "API key"), text: $model.config.apiKey)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(T("TrueNAS 사용자 이름 (Basic 인증용, 선택)",
                                "TrueNAS username (for Basic auth, optional)"),
                              text: Binding(
                        get: { model.config.basicUser ?? "" },
                        set: { model.config.basicUser = $0.isEmpty ? nil : $0 }
                    ))
                        .textFieldStyle(.roundedBorder)
                    Text(T("X-API-Key/Bearer 인증이 401로 실패할 때 진단이 Basic 인증으로 자동 재시도합니다.\n자신의 관리 계정 이름(예: truenas_admin)을 입력해 두면 실험에 사용됩니다.",
                           "Diagnosis retries with Basic auth on 401. Enter your admin username (e.g. truenas_admin)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(T("자체 서명 인증서 허용 (사설 인증서 사용 시)", "Allow self-signed certificates"), isOn: $model.config.allowInsecure)
            }

            Section(T("표시 언어", "Language")) {
                Picker(T("언어", "Language"), selection: $model.language) {
                    Text(T("한국어", "한국어")).tag(AppLanguage.korean)
                    Text(T("English", "English")).tag(AppLanguage.english)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .frame(maxWidth: 260)
                Text(T("연결 테스트·오류 안내 문구에 적용됩니다.", "Applies to test and error messages."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(T("설정 저장 (이 기기에만 보관)", "Remember settings on this device"), isOn: $model.config.remember)
                HStack {
                    Button {
                        Task {
                            testing = true
                            await model.testConnection()
                            testOK = !model.isError
                            testResult = model.statusMessage ?? ""
                            testing = false
                        }
                    } label: {
                        HStack {
                            if testing { ProgressView().controlSize(.small) }
                            Text(T("연결 테스트", "Test connection"))
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task {
                            testing = true
                            diagLines = await model.diagnose()
                            testing = false
                        }
                    } label: {
                        Text(T("진단 실행", "Run diagnosis"))
                    }
                    .disabled(testing)

                    if model.isConfigured {
                        Button(T("연결 지우기", "Forget connection")) {
                            let cleared = TruenasConfig()
                            model.config = cleared
                            model.systemInfo = nil
                            model.pools = []
                            model.alerts = []
                        }
                    }
                    Spacer()
                }

                if let r = testResult {
                    Label(r, systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(testOK ? Color.green : Color.orange)
                }

                if !diagLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("진단 결과", "Diagnosis result")).bold()
                        ForEach(diagLines, id: \.self) { line in
                            Text(line).font(.callout)
                        }
                        HStack {
                            Button(T("진단 결과 복사", "Copy diagnosis")) {
                                let text = diagLines.joined(separator: "\n")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                                diagCopied = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if diagCopied {
                                Text(T("복사됨", "Copied"))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(T("복사한 내용을 개발자에게 전달하면 원인을 바로 찾아드릴 수 있습니다.",
                               "Paste the copied text when reporting an issue."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
                }
            }

            Section(T("앱 업데이트", "App update")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("현재 버전: ", "Current version: ") + AppUpdate.currentVersion)
                        if let latest = latestVersion {
                            Text(T("최신 버전: ", "Latest version: ") + latest)
                                .foregroundStyle(AppUpdate.isNewer(latest, than: AppUpdate.currentVersion) ? Color.orange : Color.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        checkingUpdate = true
                        updateError = nil
                        Task {
                            do {
                                latestVersion = try await AppUpdate.checkLatest()
                                updateError = nil
                            } catch {
                                latestVersion = nil
                                updateError = T("업데이트 서버에 접속할 수 없습니다.\n(\(error.localizedDescription))",
                                                "Cannot reach the update server.\n(\(error.localizedDescription))")
                            }
                            checkingUpdate = false
                        }
                    } label: {
                        HStack {
                            if checkingUpdate { ProgressView().controlSize(.small) }
                            Text(T("업데이트 확인", "Check for updates"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checkingUpdate)
                }
                if let latest = latestVersion, AppUpdate.isNewer(latest, than: AppUpdate.currentVersion) {
                    Text(T("새 버전이 있습니다. ダ운로ード 페이지를 열어 NaDeck-macOS.dmg를 받아 설치하면 됩니다.",
                           "A new version is available. Open the download page and install NaDeck-macOS.dmg."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if let err = updateError {
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
                Text(T("앱을 실행할 때마다 자동으로 확인하며, 새 버전이 있으면 상단에 안내합니다.",
                       "Checked automatically at launch; a notice appears when a new version exists."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(T("API 키 발급 방법 (단계별)", "How to get an API key (step by step)")) {
                Text(T(
                    "1. 웹 브라우저로 트루나스 관리 화면에 접속 (예: https://192.168.1.100)\n"
                    + "2. 왼쪽 메뉴에서 'Credential(자격 증명)' 클릭\n"
                    + "3. 'API Keys' 클릭 → 'Add(추가)' 클릭\n"
                    + "4. 이름(예: freenas-manager) 입력 → 생성\n"
                    + "5. 화면에 표시된 텍스트가 API 키입니다 → Copy 버튼으로 복사\n"
                    + "6. 이 앱의 'API 키' 입력칸에 바로 붙여넣기 (공백/줄바꿈 없이)\n"
                    + " ※ Copy 버튼을 쓰지 않고 드래그해서 복사하면 잘리거나 공백이 섞일 수 있습니다.\n"
                    + " ※ 키는 다시 표시되지 않으므로 복사하지 않았다면 삭제 후 재발급하세요.",
                    "1. Open the TrueNAS web UI (e.g. https://192.168.1.100)\n"
                    + "2. Click 'Credential' in the left menu\n"
                    + "3. Click 'API Keys' then 'Add'\n"
                    + "4. Enter a name (e.g. freenas-manager) and create\n"
                    + "5. Copy the key via the Copy button\n"
                    + "6. Paste it into the 'API key' field of this app (no spaces/newlines)\n"
                    + " NOTE: Manual selection may clip the key; the key is shown only once."
                ))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(T("이 앱은 키를 X-API-Key 헤더로 담아 관리 API를 호출합니다.",
                       "This app authenticates REST calls with the X-API-Key header."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("연결 설정")
        .padding(.top, 8)
        .confirmationDialog(
            T("\(model.activeProfileName) 프로파일 삭제", "Delete profile ") ,
            isPresented: $showDeleteConfirm
        ) {
            Button(T("삭제", "Delete"), role: .destructive) {
                model.deleteProfile(model.activeProfileName)
            }
            Button(T("취소", "Cancel"), role: .cancel) {}
        } message: {
            Text(T("저장된 주소와 API 키가 함께 지워집니다. 되돌릴 수 없습니다.",
                   "The saved address and API key are removed. This cannot be undone."))
        }
        .onDisappear {
            // 활성 프로파일 자동 저장은 config didSet이 처리하므로 별도 저장은 필요 없다.
            model.config.baseURL = TruenasClient.normalizeBaseURL(model.config.baseURL)
        }
    }
}
