import Foundation

/// Simple terminal command execution service
/// All responses are JSON-parsable for easy AI processing
final class TerminalService {
    // MARK: - JSON Response Types

    struct CommandResult: Codable {
        let success: Bool
        let command: String
        let output: String
        let error: String?
        let exitCode: Int32
        let executionTimeMs: Int
    }

    // MARK: - Tool Definition for AI

    /// Returns the tool definition in OpenAI function calling format
    static var toolDefinition: [String: Any] {
        return [
            "type": "function",
            "function": [
                "name": "execute_terminal_command",
                "description": """
                Execute a terminal/shell command on the user's macOS computer.
                Use this for file operations (ls, cat, mkdir, rm), git commands, brew, npm, python, or any CLI tool.

                IMPORTANT: Follow the agentic workflow:
                1. ALWAYS check prerequisites first (file exists, command available)
                2. Execute the main action
                3. Verify the result

                Returns JSON with: success (bool), output (stdout), error (stderr), exitCode, purpose.
                """,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The shell command to execute (e.g., 'ls -la', 'git status', 'rm file.txt')",
                        ],
                        "workingDirectory": [
                            "type": "string",
                            "description": "Optional working directory path. Defaults to user's home directory.",
                        ],
                        "purpose": [
                            "type": "string",
                            "description": """
                            Brief description of why this command is being run. Must be one of:
                            - 'checking' (verifying prerequisites)
                            - 'executing' (main action)
                            - 'verifying' (confirming result)
                            Example: 'Checking if config.json exists'
                            """,
                        ],
                    ],
                    "required": ["command", "purpose"],
                ],
            ],
        ]
    }

    // MARK: - Execution

    /// Execute a terminal command and return JSON-parsable result
    func execute(
        command: String,
        workingDirectory: String? = nil,
        timeout: TimeInterval = 30
    ) async -> CommandResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let directory = workingDirectory.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser

        // Inherit user's environment (PATH, etc.)
        var environment = ProcessInfo.processInfo.environment
        // Ensure common paths are available
        if let path = environment["PATH"] {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        }
        do {
            // This remains the separately confirmed advanced shell tool. Ordinary utility
            // actions use typed requests and selected executables instead of shell source.
            let result = try await UtilityProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-c", command],
                workingDirectory: directory,
                environment: environment,
                timeout: timeout,
                maxOutputBytes: 65_536
            )
            var output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.outputTruncated {
                output += "\n[Command output was truncated at 65,536 bytes per stream.]"
            }
            let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandResult(
                success: result.succeeded,
                command: command,
                output: output,
                error: errorOutput.isEmpty ? nil : errorOutput,
                exitCode: result.exitCode,
                executionTimeMs: Int(result.executionTime * 1_000)
            )
        } catch is CancellationError {
            return CommandResult(
                success: false,
                command: command,
                output: "",
                error: "Command cancelled.",
                exitCode: -2,
                executionTimeMs: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            )
        } catch {
            return CommandResult(
                success: false,
                command: command,
                output: "",
                error: "Failed to execute: \(error.localizedDescription)",
                exitCode: -1,
                executionTimeMs: Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            )
        }
    }

    /// Convert result to JSON string for AI processing
    func resultToJSON(_ result: CommandResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(result),
           let json = String(data: data, encoding: .utf8)
        {
            return json
        }

        // Fallback: always return valid JSON (avoid manual string interpolation of output)
        let fallbackPayload: [String: Any] = [
            "success": result.success,
            "output": result.output,
            "exitCode": Int(result.exitCode),
        ]

        if let data = try? JSONSerialization.data(withJSONObject: fallbackPayload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8)
        {
            return json
        }

        // If serialization fails for any reason, return minimal safe JSON
        return #"{"success":false,"output":"<json-serialization-failed>","exitCode":-1}"#
    }
}
