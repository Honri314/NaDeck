import SwiftUI

// [String: Any] 사전에서 "a.b.c" 같은 점 경로로 값을 꺼내는 공용 헬퍼
func nestedValue(_ dict: [String: Any], _ keyPath: String) -> Any? {
    var current: Any = dict
    for part in keyPath.split(separator: ".").map(String.init) {
        guard let inner = current as? [String: Any], let next = inner[part] else { return nil }
        current = next
    }
    return current
}

// MARK: - 범용 엔티티 화면

struct GenericEntityView: View {
    @EnvironmentObject var model: AppModel
    let spec: EntitySpec

    @State private var showAdd = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var selectedIndex: Int?
    @State private var deleteTargetDescription = ""

    private var rows: [[String: Any]] { model.entities[spec.key] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .navigationTitle(spec.title)
        .task { await model.loadEntity(spec) }
        .sheet(isPresented: $showAdd) {
            EntityCreateSheet(spec: spec)
        }
        .sheet(isPresented: $showEdit) {
            if let index = selectedIndex, index < rows.count {
                EntityEditSheet(spec: spec, row: rows[index])
            }
        }
        .confirmationDialog(
            "\(spec.title) 삭제",
            isPresented: $showDeleteConfirm
        ) {
            Button("삭제", role: .destructive) { deleteSelected() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("'\(deleteTargetDescription)' 항목을 삭제할까요? 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: 상단 바

    private var headerBar: some View {
        HStack {
            // 화면 제목은 툴바(navigationTitle)로만 표시하고,
            // 상단 바에는 항목 수와 작업 버튼만 둔다(전체화면 상단 두꺼움 방지).
            Text("\(rows.count) 개")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if !spec.createFields.isEmpty {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("추가")
            }
            if !spec.editFields.isEmpty {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(selectedIndex == nil)
                .help("편집")
            }
            if spec.deletable {
                Button {
                    askDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedIndex == nil)
                .help("선택 삭제")
            }
            RefreshToolbar { Task { await model.loadEntity(spec) } }
        }
        .padding([.horizontal, .vertical], 12)
    }

    // MARK: 목록 영역

    private var contentArea: some View {
        Group {
            if rows.isEmpty && !model.isBusy {
                VStack(spacing: 8) {
                    Text("데이터가 없습니다.")
                    Text("새로고침을 눌러 주세요.").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tableBody
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var tableBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerRow()
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { index, _ in
                    rowView(index: index)
                        .background(rowBackground(isSelected: selectedIndex == index))
                        .onTapGesture { selectedIndex = index }
                    Divider().opacity(0.4)
                }
            }
            .padding(.horizontal, 14)
            // 가로 좌우 여유 폭을 채워 상세 화면이 사이드바를 밀지 않게 한다
            .frame(maxWidth: .infinity)
            .frame(minWidth: 0)
        }
    }

    private func headerRow() -> some View {
        HStack(spacing: 10) {
            ForEach(spec.columns, id: \.key) { col in
                Text(col.header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func rowView(index: Int) -> some View {
        return HStack(spacing: 10) {
            ForEach(spec.columns, id: \.key) { col in
                cellText(index: index, col: col)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color.clear
    }

    // MARK: 셀 렌더링

    private func value(at index: Int, key: String) -> Any? {
        guard index < rows.count else { return nil }
        var current: Any = rows[index]
        for part in key.split(separator: ".").map(String.init) {
            guard let dict = current as? [String: Any], let next = dict[part] else { return nil }
            current = next
        }
        return current
    }

    private func cellText(index: Int, col: EntityColumn) -> Text {
        let value = value(at: index, key: col.key)
        switch col.kind {
        case .raw:
            return Text(Fmt.anyString(value))
        case .bytes:
            if let n = Fmt.toInt(value) {
                return Text(Fmt.bytes(n))
            }
            return Text("-")
        case .bool:
            let flag = value as? Bool
            if flag == true {
                return Text("예").foregroundColor(.green)
            }
            if flag == nil {
                return Text("-")
            }
            return Text("아니오").foregroundColor(.secondary)
        case .time:
            return Text(Fmt.date(epoch: Fmt.toInt(value))).foregroundColor(.secondary)
        }
    }

    // MARK: 동작

    private func askDelete() {
        guard let index = selectedIndex, index < rows.count else { return }
        let row = rows[index]
        deleteTargetDescription = Fmt.anyString(row[spec.columns.first?.key ?? spec.idField])
        showDeleteConfirm = true
    }

    private func deleteSelected() {
        guard let index = selectedIndex, index < rows.count else { return }
        let row = rows[index]
        let taskSpec = spec
        let target = row
        Task {
            await model.deleteEntity(taskSpec, target)
            selectedIndex = nil
        }
    }
}

// MARK: - 편집 시트 (기존 값 채워 넣고 PUT)

struct EntityEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let spec: EntitySpec
    let row: [String: Any]

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var datasetOptions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(spec.title) 편집").font(.title3).bold()
            Form {
                ForEach(spec.editFields, id: \.key) { field in
                    fieldRow(field)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("저장") {
                    let body = buildBody()
                    dismiss()
                    Task { await model.updateEntity(spec, row, fields: body) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
        .frame(minHeight: 300)
        .task {
            datasetOptions = await model.fetchDatasetNames()
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: EntityField) -> some View {
        switch field.type {
        case .text, .password:
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label).bold()
                TextField("값", text: textBinding(field.key))
            }
        case .bool:
            Toggle(field.label, isOn: boolBinding(field.key))
        case .datasetChoice:
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label).bold()
                Picker("", selection: textBinding(field.key)) {
                    Text("선택...").tag("")
                    ForEach(datasetOptions, id: \.self) { name in
                        Text("/mnt/\(name)").tag("/mnt/\(name)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func prefilled(_ key: String) -> String {
        let value = nestedValue(row, key)
        if let n = Fmt.toInt(value) { return String(n) }
        return Fmt.anyString(value)
    }

    private func prefilledBool(_ key: String) -> Bool {
        nestedValue(row, key) as? Bool ?? false
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { textValues[key] ?? prefilled(key) },
            set: { textValues[key] = $0 }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { boolValues[key] ?? prefilledBool(key) },
            set: { boolValues[key] = $0 }
        )
    }

    // PUT 본문: 값이 들어간 필드만 보낸다(빈 값 = 변경 없음으로 두어
    // 스키마에 없는 필드 전송 오류를 피한다).
    private func buildBody() -> [String: Any] {
        var body: [String: Any] = [:]
        for field in spec.editFields {
            switch field.type {
            case .text, .password, .datasetChoice:
                let value = textValues[field.key] ?? ""
                if !value.isEmpty { body[field.key] = value }
            case .bool:
                body[field.key] = boolValues[field.key] ?? false
            }
        }
        return body
    }
}

// MARK: - 생성 시트

struct EntityCreateSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let spec: EntitySpec

    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var datasetOptions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(spec.title) 추가").font(.title3).bold()
            Form {
                ForEach(spec.createFields, id: \.key) { field in
                    fieldRow(field)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("추가") {
                    let body = buildBody()
                    dismiss()
                    Task { await model.createEntity(spec, fields: body) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 460)
        .frame(minHeight: 300)
        .task {
            datasetOptions = await model.fetchDatasetNames()
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: EntityField) -> some View {
        switch field.type {
        case .text, .password:
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label).bold()
                if field.type == .password {
                    SecureField(field.placeholder, text: textBinding(field.key))
                } else {
                    TextField(field.placeholder, text: textBinding(field.key))
                }
            }
        case .bool:
            Toggle(field.label, isOn: boolBinding(field.key))
        case .datasetChoice:
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label).bold()
                Picker("", selection: textBinding(field.key)) {
                    Text("선택...").tag("")
                    ForEach(datasetOptions, id: \.self) { name in
                        Text("/mnt/\(name)").tag("/mnt/\(name)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func textBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { textValues[key] ?? "" },
            set: { textValues[key] = $0 }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { boolValues[key] ?? false },
            set: { boolValues[key] = $0 }
        )
    }

    private var valid: Bool {
        for field in spec.createFields {
            guard field.required else { continue }
            switch field.type {
            case .text, .password, .datasetChoice:
                if (textValues[field.key] ?? "").isEmpty { return false }
            case .bool:
                break
            }
        }
        return true
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = [:]
        for field in spec.createFields {
            switch field.type {
            case .text, .password, .datasetChoice:
                let value = textValues[field.key] ?? ""
                if !value.isEmpty { body[field.key] = value }
            case .bool:
                body[field.key] = boolValues[field.key] ?? false
            }
        }
        return body
    }
}
