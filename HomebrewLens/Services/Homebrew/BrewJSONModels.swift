import Foundation

struct BrewInfoPayload: Decodable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]

    enum CodingKeys: String, CodingKey {
        case formulae
        case casks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = try container.decodeIfPresent([BrewFormula].self, forKey: .formulae) ?? []
        casks = try container.decodeIfPresent([BrewCask].self, forKey: .casks) ?? []
    }
}

struct BrewFormula: Decodable {
    let name: String
    let fullName: String?
    let description: String?
    let homepage: String?
    let license: FlexibleLicense?
    let tap: String?
    let versions: BrewVersions?
    let installed: [BrewFormulaInstall]?
    let dependencies: [String]?
    let runtimeDependencies: [BrewRuntimeDependency]?
    let pinned: Bool?
    let deprecated: Bool?
    let disabled: Bool?
    let kegOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description = "desc"
        case homepage
        case license
        case tap
        case versions
        case installed
        case dependencies
        case runtimeDependencies = "runtime_dependencies"
        case pinned
        case deprecated
        case disabled
        case kegOnly = "keg_only"
    }
}

struct BrewFormulaInstall: Decodable {
    let version: String?
    let installedOnRequest: Bool?
    let installedAsDependency: Bool?
    let time: Double?

    enum CodingKeys: String, CodingKey {
        case version
        case installedOnRequest = "installed_on_request"
        case installedAsDependency = "installed_as_dependency"
        case time
    }
}

struct BrewRuntimeDependency: Decodable {
    let fullName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
    }
}

struct BrewCask: Decodable {
    let token: String?
    let name: FlexibleStringList?
    let version: String?
    let description: FlexibleStringList?
    let homepage: String?
    let tap: String?
    let installed: String?
    let outdated: Bool?
    let artifacts: [BrewCaskArtifact]?

    enum CodingKeys: String, CodingKey {
        case token
        case name
        case version
        case description = "desc"
        case homepage
        case tap
        case installed
        case outdated
        case artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(String.self, forKey: .token)
        name = try container.decodeIfPresent(FlexibleStringList.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = try container.decodeIfPresent(FlexibleStringList.self, forKey: .description)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        tap = try container.decodeIfPresent(String.self, forKey: .tap)
        installed = try container.decodeIfPresent(String.self, forKey: .installed)
        outdated = try container.decodeIfPresent(Bool.self, forKey: .outdated)
        artifacts = try container
            .decodeIfPresent([LossyDecodable<BrewCaskArtifact>].self, forKey: .artifacts)?
            .compactMap(\.value)
    }
}

struct BrewCaskArtifact: Decodable, Equatable {
    let apps: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        apps = Self.artifactStrings(for: "app", in: container)
    }

    private static func artifactStrings(
        for key: String,
        in container: KeyedDecodingContainer<DynamicCodingKey>
    ) -> [String] {
        guard let codingKey = DynamicCodingKey(stringValue: key) else {
            return []
        }

        if let value = try? container.decode(String.self, forKey: codingKey) {
            return [value]
        }
        if let values = try? container.decode([String].self, forKey: codingKey) {
            return values
        }
        if let entries = try? container.decode([BrewCaskArtifactEntry].self, forKey: codingKey) {
            return entries.compactMap(\.path)
        }
        if let entry = try? container.decode(BrewCaskArtifactEntry.self, forKey: codingKey),
           let path = entry.path {
            return [path]
        }

        return []
    }
}

private struct BrewCaskArtifactEntry: Decodable, Equatable {
    let path: String?

    init(from decoder: Decoder) throws {
        if let value = try? String(from: decoder) {
            path = value
            return
        }

        guard let container = try? decoder.container(keyedBy: DynamicCodingKey.self) else {
            path = nil
            return
        }

        if let targetKey = DynamicCodingKey(stringValue: "target"),
           let target = try? container.decode(String.self, forKey: targetKey) {
            path = target
        } else if let pathKey = DynamicCodingKey(stringValue: "path"),
                  let decodedPath = try? container.decode(String.self, forKey: pathKey) {
            path = decodedPath
        } else {
            path = nil
        }
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

struct BrewVersions: Decodable {
    let stable: String?
}

struct BrewOutdatedPayload: Decodable {
    let formulae: [BrewOutdatedPackage]
    let casks: [BrewOutdatedPackage]

    enum CodingKeys: String, CodingKey {
        case formulae
        case casks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = try container.decodeIfPresent([BrewOutdatedPackage].self, forKey: .formulae) ?? []
        casks = try container.decodeIfPresent([BrewOutdatedPackage].self, forKey: .casks) ?? []
    }
}

struct BrewOutdatedPackage: Decodable {
    let name: String?
    let installedVersions: [String]?
    let currentVersion: String?
    let pinned: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
    }
}

enum FlexibleLicense: Decodable, Equatable {
    case text(String)

    var text: String {
        switch self {
        case let .text(value):
            value
        }
    }

    init(from decoder: Decoder) throws {
        if let value = try? String(from: decoder) {
            self = .text(value)
        } else if let values = try? [String](from: decoder) {
            self = .text(values.joined(separator: ", "))
        } else {
            self = .text("")
        }
    }
}

enum FlexibleStringList: Decodable, Equatable {
    case values([String])

    var firstText: String {
        switch self {
        case let .values(values):
            values.first ?? ""
        }
    }

    var joinedText: String {
        switch self {
        case let .values(values):
            values.joined(separator: ", ")
        }
    }

    init(from decoder: Decoder) throws {
        if let value = try? String(from: decoder) {
            self = .values([value])
        } else if let values = try? [String](from: decoder) {
            self = .values(values)
        } else {
            self = .values([])
        }
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
