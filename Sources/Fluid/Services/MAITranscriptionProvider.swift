import Foundation

final class MAITranscriptionProvider: TranscriptionProvider {
    enum Route: String, CaseIterable { case openRouter, azure }
    static var route: Route {
        Route(rawValue: UserDefaults.standard.string(forKey: "SayStoneMAIRoute") ?? "") ?? .azure
    }
    static var style: MAITranscriptionRequest.Style {
        MAITranscriptionRequest.Style(rawValue: UserDefaults.standard.string(forKey: "SayStoneMAIStyle") ?? "") ?? .verbatim
    }
    static func keyID(for route: Route) -> String {
        route == .openRouter ? "saystone-openrouter-speech" : keyID
    }
    static let keyID = "saystone-azure-speech"
    static let resourceDefaultsKey = "SayStoneAzureSpeechResource"
    static var resource: String { UserDefaults.standard.string(forKey: resourceDefaultsKey) ?? "" }
    static var isConfigured: Bool {
        (route == .openRouter || (try? MAITranscriptionRequest.endpoint(resource: resource)) != nil) && KeychainService.shared.containsKey(for: keyID(for: route))
    }
    let name = "MAI-Transcribe-2"
    var isAvailable: Bool { true }
    var isReady: Bool { Self.isConfigured }
    func modelsExistOnDisk() -> Bool { Self.isConfigured }
    var shouldClearCacheAfterCancellation: Bool { false }
    func prepare(progressHandler: ((ModelPreparationProgress) -> Void)?) async throws {
        if Self.route == .azure { _ = try MAITranscriptionRequest.endpoint(resource: Self.resource) }
        guard Self.isConfigured else { throw MAITranscriptionRequest.failure("Configure your MAI connection and key in Voice Engine settings.") }
    }
    func transcribe(_ samples: [Float]) async throws -> ASRTranscriptionResult {
        try Task.checkCancellation()
        guard !samples.isEmpty else { return ASRTranscriptionResult(text: "") }
        let route = Self.route
        let style = Self.style
        let key = try KeychainService.shared.fetchKey(for: Self.keyID(for: route)) ?? ""
        let request = try MAITranscriptionRequest.make(samples: samples, resource: Self.resource, key: key, style: style, openRouter: route == .openRouter)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: NoTranscriptionRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let text = try MAITranscriptionRequest.text(from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0, openRouter: route == .openRouter)
        return ASRTranscriptionResult(text: text, confidence: 0)
    }
}

private final nonisolated class NoTranscriptionRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
