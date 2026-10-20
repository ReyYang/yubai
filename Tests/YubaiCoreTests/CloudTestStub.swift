import Foundation
@testable import YubaiCore

/// Intercepts only this stub's host, so tests exercise cloud requests without network access.
final class CloudTestStub {
    let backend: CloudBackend
    private let session: URLSession
    private let host: String

    init(reply: @escaping (URLRequest) throws -> String) {
        let host = UUID().uuidString.lowercased() + ".yubai.test"
        CloudTestURLProtocol.register(reply, for: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        self.host = host
        self.session = session
        backend = CloudBackend(
            client: DeepSeekClient(configuration: DeepSeekConfiguration(
                apiKey: "test-key", baseURL: URL(string: "https://" + host)!
            )),
            session: session
        )
    }

    func close() {
        session.invalidateAndCancel()
        CloudTestURLProtocol.unregister(host)
    }

    static func messages(in request: URLRequest) throws -> [[String: String]] {
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
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = payload["messages"] as? [[String: String]]
        else { throw URLError(.cannotDecodeContentData) }
        return messages
    }
}

private final class CloudTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var replies: [String: (URLRequest) throws -> String] = [:]

    static func register(_ reply: @escaping (URLRequest) throws -> String, for host: String) {
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
            let content = try reply(request)
            let data = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content]]]
            ])
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
