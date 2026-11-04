import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import YubaiCore

/// Intercepts only this stub's host, so tests exercise cloud requests without network access.
final class CloudTestStub {
    let backend: CloudBackend
    private let session: URLSession
    private let host: String

    init(rawResponse: Bool = false, statusCode: Int = 200, sendLog: SendLog = .shared, basePath: String = "", model: String = DeepSeekConfiguration.defaultModel, headers: [String: String] = [:], responseStatus: (() -> Int)? = nil,
         catalogReply: ((URLRequest) throws -> String)? = nil, catalogStatus: Int = 200,
         retrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }, reply: @escaping (URLRequest) throws -> String) {
        let host = UUID().uuidString.lowercased() + ".yubai.test"
        CloudTestURLProtocol.register({ request in
            // Organization's bounded discovery is separate from explicit model-menu tests.
            if request.url?.lastPathComponent == "models", request.timeoutInterval <= 5 {
                return (Data(try (catalogReply?(request) ?? "{}").utf8), catalogReply == nil ? 503 : catalogStatus, [:])
            }
            let content = try reply(request)
            let statusCode = responseStatus?() ?? statusCode
            if rawResponse { return (Data(content.utf8), statusCode, headers) }
            return (try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]]), statusCode, headers)
        }, for: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        self.host = host
        self.session = session
        backend = CloudBackend(
            client: DeepSeekClient(configuration: DeepSeekConfiguration(
                apiKey: "test-key", baseURL: URL(string: "https://" + host + basePath)!, model: model
            ), sendLog: sendLog, retrySleep: retrySleep, retryJitter: { 0.5 }),
            session: session
        )
    }

    func close() {
        session.invalidateAndCancel()
        CloudTestURLProtocol.unregister(host)
    }

    func send(_ request: ChatRequest) async throws -> ChatMessage {
        try await backend.client.send(request, session: session)
    }

    func listModels() async throws -> [String] {
        try await backend.client.listModels(session: session)
    }

    static func messages(in request: URLRequest) throws -> [[String: String]] {
        guard let messages = try payload(in: request)["messages"] as? [[String: String]] else { throw URLError(.cannotDecodeContentData) }
        return messages
    }

    static func payload(in request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            let capacity = 1024
            var buffer = [UInt8](repeating: 0, count: capacity)
            while true {
                let count = stream.read(&buffer, maxLength: capacity)
                guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw URLError(.cannotDecodeContentData) }
        return payload
    }
}

private final class CloudTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var replies: [String: (URLRequest) throws -> (Data, Int, [String: String])] = [:]

    static func register(_ reply: @escaping (URLRequest) throws -> (Data, Int, [String: String]), for host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = reply
    }

    static func unregister(_ host: String) {
        lock.lock(); defer { lock.unlock() }
        replies.removeValue(forKey: host)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let reply = Self.replies[request.url?.host ?? ""]
        Self.lock.unlock()
        do {
            guard let reply, let url = request.url else { throw URLError(.unsupportedURL) }
            let (data, status, headers) = try reply(request)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
