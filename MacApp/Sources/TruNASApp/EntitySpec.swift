import Foundation

// MARK: - 범용 엔티티 사양 (카테고리별 기능 정의)

enum ColumnKind {
    case raw, bytes, bool, time
}

struct EntityColumn {
    let key: String
    let header: String
    let kind: ColumnKind
}

enum EntityFieldType {
    case text, password, bool, datasetChoice
}

struct EditFieldSpec {
    let key: String
    let label: String
    let kind: EntityFieldType
}

struct EntityField {
    let key: String
    let label: String
    let type: EntityFieldType
    var required: Bool = false
    var placeholder: String = ""
}

struct EntitySpec {
    let key: String
    let title: String
    let endpoint: String
    let idField: String
    var deleteBasePath: String? = nil      // 기본: endpoint + "/id/"
    let columns: [EntityColumn]
    var createFields: [EntityField] = []   // 비어 있으면 추가 불가(읽기 전용)
    var editFields: [EntityField] = []     // 비어 있으면 편집 불가
    var createDefaults: [String: Any] = [:]
    var deletable: Bool = true
}

extension NavItem {
    var spec: EntitySpec? {
        switch self {
        case .datasets:
            return EntitySpec(
                key: rawValue, title: "데이터셋", endpoint: "/pool/dataset", idField: "name",
                columns: [.init(key: "name", header: "이름", kind: .raw),
                          .init(key: "pool", header: "풀", kind: .raw),
                          .init(key: "type", header: "유형", kind: .raw),
                          .init(key: "comments", header: "설명", kind: .raw),
                          .init(key: "used", header: "사용량", kind: .bytes)],
                createFields: [
                    .init(key: "dataset_path", label: "상위 데이터셋", type: .datasetChoice, required: true),
                    .init(key: "name", label: "이름", type: .text, required: true),
                    .init(key: "comments", label: "설명", type: .text),
                ],
                createDefaults: ["type": "FILESYSTEM"]
            )
        case .disks:
            return EntitySpec(
                key: rawValue, title: "디스크", endpoint: "/disk", idField: "name",
                columns: [.init(key: "name", header: "장치", kind: .raw),
                          .init(key: "model", header: "모델", kind: .raw),
                          .init(key: "serial", header: "시리얼", kind: .raw),
                          .init(key: "size", header: "용량", kind: .bytes),
                          .init(key: "temperature", header: "온도", kind: .raw),
                          .init(key: "rotationrate", header: "RPM", kind: .raw)],
                deletable: false
            )
        case .sharesSMB:
            return EntitySpec(
                key: rawValue, title: "SMB 공유", endpoint: "/sharing/smb", idField: "id",
                columns: [.init(key: "name", header: "이름", kind: .raw),
                          .init(key: "path", header: "경로", kind: .raw),
                          .init(key: "purpose", header: "유형", kind: .raw),
                          .init(key: "comment", header: "설명", kind: .raw),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                createFields: [
                    .init(key: "name", label: "공유 이름", type: .text, required: true),
                    .init(key: "path", label: "데이터셋 경로", type: .datasetChoice, required: true),
                    .init(key: "comment", label: "설명", type: .text),
                ],
                editFields: [
                    .init(key: "comment", label: "설명", type: .text),
                    .init(key: "enabled", label: "활성", type: .bool),
                    .init(key: "readonly", label: "읽기 전용", type: .bool),
                    .init(key: "browsable", label: "탐색 가능", type: .bool),
                ]
            )
        case .sharesNFS:
            return EntitySpec(
                key: rawValue, title: "NFS 공유", endpoint: "/sharing/nfs", idField: "id",
                columns: [.init(key: "path", header: "경로", kind: .raw),
                          .init(key: "networks", header: "네트워크", kind: .raw),
                          .init(key: "hosts", header: "호스트", kind: .raw),
                          .init(key: "ro", header: "읽기전용", kind: .bool),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                editFields: [
                    .init(key: "comment", label: "설명", type: .text),
                    .init(key: "hosts", label: "호스트", type: .text),
                    .init(key: "ro", label: "읽기 전용", type: .bool),
                    .init(key: "enabled", label: "활성", type: .bool),
                ],
                deletable: true
            )
        case .iscsi:
            return EntitySpec(
                key: rawValue, title: "iSCSI 대상", endpoint: "/iscsi/target", idField: "id",
                columns: [.init(key: "target_name", header: "대상 이름", kind: .raw),
                          .init(key: "alias", header: "별명", kind: .raw),
                          .init(key: "auth_type", header: "인증", kind: .raw)],
                deletable: false
            )
        case .replications:
            return EntitySpec(
                key: rawValue, title: "복제 작업", endpoint: "/replication", idField: "id",
                columns: [.init(key: "name", header: "이름", kind: .raw),
                          .init(key: "direction", header: "방향", kind: .raw),
                          .init(key: "target_dataset", header: "대상", kind: .raw),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                deletable: false
            )
        case .users:
            return EntitySpec(
                key: rawValue, title: "사용자", endpoint: "/user", idField: "id",
                columns: [.init(key: "username", header: "사용자", kind: .raw),
                          .init(key: "uid", header: "UID", kind: .raw),
                          .init(key: "full_name", header: "표시 이름", kind: .raw),
                          .init(key: "shell", header: "셸", kind: .raw),
                          .init(key: "smb", header: "SMB", kind: .bool)],
                createFields: [
                    .init(key: "username", label: "사용자 이름", type: .text, required: true),
                    .init(key: "full_name", label: "표시 이름", type: .text),
                    .init(key: "password", label: "비밀번호 (8자 이상)", type: .password, required: true),
                    .init(key: "smb", label: "SMB 접근 허용", type: .bool),
                ],
                editFields: [   // PUT /user/id (25.10 스키마: email 제외)
                    .init(key: "full_name", label: "표시 이름", type: .text),
                    .init(key: "shell", label: "셸(/usr/bin/nologin 등)", type: .text),
                    .init(key: "locked", label: "잠금", type: .bool),
                    .init(key: "smb", label: "SMB 접근 허용", type: .bool),
                ],
                createDefaults: ["group_create": true]
            )
        case .groups:
            return EntitySpec(
                key: rawValue, title: "그룹", endpoint: "/group", idField: "id",
                columns: [.init(key: "group", header: "그룹", kind: .raw),
                          .init(key: "gid", header: "GID", kind: .raw),
                          .init(key: "builtin", header: "시스템", kind: .bool),
                          .init(key: "smb", header: "SMB", kind: .bool)],
                createFields: [
                    .init(key: "name", label: "그룹 이름", type: .text, required: true),
                    .init(key: "smb", label: "SMB 접근 허용", type: .bool),
                ]
            )
        case .cronjobs:
            return EntitySpec(
                key: rawValue, title: "Cron 작업", endpoint: "/cronjob", idField: "id",
                columns: [.init(key: "title", header: "제목", kind: .raw),
                          .init(key: "command", header: "명령", kind: .raw),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                createFields: [
                    .init(key: "title", label: "제목", type: .text, required: true),
                    .init(key: "command", label: "명령", type: .text, required: true),
                ]
            )
        case .rsyncTasks:
            return EntitySpec(
                key: rawValue, title: "Rsync 작업", endpoint: "/rsynctask", idField: "id",
                columns: [.init(key: "desc", header: "설명", kind: .raw),
                          .init(key: "direction", header: "방향", kind: .raw),
                          .init(key: "remotehost", header: "호스트", kind: .raw),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                deletable: false
            )
        case .cloudSyncs:
            return EntitySpec(
                key: rawValue, title: "Cloud Sync", endpoint: "/cloudsync", idField: "id",
                columns: [.init(key: "description", header: "설명", kind: .raw),
                          .init(key: "direction", header: "방향", kind: .raw),
                          .init(key: "enabled", header: "활성", kind: .bool)],
                deletable: false
            )
        case .interfaces:
            return EntitySpec(
                key: rawValue, title: "인터페이스", endpoint: "/interface", idField: "name",
                columns: [.init(key: "name", header: "이름", kind: .raw),
                          .init(key: "state", header: "상태", kind: .raw),
                          .init(key: "type", header: "유형", kind: .raw),
                          .init(key: "mtu", header: "MTU", kind: .raw),
                          .init(key: "ipv4_addr", header: "IP", kind: .raw)],
                deletable: false
            )
        case .certificates:
            return EntitySpec(
                key: rawValue, title: "인증서", endpoint: "/certificate", idField: "id",
                columns: [.init(key: "name", header: "이름", kind: .raw),
                          .init(key: "issued", header: "발급일", kind: .time),
                          .init(key: "expires_at", header: "만료일", kind: .time),
                          .init(key: "self_signed", header: "자가서명", kind: .bool)],
                deletable: false
            )
        case .staticRoutes:
            return EntitySpec(
                key: rawValue, title: "정적 라우트", endpoint: "/staticroute", idField: "id",
                columns: [.init(key: "destination", header: "대상", kind: .raw),
                          .init(key: "gateway", header: "게이트웨이", kind: .raw),
                          .init(key: "description", header: "설명", kind: .raw)],
                createFields: [
                    .init(key: "destination", label: "대상 (예: 192.168.10.0/24)", type: .text, required: true),
                    .init(key: "gateway", label: "게이트웨이 (예: 192.168.10.1)", type: .text, required: true),
                    .init(key: "description", label: "설명", type: .text),
                ]
            )
        default:
            return nil
        }
    }
}
