import AppKit
import Darwin
import Foundation

// Read-only launch/focus receipt. Records no window text, user input or clipboard.
// Run before launching the review copy. App control belongs exclusively to CUA.
let arguments = CommandLine.arguments
guard arguments.count == 3, let duration = Double(arguments[2]), duration > 0, duration <= 1800 else {
    fatalError("Usage: observe-review-focus <new-private-jsonl-file> <seconds-up-to-1800>")
}
let output = URL(fileURLWithPath: arguments[1])
let descriptor = open(output.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
guard descriptor >= 0 else { fatalError("Could not exclusively create private receipt") }
let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
defer { try? file.close() }
let workspace = NSWorkspace.shared
let targetIdentifier = "com.architech.saystone.development"
var targetEverFrontmost = false

func record(_ event: String, activated: NSRunningApplication? = nil) {
    let frontmost = workspace.frontmostApplication
    let isTarget = frontmost?.bundleIdentifier == targetIdentifier
    let activationIsTarget = activated?.bundleIdentifier == targetIdentifier
    targetEverFrontmost = targetEverFrontmost || isTarget || activationIsTarget
    let targets = workspace.runningApplications.filter { $0.bundleIdentifier == targetIdentifier }.map {
        ["pid": $0.processIdentifier, "appPath": $0.bundleURL?.path ?? "", "active": $0.isActive] as [String: Any]
    }
    let item: [String: Any] = [
        "time": ISO8601DateFormatter().string(from: Date()),
        "event": event,
        "frontmostPID": frontmost?.processIdentifier ?? -1,
        "targetFrontmost": isTarget,
        "targetActivated": activationIsTarget,
        "targetEverFrontmost": targetEverFrontmost,
        "targets": targets,
    ]
    do {
        try file.write(contentsOf: JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]))
        try file.write(contentsOf: Data([10]))
        try file.synchronize()
    } catch { fatalError("Could not persist focus receipt: \(error)") }
}

let observer = workspace.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { notification in
    record("activation", activated: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
}
let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in record("poll") }
// This is the launch-ready signal: the activation observer is already installed.
record("started")
RunLoop.main.run(until: Date().addingTimeInterval(duration))
timer.invalidate()
workspace.notificationCenter.removeObserver(observer)
record("finished")
if targetEverFrontmost { exit(2) }
