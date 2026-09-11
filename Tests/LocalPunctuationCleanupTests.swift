import Foundation
@main struct Tests {
    static func main() async {
        precondition(LocalPunctuationCleanup.accepts(original: "please send the report", candidate: "Please send the report."))
        for pair in [
            ("Thursday no Friday", "Thursday."),
            ("Do not deploy", "Do deploy."),
            ("The cost is 1,245.67", "The cost is 1.24567."),
            ("Keep customer_id", "Keep customer_ID"),
            ("What time is it", "It is noon."),
            ("Keep $40", "Keep 40."),
            ("Keep ERI-482", "Keep ERI 482")
        ] { precondition(!LocalPunctuationCleanup.accepts(original: pair.0, candidate: pair.1)) }
        if CommandLine.arguments.contains("--live") {
            for text in ["please send the report", "Schedule it Thursday no Friday", "Keep customer_id and SF_TARGET_ORG unchanged.", "Do not deploy to production."] {
                let start = Date()
                let output = await LocalPunctuationCleanup.clean(text)
                precondition(LocalPunctuationCleanup.accepts(original: text, candidate: output))
                print(String(format:"%.3fs", Date().timeIntervalSince(start)), output)
            }
        }
        print("PASS: punctuation acceptance and lexical/number/identifier/negation guards")
    }
}
