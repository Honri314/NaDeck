import Foundation

// MARK: - 인증/설정

// 여러 TrueNAS를 관리하기 위한 연결 프로파일.
// 이름이 고유 식별자이고, 나머지 필드는 단일 연결 설정과 동일하다.
struct NasProfile: Codable {
    var name: String
    var baseURL: String = ""
    var apiKey: String = ""
    var allowInsecure: Bool = false
    var port: String? = nil
    var authMode: String? = nil
    var basicUser: String? = nil

    /// TruenasConfig(단일 연결 작업 사본)에서 프로파일로 변환
    init(name: String, from config: TruenasConfig) {
        self.name = name
        self.baseURL = config.baseURL
        self.apiKey = config.apiKey
        self.allowInsecure = config.allowInsecure
        self.port = config.port
        self.authMode = config.authMode
        self.basicUser = config.basicUser
    }

    func asConfig() -> TruenasConfig {
        var c = TruenasConfig()
        c.name = name
        c.baseURL = baseURL
        c.apiKey = apiKey
        c.allowInsecure = allowInsecure
        c.port = port
        c.authMode = authMode
        c.basicUser = basicUser
        return c
    }
}

struct TruenasConfig: Codable {
    var name: String = ""
    var baseURL: String = ""      // 예: https://192.168.1.100
    var apiKey: String = ""
    var allowInsecure: Bool = false // 자체 서명 인증서 허용
    var remember: Bool = true
    var port: String? = nil

    // 인증 방식 폴백: "api_key"(기본) / "bearer" / "basic"
    var authMode: String? = nil
    // Basic 인증용 TrueNAS 사용자 이름 (선택)
    var basicUser: String? = nil
}

// MARK: - 시스템

struct SystemInfo: Decodable {
    var hostname: String?
    var version: String?
    var uptime: String?
    var systemProduct: String?
    var physmem: Double?
    var cpuModel: String?
    var cores: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostname = try? c.decodeIfPresent(String.self, forKey: .hostname)
        version = try? c.decodeIfPresent(String.self, forKey: .version)
        uptime = try? c.decodeIfPresent(String.self, forKey: .uptime)
        systemProduct = try? c.decodeIfPresent(String.self, forKey: .systemProduct)
        cpuModel = try? c.decodeIfPresent(String.self, forKey: .cpuModel)
        cores = try? c.decodeIfPresent(Int.self, forKey: .cores)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .physmem) {
            physmem = d
        } else if let i = try? c.decodeIfPresent(Int64.self, forKey: .physmem) {
            physmem = Double(i)
        }
    }
    enum CodingKeys: String, CodingKey {
        case hostname, version, uptime, physmem
        case cpuModel = "model"
        case cores
        case systemProduct = "system_product"
    }
}

struct CPUStat: Decodable {
    var model: String?
    var data: [Double]?   // 사용률 샘플(%)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        if let nums = try? c.decodeIfPresent([Double].self, forKey: .data) {
            data = nums
        } else if let asInt = try? c.decodeIfPresent([Int].self, forKey: .data) {
            data = asInt.map { Double($0) }
        } else {
            data = nil
        }
    }
    enum CodingKeys: String, CodingKey { case model, data }
}

struct MemoryUsage: Decodable {
    var usage: [String: Double] = [:]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let dict = try? c.decodeIfPresent([String: Double].self, forKey: .usage) {
            usage = dict
        } else if let dictInt = try? c.decodeIfPresent([String: Int].self, forKey: .usage) {
            usage = dictInt.mapValues { Double($0) }
        }
    }
    enum CodingKeys: String, CodingKey { case usage }
}

struct Alert: Decodable {
    // v25.10 (/alert/list): id/uuid는 문자열(예: '9667585f-...'), severity는 level 필드,
    // 본문은 formatted(없으면 text) 필드를 쓴다.
    var id: String?
    var klass: String?
    var alert: String?
    var severity: String?
    var dismissed: Bool?
    var datetime: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decodeIfPresent(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
            id = "\(i)"
        }
        klass = try? c.decodeIfPresent(String.self, forKey: .klass)
        alert = (try? c.decodeIfPresent(String.self, forKey: .formatted)) ?? nil
            ?? (try? c.decodeIfPresent(String.self, forKey: .text))
            ?? (try? c.decodeIfPresent(String.self, forKey: .alert))
        severity = (try? c.decodeIfPresent(String.self, forKey: .level)) ?? nil
            ?? (try? c.decodeIfPresent(String.self, forKey: .severity))
        dismissed = try? c.decodeIfPresent(Bool.self, forKey: .dismissed)
        datetime = try? c.decodeIfPresent(String.self, forKey: .datetime)
    }
    enum CodingKeys: String, CodingKey {
        case id, klass, alert, severity, dismissed, datetime
        case formatted, text, level
    }
}

// MARK: - 풀

struct Pool: Decodable {
    var id: Int?
    var name: String?
    var status: String?
    var size: Int?
    var allocated: Int?
    var free: Int?
    var fragmentation: Double?
    var healthy: Bool?
    var autotrim: String?
    var topology: PoolTopology?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        if let l = try? c.decodeIfPresent(Int64.self, forKey: .size) { size = Int(l) }
        if let l = try? c.decodeIfPresent(Int64.self, forKey: .allocated) { allocated = Int(l) }
        if let l = try? c.decodeIfPresent(Int64.self, forKey: .free) { free = Int(l) }
        fragmentation = try? c.decodeIfPresent(Double.self, forKey: .fragmentation) ?? nil
        healthy = try? c.decodeIfPresent(Bool.self, forKey: .healthy)
        autotrim = try? c.decodeIfPresent(String.self, forKey: .autotrim)
        topology = try? c.decodeIfPresent(PoolTopology.self, forKey: .topology)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, status, size, allocated, free, fragmentation, healthy, autotrim, topology
    }
}

struct PoolTopology: Decodable {
    var data: [PoolDisk]?
    var log: [PoolDisk]?
    var cache: [PoolDisk]?
    var spare: [PoolDisk]?
}

struct PoolDisk: Decodable {
    var name: String?
    var path: String?
    var type: String?
    var status: String?
    var children: [PoolDisk]?
}

// MARK: - 데이터셋

struct Dataset: Decodable {
    var name: String?
    var type: String?
    var pool: String?
}

// MARK: - 공유 (SMB)

struct SMBShare: Decodable {
    var id: Int
    var name: String
    var path: String?
    var purpose: String?
    var comment: String?
    var enabled: Bool?
    var locked: Bool?
    var home: Bool?
}

// MARK: - 공유 (NFS)

struct NFSShare: Decodable {
    var id: Int
    var dsNfs: NFSPath?
    var networks: [String]?
    var hosts: [String]?
    var ro: Bool?
    var enabled: Bool?
    var aliases: [String]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        dsNfs = try? c.decodeIfPresent(NFSPath.self, forKey: .dsNfs)
        networks = try? c.decodeIfPresent([String].self, forKey: .networks)
        hosts = try? c.decodeIfPresent([String].self, forKey: .hosts)
        ro = try? c.decodeIfPresent(Bool.self, forKey: .ro)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        if let a = try? c.decodeIfPresent([String].self, forKey: .aliases) { aliases = a }
    }
    enum CodingKeys: String, CodingKey {
        case id, networks, hosts, ro, enabled
        case dsNfs = "ds_nfs"
        case aliases
    }
}

struct NFSPath: Decodable {
    var path: String?
}

// MARK: - 스냅샷

struct Snapshot: Decodable {
    var name: String?
    var dataset: String?
    var snapshotName: String?
    var takenAt: Int?       // epoch seconds (flexible)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        dataset = try? c.decodeIfPresent(String.self, forKey: .dataset)
        snapshotName = try? c.decodeIfPresent(String.self, forKey: .snapshotName)
        if let i = try? c.decodeIfPresent(Int64.self, forKey: .takenAt) {
            takenAt = Int(i)
        } else if (try? c.decodeIfPresent(String.self, forKey: .takenAt)) != nil {
            // ISO8601이 오면 무시(epoch만 지원)
            takenAt = nil
        }
    }
    enum CodingKeys: String, CodingKey {
        case name, dataset
        case snapshotName = "snapshot_name"
        case takenAt = "taken_at"
    }
}

struct ReplicationTask: Decodable {
    var id: Int
    var name: String?
    var enabled: Bool?
    var direction: String?
    var targetDataset: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        direction = try? c.decodeIfPresent(String.self, forKey: .direction)
        targetDataset = try? c.decodeIfPresent(String.self, forKey: .targetDataset)
    }
    enum CodingKeys: String, CodingKey {
        case id, name, enabled, direction
        case targetDataset = "target_dataset"
    }
}

// MARK: - 사용자

struct NasUser: Decodable {
    var id: Int?
    var username: String?
    var uid: Int?
    var fullName: String?
    var shell: String?
    var home: String?
    var smb: Bool?
    var group: UserGroup?
    var groups: [UserGroup]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        if let i = try? c.decodeIfPresent(Int.self, forKey: .uid) {
            uid = i
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .uid) {
            uid = Int(s)
        }
        fullName = try? c.decodeIfPresent(String.self, forKey: .fullName)
        shell = try? c.decodeIfPresent(String.self, forKey: .shell)
        home = try? c.decodeIfPresent(String.self, forKey: .home)
        smb = try? c.decodeIfPresent(Bool.self, forKey: .smb)
        group = try? c.decodeIfPresent(UserGroup.self, forKey: .group)
        groups = try? c.decodeIfPresent([UserGroup].self, forKey: .groups)
    }
    enum CodingKeys: String, CodingKey {
        case id, username, uid, shell, home, smb, group, groups
        case fullName = "full_name"
    }
}

struct UserGroup: Decodable {
    var gid: Int?
    var group: String?
}
