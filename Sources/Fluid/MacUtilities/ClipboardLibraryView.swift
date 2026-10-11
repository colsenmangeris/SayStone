import SwiftUI

/// Copy and paste use the shared action dispatcher supplied by the host window.
struct ClipboardLibraryView: View {
    @Environment(\.theme) private var theme
    @ObservedObject var library: ClipboardLibrary
    let onCopy: (String) -> Void
    let onPaste: (String) -> Void

    @State private var section: Section = .snippets
    @State private var query = ""
    @State private var editorRequest: SnippetEditorRequest?
    @State private var isClearConfirmationPresented = false
    @State private var excludedAppDraft = ""
    @State private var transformation: UtilityTextTransform = .trim
    @State private var transformationInput = ""

    private enum Section: String, CaseIterable {
        case snippets = "Snippets"
        case history = "History"
        case transform = "Transform text"
    }

    private struct SnippetEditorRequest: Identifiable {
        let id = UUID()
        let snippet: ClipboardSnippet?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spacing.md) {
            HStack {
                Text("Clipboard library")
                    .font(theme.typography.title)
                Spacer()
                if section == .snippets {
                    Button("New snippet", systemImage: "plus") {
                        editorRequest = SnippetEditorRequest(snippet: nil)
                    }
                    .accessibilityIdentifier("clipboard.newSnippet")
                }
            }
            Picker("Library section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("clipboard.section")

            if let error = library.lastError {
                Text(error).foregroundStyle(theme.palette.warning).font(theme.typography.caption)
                    .accessibilityIdentifier("clipboard.error")
            }
            switch section {
            case .snippets: snippetsContent
            case .history: historyContent
            case .transform: transformContent
            }
        }
        .padding(theme.metrics.spacing.lg)
        .foregroundStyle(theme.palette.primaryText)
        .background(theme.palette.contentBackground)
        .sheet(item: $editorRequest) { request in
            ClipboardSnippetEditor(library: library, snippet: request.snippet)
                .id(request.id)
        }
        .confirmationDialog("Clear all clipboard history?", isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { library.clearHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saved snippets are kept. Clipboard history is removed from this app's local storage.")
        }
    }

    private var searchField: some View {
        TextField("Search text", text: $query)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("clipboard.search")
    }

    private var snippetsContent: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spacing.sm) {
            searchField
            Text("Save text you use often. Pinned snippets appear first.")
                .font(theme.typography.caption).foregroundStyle(theme.palette.secondaryText)
            List {
                ForEach(library.matchingSnippets(query)) { snippet in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            library.setPinned(!snippet.isPinned, id: snippet.id)
                        } label: {
                            Image(systemName: snippet.isPinned ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.borderless)
                        .help(snippet.isPinned ? "Unpin snippet" : "Pin snippet")
                        .accessibilityLabel(snippet.isPinned ? "Unpin \(snippet.title)" : "Pin \(snippet.title)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.title).font(theme.typography.bodyStrong)
                            Text(snippet.text).font(theme.typography.caption)
                                .foregroundStyle(theme.palette.secondaryText).lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        copyPasteButtons(text: snippet.text, identifier: "clipboard.snippet.\(snippet.id)")
                        Menu {
                            Button("Edit") {
                                editorRequest = SnippetEditorRequest(snippet: snippet)
                            }
                            .accessibilityIdentifier("clipboard.snippet.\(snippet.id).edit")
                            Button("Delete snippet", role: .destructive) { library.removeSnippet(id: snippet.id) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .accessibilityLabel("Options for \(snippet.title)")
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("clipboard.snippet.\(snippet.id)")
                }
                if library.matchingSnippets(query).isEmpty {
                    Text(query.isEmpty ? "No saved snippets. Choose New snippet to add one." : "No matching snippets.")
                        .foregroundStyle(theme.palette.secondaryText)
                }
            }
            .listStyle(.inset)
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spacing.sm) {
            Toggle("Collect clipboard history on this Mac", isOn: Binding(
                get: { library.options.isEnabled }, set: { library.setHistoryEnabled($0) }
            ))
            .accessibilityIdentifier("clipboard.historyEnabled")
            Text("Off by default. After enabling, newly copied text is saved locally. Concealed, transient and generated items are skipped. Unmarked sensitive text may be saved; add apps to the exclusions below.")
                .font(theme.typography.caption).foregroundStyle(theme.palette.secondaryText)
            HStack {
                Picker("Keep for", selection: optionBinding(\.retentionDays)) {
                    ForEach([1, 3, 7, 14, 30], id: \.self) { Text("\($0) \($0 == 1 ? "day" : "days")").tag($0) }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("clipboard.retentionDays")
                Picker("Maximum items", selection: optionBinding(\.maximumItems)) {
                    ForEach([25, 50, 100, 250, 500], id: \.self) { Text("\($0)").tag($0) }
                }
                .frame(maxWidth: 220)
                .accessibilityIdentifier("clipboard.maximumItems")
                Spacer()
                Button("Clear history", role: .destructive) { isClearConfirmationPresented = true }
                    .disabled(library.history.isEmpty)
                    .accessibilityIdentifier("clipboard.clearHistory")
            }
            exclusionsContent
            Divider()
            searchField
            List {
                ForEach(library.matchingHistory(query)) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text).font(theme.typography.bodySmall).lineLimit(3)
                            HStack {
                                Text(item.capturedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                if let source = item.sourceBundleIdentifier ?? item.observedBundleIdentifier, !source.isEmpty {
                                    Text(source).lineLimit(1)
                                }
                            }
                            .font(theme.typography.captionSmall).foregroundStyle(theme.palette.secondaryText)
                        }
                        Spacer(minLength: 12)
                        copyPasteButtons(text: item.text, identifier: "clipboard.history.\(item.id)")
                        Button {
                            editorRequest = SnippetEditorRequest(snippet: ClipboardSnippet(id: UUID(), title: "Saved text", text: item.text, isPinned: true, updatedAt: Date()))
                        } label: { Image(systemName: "pin") }
                        .help("Save as snippet")
                        .accessibilityLabel("Save as snippet")
                        Button(role: .destructive) { library.removeHistoryEntry(id: item.id) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove history item")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("clipboard.history.\(item.id)")
                }
                if library.matchingHistory(query).isEmpty {
                    Text(library.options.isEnabled ? "Newly copied text will appear here." : "History collection is off.")
                        .foregroundStyle(theme.palette.secondaryText)
                }
            }
            .listStyle(.inset)
        }
    }

    private var exclusionsContent: some View {
        DisclosureGroup("Excluded apps (\(library.options.excludedBundleIdentifiers.count))") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter an app's bundle identifier, for example com.example.Editor. Exclusions use available clipboard source markers and the foreground app. Adding an exclusion removes matching stored entries.")
                    .font(theme.typography.caption).foregroundStyle(theme.palette.secondaryText)
                HStack {
                    TextField("App bundle identifier", text: $excludedAppDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("clipboard.excludedApp")
                    Button("Add") {
                        var options = library.options
                        options.excludedBundleIdentifiers.insert(excludedAppDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        library.updateOptions(options)
                        excludedAppDraft = ""
                    }
                    .disabled(!ClipboardLibrary.isValidBundleIdentifier(excludedAppDraft.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .accessibilityIdentifier("clipboard.addExclusion")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(library.options.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in
                            HStack {
                                Text(identifier).font(theme.typography.caption)
                                Spacer()
                                Button("Remove") {
                                    var options = library.options
                                    options.excludedBundleIdentifiers.remove(identifier)
                                    library.updateOptions(options)
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("clipboard.exclusions")
    }

    private var transformContent: some View {
        VStack(alignment: .leading, spacing: theme.metrics.spacing.sm) {
            Picker("Transformation", selection: $transformation) {
                ForEach(UtilityTextTransform.allCases, id: \.self) { Text(transformTitle($0)).tag($0) }
            }
            .accessibilityIdentifier("clipboard.transformation")
            Text("Enter text to preview a local transformation.")
                .font(theme.typography.caption).foregroundStyle(theme.palette.secondaryText)
            PromptTextView(text: $transformationInput, allowsAutomaticTextSubstitution: false, accessibilityID: "clipboard.transformInput")
                .frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.separator))
                .onChange(of: transformationInput) { _, newValue in
                    if newValue.count > ClipboardLibrary.maximumSnippetCharacters {
                        transformationInput = String(newValue.prefix(ClipboardLibrary.maximumSnippetCharacters))
                    }
                }
            Text("Preview").font(theme.typography.sectionTitle)
            ScrollView {
                Text(transformation.apply(to: transformationInput))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 130)
            .background(theme.palette.cardBackground, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("clipboard.transformPreview")
            HStack {
                Spacer()
                copyPasteButtons(text: transformation.apply(to: transformationInput), identifier: "clipboard.transform")
            }
        }
    }

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<ClipboardHistoryOptions, Value>) -> Binding<Value> {
        Binding(get: { library.options[keyPath: keyPath] }, set: { value in
            var options = library.options
            options[keyPath: keyPath] = value
            library.updateOptions(options)
        })
    }

    private func copyPasteButtons(text: String, identifier: String) -> some View {
        HStack(spacing: 8) {
            Button("Copy") { onCopy(text) }
                .accessibilityIdentifier("\(identifier).copy")
            Button("Paste") { onPaste(text) }
                .accessibilityIdentifier("\(identifier).paste")
        }
        .disabled(text.isEmpty)
        .buttonStyle(.bordered)
    }

    private func transformTitle(_ transform: UtilityTextTransform) -> String {
        switch transform {
        case .trim: return "Trim surrounding whitespace"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .collapseWhitespace: return "Collapse whitespace"
        case .removeLineBreaks: return "Remove line breaks"
        }
    }
}

private struct ClipboardSnippetEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: ClipboardLibrary
    let snippetID: UUID?
    @State private var title: String
    @State private var text: String
    @State private var isPinned: Bool

    init(library: ClipboardLibrary, snippet: ClipboardSnippet?) {
        self.library = library
        // A history item can prefill a new snippet without reusing its identity.
        snippetID = snippet.flatMap { library.lookupSnippet(id: $0.id)?.id }
        _title = State(initialValue: snippet?.title ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _isPinned = State(initialValue: snippet?.isPinned ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(snippetID == nil ? "New snippet" : "Edit snippet").font(theme.typography.sectionTitle)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("clipboard.editorTitle")
                .onChange(of: title) { _, value in
                    if value.count > 120 { title = String(value.prefix(120)) }
                }
            PromptTextView(text: $text, allowsAutomaticTextSubstitution: false, accessibilityID: "clipboard.editorText")
                .frame(minHeight: 170)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.palette.separator))
                .onChange(of: text) { _, value in
                    if value.count > ClipboardLibrary.maximumSnippetCharacters {
                        text = String(value.prefix(ClipboardLibrary.maximumSnippetCharacters))
                    }
                }
            HStack {
                Toggle("Pin snippet", isOn: $isPinned)
                Spacer()
                Text("\(text.count)/\(ClipboardLibrary.maximumSnippetCharacters)")
                    .font(theme.typography.caption).foregroundStyle(theme.palette.secondaryText)
            }
            if let error = library.lastError {
                Text(error).font(theme.typography.caption).foregroundStyle(theme.palette.warning)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if library.saveSnippet(id: snippetID, title: title, text: text, isPinned: isPinned) != nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || text.isEmpty || text.count > ClipboardLibrary.maximumSnippetCharacters)
                .accessibilityIdentifier("clipboard.editorSave")
            }
        }
        .padding(20)
        .frame(width: 500)
        .foregroundStyle(theme.palette.primaryText)
        .background(theme.palette.contentBackground)
    }
}
