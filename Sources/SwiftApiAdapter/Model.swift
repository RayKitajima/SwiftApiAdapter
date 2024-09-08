import Foundation

public struct ApiContentRack {
    public var id: UUID = UUID()
    public var arguments: [String: String] = [String: String]()

    public init(id: UUID = UUID(), arguments: [String: String] = [String: String]()) {
        self.id = id
        self.arguments = arguments
    }
}

public enum HttpMethod: String, Codable, CaseIterable {
    case get = "GET"
    case post = "POST"
}

public enum ContentType: String, Codable, CaseIterable {
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

public struct CodableExtraData: Codable, Equatable {
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
            if let intValue = value as? Int {
                try dataContainer.encode(intValue, forKey: codingKey)
            } else if let doubleValue = value as? Double {
                try dataContainer.encode(doubleValue, forKey: codingKey)
            } else if let stringValue = value as? String {
                try dataContainer.encode(stringValue, forKey: codingKey)
            } else if let boolValue = value as? Bool {
                try dataContainer.encode(boolValue, forKey: codingKey)
            } else if value is NSNull {
                try dataContainer.encodeNil(forKey: codingKey)
            } else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [codingKey], debugDescription: "Invalid value"))
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dataContainer = try container.nestedContainer(keyedBy: DynamicCodingKeys.self, forKey: .data)
        var data: [String: Any] = [:]
        for key in dataContainer.allKeys {
            if let intValue = try? dataContainer.decode(Int.self, forKey: key) {
                data[key.stringValue] = intValue
            } else if let doubleValue = try? dataContainer.decode(Double.self, forKey: key) {
                data[key.stringValue] = doubleValue
            } else if let stringValue = try? dataContainer.decode(String.self, forKey: key) {
                data[key.stringValue] = stringValue
            } else if let boolValue = try? dataContainer.decode(Bool.self, forKey: key) {
                data[key.stringValue] = boolValue
            } else if try dataContainer.decodeNil(forKey: key) {
                print("decodeNil: \(key)")
                data[key.stringValue] = NSNull()
            } else {
                throw DecodingError.dataCorruptedError(forKey: key, in: dataContainer, debugDescription: "Invalid value")
            }
        }
        self.data = data
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


public struct ApiContent: Identifiable, Codable, Equatable, Hashable {
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
        extraData: [String: Any]? = nil
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
            lhs.extraData == rhs.extraData
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
    }
}

public extension ApiContent {
    struct Data: Codable, Equatable {
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
            extraData: [String: Any]? = nil
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
            extraData: self.extraData?.data
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
    }
}
