import Foundation

@main struct MAITranscriptionRequestTests {
    static func main() throws {
        let request = try MAITranscriptionRequest.make(samples: [-2, 0, 2], resource: "my-speech", key: "test-key", boundary: "test-boundary")
        precondition(request.url?.host == "my-speech.cognitiveservices.azure.com")
        precondition(request.url?.query == "api-version=2025-10-15")
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "test-key")
        let data = request.httpBody!
        let text = String(decoding: data, as: UTF8.self)
        precondition(text.contains(#""model":"MAI-Transcribe-2""#))
        precondition(text.contains(#""transcribeStyle":"verbatim""#))
        let riff = data.range(of: Data("RIFF".utf8))!.lowerBound
        precondition(Array(data[(riff + 44)..<(riff + 50)]) == [1, 128, 0, 0, 255, 127])
        precondition(text.hasSuffix("--test-boundary--\r\n"))
        for value in ["http://example.com", "example.com", "my-speech?secret=x", "", "https://my-speech.cognitiveservices.azure.com.evil.test"] {
            do { _ = try MAITranscriptionRequest.endpoint(resource: value); fatalError("Accepted invalid resource") } catch {}
        }
        for samples: [Float] in [[], [.nan], [.infinity]] {
            do { _ = try MAITranscriptionRequest.make(samples: samples, resource: "my-speech", key: "key"); fatalError("Accepted invalid audio") } catch {}
        }
        let response = Data(#"{"combinedPhrases":[{"text":"Hello."},{"text":"Second phrase."}]}"#.utf8)
        let transcript = try MAITranscriptionRequest.text(from: response, status: 200)
        precondition(transcript == "Hello. Second phrase.")
        for status in [401, 403, 429, 500] {
            do { _ = try MAITranscriptionRequest.text(from: response, status: status); fatalError("Accepted failed response") } catch {}
        }
        do { _ = try MAITranscriptionRequest.text(from: Data("{}".utf8), status: 200); fatalError("Accepted malformed response") } catch {}
        print("PASS: Azure endpoint validation, WAV clipping/header, multipart model/style, schema and HTTP errors")
    }
}
