import Foundation

public struct ApiContentRack: Sendable {
    public var id: UUID = UUID()
    public var arguments: [String: String] = [String: String]()

    public init(id: UUID = UUID(), arguments: [String: String] = [String: String]()) {
        self.id = id
        self.arguments = arguments
    }
}

public enum HttpMethod: String, Codable, CaseIterable, Sendable {
    case get = "GET"
    case post = "POST"
}

public enum ContentType: String, Codable, CaseIterable, Sendable {
    case page = "PAGE"
    case text = "TEXT"
    case base64image = "BASE64_IMAGE"
    case urlImage = "URL_IMAGE"

    public var displayName: String {
        switch self {
        case .page:
            return "Page"
        case .text:
            return "Text"
        case .base64image:
            return "Base64 Image"
        case .urlImage:
            return "URL Image"
        }
    }
}

public struct CodableExtraData: Codable, Equatable, @unchecked Sendable {
    public var data: [String: Any]

    public init(data: [String: Any]) {
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var dataContainer = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)

        for (key, value) in data {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            try encodeValue(value, into: &dataContainer, forKey: codingKey)
        }
    }

    private func encodeValue(_ value: Any,
                             into container: inout KeyedEncodingContainer<DynamicCodingKeys>,
                             forKey codingKey: DynamicCodingKeys) throws {
        switch value {
        case is NSNull:
            try container.encodeNil(forKey: codingKey)

        case let v as Int:
            try container.encode(v, forKey: codingKey)
        case let v as Double:
            try container.encode(v, forKey: codingKey)
        case let v as String:
            try container.encode(v, forKey: codingKey)
        case let v as Bool:
            try container.encode(v, forKey: codingKey)

        case let v as [Any]:
            var nestedUnkeyedContainer = container.nestedUnkeyedContainer(forKey: codingKey)
            for element in v {
                try encodeUnkeyedValue(element, into: &nestedUnkeyedContainer)
            }

        case let v as [String: Any]:
            var nestedContainer = container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: codingKey)
            for (nestedKey, nestedValue) in v {
                let nestedCodingKey = DynamicCodingKeys(stringValue: nestedKey)!
                try encodeValue(nestedValue, into: &nestedContainer, forKey: nestedCodingKey)
            }

        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: container.codingPath + [codingKey],
                                      debugDescription: "Invalid value in CodableExtraData")
            )
        }
    }

    /// Recursively encodes any element inside an array
    private func encodeUnkeyedValue(_ value: Any,
                                    into container: inout UnkeyedEncodingContainer) throws {
        switch value {
        case is NSNull:
            try container.encodeNil()

        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as Bool:
            try container.encode(v)

        case let v as [Any]:
            var nestedUnkeyedContainer = container.nestedUnkeyedContainer()
            for element in v {
                try encodeUnkeyedValue(element, into: &nestedUnkeyedContainer)
            }

        case let v as [String: Any]:
            var nestedContainer = container.nestedContainer(keyedBy: DynamicCodingKeys.self)
            for (nestedKey, nestedValue) in v {
                let nestedCodingKey = DynamicCodingKeys(stringValue: nestedKey)!
                try encodeValue(nestedValue, into: &nestedContainer, forKey: nestedCodingKey)
            }

        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: container.codingPath,
                                      debugDescription: "Invalid value in array within CodableExtraData")
            )
        }
    }

    // MARK: - Decodable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
        self.data = try Self.decodeDictionary(from: dataContainer)
    }

    private static func decodeDictionary(from container: KeyedDecodingContainer<DynamicCodingKeys>) throws -> [String: Any] {
        var result: [String: Any] = [:]

        for key in container.allKeys {
            if try container.decodeNil(forKey: key) {
                result[key.stringValue] = NSNull()
                continue
            }

            // Attempt to decode all possible types
            if let intValue = try? container.decode(Int.self, forKey: key) {
                result[key.stringValue] = intValue
            } else if let doubleValue = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = doubleValue
            } else if let boolValue = try? container.decode(Bool.self, forKey: key) {
                result[key.stringValue] = boolValue
            } else if let stringValue = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = stringValue
            } else if var unkeyedContainer = try? container.nestedUnkeyedContainer(forKey: key) {
                // decode array
                result[key.stringValue] = try decodeArray(from: &unkeyedContainer)
            } else if let nestedContainer = try? container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: key) {
                // decode dictionary
                result[key.stringValue] = try decodeDictionary(from: nestedContainer)
            } else {
                throw DecodingError.dataCorruptedError(forKey: key,
                    in: container,
                    debugDescription: "Invalid value for key \(key.stringValue) in CodableExtraData"
                )
            }
        }

        return result
    }

    private static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
        var result: [Any] = []

        while !container.isAtEnd {
            if try container.decodeNil() {
                result.append(NSNull())
                continue
            }

            if let intValue = try? container.decode(Int.self) {
                result.append(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                result.append(doubleValue)
            } else if let boolValue = try? container.decode(Bool.self) {
                result.append(boolValue)
            } else if let stringValue = try? container.decode(String.self) {
                result.append(stringValue)
            } else if var nestedUnkeyedContainer = try? container.nestedUnkeyedContainer() {
                // nested array
                result.append(try decodeArray(from: &nestedUnkeyedContainer))
            } else if let nestedContainer = try? container.nestedContainer(keyedBy: DynamicCodingKeys.self) {
                // nested dictionary
                result.append(try decodeDictionary(from: nestedContainer))
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid array element in CodableExtraData.")
            }
        }

        return result
    }

    public static func == (lhs: CodableExtraData, rhs: CodableExtraData) -> Bool {
        return NSDictionary(dictionary: lhs.data).isEqual(to: rhs.data)
    }

    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = "\(intValue)"
        }
    }
}

public extension CodableExtraData {
    func value<T>(for key: String) -> T? {
        return data[key] as? T
    }
}

public struct ApiContent: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String = String()
    public var endpoint: String = String()
    public var method: HttpMethod = .get
    public var headers: [String: String] = [String: String]()
    public var body: String = String()
    public var arguments: [String: String] = [String: String]()
    public var contentType: ContentType = .text
    public var description: String?
    public var extraData: CodableExtraData?
    public var lastModified: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String = "",
        endpoint: String = "",
        method: HttpMethod = .get,
        headers: [String: String] = [String: String](),
        body: String = "",
        arguments: [String: String] = [String: String](),
        contentType: ContentType = .text,
        description: String? = nil,
        extraData: [String: Any]? = nil,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.method = method
        self.headers = headers
        self.body = body
        self.arguments = arguments
        self.contentType = contentType
        self.description = description
        self.extraData = extraData != nil ? CodableExtraData(data: extraData!) : nil
        self.lastModified = lastModified
    }

    init() {
        self.id = UUID()
        self.name = "New API"
        self.endpoint = String()
        self.method = .get
        self.headers = [String: String]()
        self.body = String()
        self.arguments = [String: String]()
        self.contentType = .text
        self.description = nil
        self.extraData = nil
        self.lastModified = Date()
    }

    func isValid() -> Bool {
        return !name.isEmpty && !endpoint.isEmpty
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ApiContent, rhs: ApiContent) -> Bool {
        return lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.endpoint == rhs.endpoint &&
            lhs.method == rhs.method &&
            lhs.headers == rhs.headers &&
            lhs.body == rhs.body &&
            lhs.arguments == rhs.arguments &&
            lhs.contentType == rhs.contentType &&
            lhs.description == rhs.description &&
            lhs.description == rhs.description &&
            lhs.extraData == rhs.extraData &&
            lhs.lastModified == rhs.lastModified
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpoint
        case method
        case headers
        case body
        case arguments
        case contentType
        case description
        case extraData
        case lastModified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.endpoint = try container.decode(String.self, forKey: .endpoint)
        self.method = try container.decode(HttpMethod.self, forKey: .method)
        self.headers = try container.decode([String: String].self, forKey: .headers)
        self.body = try container.decode(String.self, forKey: .body)
        self.arguments = try container.decode([String: String].self, forKey: .arguments)
        self.contentType = try container.decode(ContentType.self, forKey: .contentType)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.extraData = try container.decodeIfPresent(CodableExtraData.self, forKey: .extraData)
        self.lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.name, forKey: .name)
        try container.encode(self.endpoint, forKey: .endpoint)
        try container.encode(self.method, forKey: .method)
        try container.encode(self.headers, forKey: .headers)
        try container.encode(self.body, forKey: .body)
        try container.encode(self.arguments, forKey: .arguments)
        try container.encode(self.contentType, forKey: .contentType)
        try container.encodeIfPresent(self.description, forKey: .description)
        try container.encodeIfPresent(self.extraData, forKey: .extraData)
        try container.encode(self.lastModified, forKey: .lastModified)
    }
}

public extension ApiContent {
    struct Data: Codable, Equatable, Sendable {
        public var id: UUID = UUID()
        public var name: String = String()
        public var endpoint: String = String()
        public var method: HttpMethod = .get
        public var headers: [String: String] = [String: String]()
        public var body: String = String()
        public var arguments: [String: String] = [String: String]()
        public var contentType: ContentType = .text
        public var description: String?
        public var extraData: CodableExtraData?
        public var lastModified: Date = Date()

        public func isValid() -> Bool {
            return !name.isEmpty && !endpoint.isEmpty
        }

        public init() {
            self.id = UUID()
            self.name = ""
            self.endpoint = ""
            self.method = .get
            self.headers = [:]
            self.body = ""
            self.arguments = [:]
            self.contentType = .text
            self.description = nil
            self.extraData = nil
            self.lastModified = Date()
        }

        public init(
            id: UUID = UUID(),
            name: String = "",
            endpoint: String = "",
            method: HttpMethod = .get,
            headers: [String: String] = [String: String](),
            body: String = "",
            arguments: [String: String] = [String: String](),
            contentType: ContentType = .text,
            description: String? = nil,
            extraData: [String: Any]? = nil,
            lastModified: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.endpoint = endpoint
            self.method = method
            self.headers = headers
            self.body = body
            self.arguments = arguments
            self.contentType = contentType
            self.description = description
            self.extraData = extraData != nil ? CodableExtraData(data: extraData!) : nil
            self.lastModified = lastModified
        }
    }

    var data: Data {
        return Data(
            id: self.id,
            name: self.name,
            endpoint: self.endpoint,
            method: self.method,
            headers: self.headers,
            body: self.body,
            arguments: self.arguments,
            contentType: self.contentType,
            description: self.description,
            extraData: self.extraData?.data,
            lastModified: self.lastModified
        )
    }

    mutating func update(from data: Data) {
        self.id = data.id
        self.name = data.name
        self.endpoint = data.endpoint
        self.method = data.method
        self.headers = data.headers
        self.body = data.body
        self.arguments = data.arguments
        self.contentType = data.contentType
        self.description = data.description
        self.extraData = data.extraData
        self.lastModified = data.lastModified
    }

    init(from data: Data) {
        self.id = data.id
        self.name = data.name
        self.endpoint = data.endpoint
        self.method = data.method
        self.headers = data.headers
        self.body = data.body
        self.arguments = data.arguments
        self.contentType = data.contentType
        self.description = data.description
        self.extraData = data.extraData
        self.lastModified = data.lastModified
    }
}
