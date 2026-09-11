import Foundation

nonisolated enum MAITranscriptionRequest {
    enum Style: String, CaseIterable { case verbatim, clean }

    static func endpoint(resource: String) throws -> URL {
        let value = resource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = value.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: ".cognitiveservices.azure.com", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !name.isEmpty, name.count <= 63,
              name.range(of: "^[a-z0-9][a-z0-9-]*[a-z0-9]$", options: .regularExpression) != nil,
              let url = URL(string: "https://\(name).cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15")
        else { throw failure("Enter your Azure Speech resource name, such as my-speech-resource.") }
        return url
    }

    static func make(samples: [Float], resource: String, key: String, style: Style = .verbatim, openRouter: Bool = false, boundary: String = UUID().uuidString) throws -> URLRequest {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("Add your API key in the MAI connection settings.") }
        guard !samples.isEmpty, samples.count <= 149_000_000 else { throw failure("Audio is empty or exceeds the 300 MB upload limit.") }
        guard samples.allSatisfy(\.isFinite) else { throw failure("Audio contains invalid samples.") }
        var wav = Data()
        func string(_ value: String) { wav.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { wav.append(contentsOf: $0) } }
        let length = UInt32(samples.count * 2)
        string("RIFF"); u32(36 + length); string("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16); string("data"); u32(length)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            u16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        if openRouter {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "microsoft/mai-transcribe-2",
                "input_audio": ["data": wav.base64EncodedString(), "format": "wav"],
                "provider": ["options": ["azure": ["enhancedMode": ["modelOptions": ["transcribeStyle": style.rawValue]]]]]
            ])
            return request
        }
        let definitionData = try JSONSerialization.data(withJSONObject: [
            "enhancedMode": ["enabled": true, "model": "MAI-Transcribe-2",
                             "modelOptions": ["transcribeStyle": style.rawValue]]
        ])
        let definition = String(decoding: definitionData, as: UTF8.self)
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"definition\"\r\nContent-Type: application/json\r\n\r\n\(definition)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(wav); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try endpoint(resource: resource))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func text(from data: Data, status: Int, openRouter: Bool = false) throws -> String {
        let provider = openRouter ? "OpenRouter" : "Azure"
        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw failure("\(provider) rejected the key or access. Check your MAI configuration.")
            case 429: throw failure("\(provider)'s transcription quota is busy. Please try again later.")
            default: throw failure("\(provider) transcription failed (HTTP \(status)).")
            }
        }
        if openRouter {
            struct RouterResponse: Decodable { let text: String }
            guard let response = try? JSONDecoder().decode(RouterResponse.self, from: data) else {
                throw failure("OpenRouter returned an unexpected transcription response.")
            }
            return response.text
        }
        struct Response: Decodable { struct Phrase: Decodable { let text: String }; let combinedPhrases: [Phrase] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw failure("Azure returned an unexpected transcription response.") }
        return response.combinedPhrases.map(\.text).joined(separator: " ")
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "SayStone.MAI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
