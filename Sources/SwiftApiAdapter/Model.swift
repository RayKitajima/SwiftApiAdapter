import Foundation

public struct ApiContentRack {
    var id: UUID = UUID()
    public var arguments: [String: String] = [String: String]()
}

public enum HttpMethod: String, Codable, CaseIterable {
    case get = "GET"
    case post = "POST"
}

public enum ContentType: String, Codable, CaseIterable {
    case text = "TEXT"
    case base64image = "BASE64_IMAGE"
    case urlImage = "URL_IMAGE"
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

    public init(
        id: UUID = UUID(),
        name: String = "",
        endpoint: String = "",
        method: HttpMethod = .get,
        headers: [String: String] = [String: String](),
        body: String = "",
        arguments: [String: String] = [String: String](),
        contentType: ContentType = .text,
        description: String? = nil
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
            lhs.description == rhs.description
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
    }
}

public extension ApiContent {
    struct Data: Codable {
        public var id: UUID = UUID()
        public var name: String = String()
        public var endpoint: String = String()
        public var method: HttpMethod = .get
        public var headers: [String: String] = [String: String]()
        public var body: String = String()
        public var arguments: [String: String] = [String: String]()
        public var contentType: ContentType = .text
        public var description: String?

        public func isValid() -> Bool {
            return !name.isEmpty && !endpoint.isEmpty
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
            description: self.description
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
    }
}
