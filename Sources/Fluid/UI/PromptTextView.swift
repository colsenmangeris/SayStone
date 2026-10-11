import AppKit
import SwiftUI

/// A lightweight macOS-native text view that reliably renders bound text immediately,
/// avoiding occasional `TextEditor` refresh glitches in sheets.
struct PromptTextView: NSViewRepresentable {
    @Binding var text: String

    var isEditable: Bool = true
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    var contentInset: CGFloat = 10
    var allowsAutomaticTextSubstitution: Bool = true
    var accessibilityID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = PromptNativeTextView()
        textView.isRichText = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.isEditable = self.isEditable && context.environment.isEnabled
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = self.font
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: self.contentInset, height: self.contentInset)
        textView.textContainer?.lineFragmentPadding = 0

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        self.configureLiteralEditing(textView)

        textView.string = self.text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Keep AppKit view in sync with SwiftUI state.
        // This is the critical bit that avoids "blank until focus changes" behavior.
        if textView.string != self.text {
            let selectedRanges = textView.selectedRanges
            textView.string = self.text
            textView.selectedRanges = selectedRanges
        }

        let editable = self.isEditable && context.environment.isEnabled
        if textView.isEditable != editable { textView.isEditable = editable }
        self.configureLiteralEditing(textView)
        textView.isSelectable = true
        textView.drawsBackground = false
        if textView.font != self.font { textView.font = self.font }
        if textView.textContainerInset != NSSize(width: self.contentInset, height: self.contentInset) {
            textView.textContainerInset = NSSize(width: self.contentInset, height: self.contentInset)
        }
        if textView.textContainer?.lineFragmentPadding != 0 {
            textView.textContainer?.lineFragmentPadding = 0
        }
    }

    private func configureLiteralEditing(_ textView: NSTextView) {
        textView.setAccessibilityIdentifier(self.accessibilityID)
        (textView as? PromptNativeTextView)?.preservesLiteralSpaces = !self.allowsAutomaticTextSubstitution
        guard !self.allowsAutomaticTextSubstitution else { return }
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.inlinePredictionType = .no
        textView.mathExpressionCompletionType = .no
        textView.enabledTextCheckingTypes = 0
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if self.text.wrappedValue != textView.string {
                self.text.wrappedValue = textView.string
            }
        }
    }
}

/// AppKit's system double-space period replacement has no per-view switch.
/// Literal utility editing inserts spaces directly, retaining normal input
/// interpretation for shortcuts and marked text such as an active IME.
private final class PromptNativeTextView: NSTextView {
    var preservesLiteralSpaces = false

    override func keyDown(with event: NSEvent) {
        guard self.preservesLiteralSpaces, event.characters == " ",
              event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              !self.hasMarkedText() else {
            super.keyDown(with: event)
            return
        }
        self.insertText(" ", replacementRange: self.selectedRange())
    }
}
