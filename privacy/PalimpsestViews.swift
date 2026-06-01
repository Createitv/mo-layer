import SwiftData
import SwiftUI
import UIKit

struct PalimpsestCoverView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var gesturePoints: [GesturePoint] = []

    private var content: DecoyNotesContent { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NotesSearchBar(text: .constant(""), placeholder: content.copy.searchPlaceholder)

                    NotesGestureEntrySurface(points: $gesturePoints) { points in
                        auth.openFromDisguiseGesture(points)
                    } label: {
                        NotesQuickNoteRow(copy: content.copy)
                    }

                    NotesSectionHeader(title: content.copy.pinnedTitle)

                    VStack(spacing: 0) {
                        let previewNotes = content.previewNotes
                        ForEach(previewNotes) { note in
                            DecoyNoteRow(note: note)
                            if let last = previewNotes.last, note.id != last.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(content.copy.appName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(DecoyNotesTheme.accent)
                }
            }
        }
    }
}

private struct NotesGestureEntrySurface<Label: View>: View {
    @Binding var points: [GesturePoint]
    let onComplete: ([GesturePoint]) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        GeometryReader { proxy in
            label()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            points.append(
                                GesturePoint(
                                    x: min(max(value.location.x / max(proxy.size.width, 1), 0), 1),
                                    y: min(max(value.location.y / max(proxy.size.height, 1), 0), 1),
                                    t: Date().timeIntervalSinceReferenceDate
                                )
                            )
                        }
                        .onEnded { _ in
                            onComplete(points)
                            points = []
                        }
                )
        }
        .frame(height: 82)
    }
}

struct DecoyVaultView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DecoyNotesHomeView()
            .onChange(of: scenePhase) { _, phase in
                if auth.shouldLock(for: phase) {
                    auth.lock()
                }
            }
    }
}

private struct DecoyNotesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @Query(sort: \DecoyNoteRecord.updatedAt, order: .reverse) private var records: [DecoyNoteRecord]
    @State private var searchText = ""
    @State private var editingNote: DecoyNoteRecord?
    @State private var showNewNote = false
    @State private var showSettings = false
    @State private var showResetGesture = false
    @State private var isLoading = false

    private var content: DecoyNotesContent { .current }

    private var allNotes: [DecoyNoteDisplay] {
        records.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder > rhs.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }.compactMap { record in
            guard record.deletedAt == nil,
                  let payload = vaultStore.decoyNotePayload(for: record) else {
                return nil
            }
            return DecoyNoteDisplay(record: record, payload: payload)
        }
    }

    private var filteredNotes: [DecoyNoteDisplay] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allNotes }
        return allNotes.filter { $0.matches(query) }
    }

    private var pinnedNotes: [DecoyNoteDisplay] {
        filteredNotes.filter(\.isPinned)
    }

    private var regularNotes: [DecoyNoteDisplay] {
        filteredNotes.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NotesSearchBar(text: $searchText, placeholder: content.copy.searchPlaceholder)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if isLoading && allNotes.isEmpty {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else if filteredNotes.isEmpty {
                    Section {
                        ContentUnavailableView(
                            searchText.isEmpty ? content.copy.emptyTitle : content.copy.noResultsTitle,
                            systemImage: "note.text",
                            description: Text(searchText.isEmpty ? content.copy.emptyDetail : content.copy.noResultsDetail)
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if !pinnedNotes.isEmpty {
                        notesSection(title: content.copy.pinnedTitle, notes: pinnedNotes)
                    }
                    notesSection(title: content.copy.todayTitle, notes: regularNotes)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(content.copy.appName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .foregroundStyle(DecoyNotesTheme.accent)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    if subscription.canImportAndSync {
                        Button {
                            showNewNote = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .tint(DecoyNotesTheme.accent)
            .sheet(item: $editingNote) { note in
                DecoyNoteEditorView(note: note, copy: content.copy)
            }
            .sheet(isPresented: $showNewNote) {
                DecoyNoteEditorView(note: nil, copy: content.copy)
            }
            .sheet(isPresented: $showSettings) {
                DecoyNotesSettingsView(
                    copy: content.copy,
                    resetAction: { showResetGesture = true },
                    lockAction: { auth.lock() }
                )
            }
            .sheet(isPresented: $showResetGesture) {
                GestureResetView()
            }
            .task {
                await loadDecoyNotes()
            }
            .onChange(of: language) { _, _ in }
        }
    }

    private func notesSection(title: String, notes: [DecoyNoteDisplay]) -> some View {
        Section(title) {
            ForEach(notes) { note in
                Button {
                    if subscription.canImportAndSync {
                        editingNote = note.record
                    }
                } label: {
                    DecoyNoteRow(note: note)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if subscription.canImportAndSync {
                        Button {
                            guard let record = note.record else { return }
                            Task { await vaultStore.toggleDecoyPin(record, context: modelContext, sync: sync) }
                        } label: {
                            Label(note.isPinned ? content.copy.unpinButton : content.copy.pinButton, systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(DecoyNotesTheme.accent)
                    }
                }
            }
            .onDelete { offsets in
                guard subscription.canImportAndSync else { return }
                deleteNotes(at: offsets, in: notes)
            }
            .onMove { source, destination in
                guard subscription.canImportAndSync else { return }
                Task {
                    await vaultStore.reorderDecoyNotes(
                        notes.compactMap(\.record),
                        from: source,
                        to: destination,
                        context: modelContext,
                        sync: sync
                    )
                }
            }
        }
    }

    private func deleteNotes(at offsets: IndexSet, in notes: [DecoyNoteDisplay]) {
        Task {
            for index in offsets {
                if let record = notes[index].record {
                    await vaultStore.deleteDecoyNote(record, context: modelContext, sync: sync)
                }
            }
        }
    }

    @MainActor
    private func loadDecoyNotes() async {
        isLoading = true
        defer { isLoading = false }
        vaultStore.setWriteAccess(subscription.canImportAndSync)
        await sync.checkAccountStatus()
        await vaultStore.pullCloudDecoyNotes(context: modelContext, sync: sync)
        if subscription.canImportAndSync {
            await vaultStore.ensureDefaultDecoyNotes(content.defaultNotes, context: modelContext, sync: sync)
            await vaultStore.syncPendingDecoyNotes(context: modelContext, sync: sync)
        }
    }
}

private struct NotesSearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "mic.fill")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct NotesQuickNoteRow: View {
    let copy: DecoyNotesCopy

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DecoyNotesTheme.accent)
                .frame(width: 36, height: 36)
                .background(DecoyNotesTheme.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(copy.quickNoteTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(copy.quickNotePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NotesSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }
}

private struct DecoyNoteRow: View {
    let note: DecoyNoteDisplay

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(DecoyNotesTheme.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DecoyNotesTheme.accent)
                    }
                }
                Text("\(note.modified)  \(note.preview)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DecoyNoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var subscription: SubscriptionManager
    let note: DecoyNoteRecord?
    let copy: DecoyNotesCopy
    @State private var title: String
    @State private var bodyText: String
    @State private var folder: String
    @State private var todos: [DecoyTodoPayload]
    @State private var isPinned: Bool
    @State private var showDeleteConfirmation = false

    init(note: DecoyNoteRecord?, copy: DecoyNotesCopy) {
        self.note = note
        self.copy = copy
        let payload: DecoyNotePayload? = note.flatMap { record in
            guard let rootKey = try? VaultCryptoService.ensureRootKey() else { return nil }
            return try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: record.encryptedPayload, using: rootKey)
        }
        _title = State(initialValue: payload?.title ?? "")
        _bodyText = State(initialValue: payload?.body ?? "")
        _folder = State(initialValue: payload?.folder ?? copy.defaultFolder)
        _todos = State(initialValue: payload?.todos ?? [])
        _isPinned = State(initialValue: note?.isPinned ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(copy.titlePlaceholder, text: $title)
                        .font(.headline)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                    TextField(copy.folderPlaceholder, text: $folder)
                }

                Section(copy.checklistTitle) {
                    ForEach(todos.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Button {
                                todos[index].done.toggle()
                            } label: {
                                Image(systemName: todos[index].done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todos[index].done ? DecoyNotesTheme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                            TextField(copy.checklistPlaceholder, text: $todos[index].text)
                        }
                    }
                    .onDelete { offsets in
                        todos.remove(atOffsets: offsets)
                    }

                    Button {
                        todos.append(DecoyTodoPayload(text: "", done: false))
                    } label: {
                        Label(copy.addChecklistItem, systemImage: "plus.circle")
                    }
                }

                Section {
                    Toggle(isOn: $isPinned) {
                        Label(copy.pinButton, systemImage: "pin")
                    }
                }

                if note != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(copy.deleteButton, systemImage: "trash")
                        }
                    }
                }
            }
            .disabled(!subscription.canImportAndSync)
            .navigationTitle(note == nil ? copy.newNoteTitle : copy.editNoteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copy.cancelButton) { dismiss() }
                }
                if subscription.canImportAndSync {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(copy.doneButton) {
                            Task { await saveAndDismiss() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(copy.deleteButton, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(copy.deleteButton, role: .destructive) {
                    Task { await deleteAndDismiss() }
                }
                Button(copy.cancelButton, role: .cancel) {}
            }
        }
    }

    @MainActor
    private func saveAndDismiss() async {
        guard subscription.canImportAndSync else { return }
        var cleanedTodos = todos
            .map { DecoyTodoPayload(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), done: $0.done) }
            .filter { !$0.text.isEmpty }
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = trimmedBody.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? (fallbackTitle?.isEmpty == false ? fallbackTitle! : copy.untitledNote) : trimmedTitle
        let finalFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? copy.defaultFolder : folder.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBody.isEmpty && cleanedTodos.isEmpty && trimmedTitle.isEmpty && note == nil {
            dismiss()
            return
        }

        if !trimmedBody.isEmpty && cleanedTodos.isEmpty && bodyText.localizedCaseInsensitiveContains("- [ ]") {
            cleanedTodos = bodyText
                .components(separatedBy: .newlines)
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- [ ]") }
                .map { line in
                    DecoyTodoPayload(text: line.replacingOccurrences(of: "- [ ]", with: "").trimmingCharacters(in: .whitespacesAndNewlines), done: false)
                }
        }

        let payload = DecoyNotePayload(title: finalTitle, body: bodyText, folder: finalFolder, todos: cleanedTodos)
        if let note {
            await vaultStore.updateDecoyNote(note, payload: payload, isPinned: isPinned, context: modelContext, sync: sync)
        } else {
            await vaultStore.createDecoyNote(payload: payload, isPinned: isPinned, context: modelContext, sync: sync)
        }
        dismiss()
    }

    @MainActor
    private func deleteAndDismiss() async {
        guard subscription.canImportAndSync else { return }
        if let note {
            await vaultStore.deleteDecoyNote(note, context: modelContext, sync: sync)
        }
        dismiss()
    }
}

private struct DecoyNotesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let copy: DecoyNotesCopy
    let resetAction: () -> Void
    let lockAction: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.settingsTitle) {
                    Label(copy.localNotesLabel, systemImage: "iphone")
                    Label(copy.autoLockLabel, systemImage: "lock")
                    Label(copy.sortingLabel, systemImage: "arrow.up.arrow.down")
                    Label(copy.encryptedSyncLabel, systemImage: "checkmark.icloud")
                }

                LanguagePickerSection()

                Section(copy.maintenanceTitle) {
                    Button(copy.resetGestureButton) {
                        dismiss()
                        resetAction()
                    }
                    Button(copy.closeButton) {
                        dismiss()
                        lockAction()
                    }
                }
            }
            .navigationTitle(copy.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copy.doneButton) { dismiss() }
                }
            }
        }
    }
}

private struct DecoyNoteDisplay: Identifiable {
    let record: DecoyNoteRecord?
    let id: String
    let title: String
    let preview: String
    let modified: String
    let folder: String
    let isPinned: Bool
    let todos: [DecoyTodoPayload]
    let updatedAt: Date

    init(record: DecoyNoteRecord, payload: DecoyNotePayload) {
        self.record = record
        self.id = record.id
        self.title = payload.title.isEmpty ? DecoyNotesContent.current.copy.untitledNote : payload.title
        self.preview = DecoyNoteDisplay.preview(for: payload)
        self.modified = DecoyNoteDisplay.modifiedText(for: record.updatedAt)
        self.folder = payload.folder
        self.isPinned = record.isPinned
        self.todos = payload.todos
        self.updatedAt = record.updatedAt
    }

    init(id: String, payload: DecoyNotePayload, isPinned: Bool, updatedAt: Date = Date()) {
        self.record = nil
        self.id = id
        self.title = payload.title
        self.preview = DecoyNoteDisplay.preview(for: payload)
        self.modified = DecoyNoteDisplay.modifiedText(for: updatedAt)
        self.folder = payload.folder
        self.isPinned = isPinned
        self.todos = payload.todos
        self.updatedAt = updatedAt
    }

    var icon: String {
        todos.isEmpty ? "note.text" : "checklist"
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || preview.localizedCaseInsensitiveContains(query)
            || folder.localizedCaseInsensitiveContains(query)
            || todos.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private static func preview(for payload: DecoyNotePayload) -> String {
        let bodyPreview = payload.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let bodyPreview {
            return bodyPreview
        }
        let todoPreview = payload.todos.map(\.text).filter { !$0.isEmpty }.prefix(3).joined(separator: ", ")
        return todoPreview.isEmpty ? DecoyNotesContent.current.copy.emptyPreview : todoPreview
    }

    private static func modifiedText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct DecoyNotesCopy {
    let appName: String
    let searchPlaceholder: String
    let pinnedTitle: String
    let todayTitle: String
    let quickNoteTitle: String
    let quickNotePreview: String
    let settingsTitle: String
    let localNotesLabel: String
    let autoLockLabel: String
    let sortingLabel: String
    let encryptedSyncLabel: String
    let maintenanceTitle: String
    let resetGestureButton: String
    let closeButton: String
    let newNoteTitle: String
    let editNoteTitle: String
    let titlePlaceholder: String
    let bodyPlaceholder: String
    let folderPlaceholder: String
    let defaultFolder: String
    let checklistTitle: String
    let checklistPlaceholder: String
    let addChecklistItem: String
    let deleteButton: String
    let pinButton: String
    let unpinButton: String
    let doneButton: String
    let cancelButton: String
    let emptyTitle: String
    let emptyDetail: String
    let noResultsTitle: String
    let noResultsDetail: String
    let untitledNote: String
    let emptyPreview: String
}

private struct DecoyNotesContent {
    let copy: DecoyNotesCopy
    let defaultNotes: [(id: String, payload: DecoyNotePayload, isPinned: Bool)]

    var previewNotes: [DecoyNoteDisplay] {
        defaultNotes.prefix(4).map { note in
            DecoyNoteDisplay(id: note.id, payload: note.payload, isPinned: note.isPinned)
        }
    }

    static var current: DecoyNotesContent {
        localizedFromStrings()
    }

    private static func localizedFromStrings() -> DecoyNotesContent {
        DecoyNotesContent(
            copy: DecoyNotesCopy(
                appName: L.string("Notes"),
                searchPlaceholder: L.string("Search"),
                pinnedTitle: L.string("Pinned"),
                todayTitle: L.string("Today"),
                quickNoteTitle: L.string("Daily Notes"),
                quickNotePreview: L.string("Groceries, messages, and follow-ups"),
                settingsTitle: L.string("Notes Settings"),
                localNotesLabel: L.string("On My iPhone Notes"),
                autoLockLabel: L.string("Lock when leaving app"),
                sortingLabel: L.string("Drag notes to reorder"),
                encryptedSyncLabel: L.string("Encrypted iCloud Notes"),
                maintenanceTitle: L.string("Account"),
                resetGestureButton: L.string("Reset Gesture"),
                closeButton: L.string("Close Notes"),
                newNoteTitle: L.string("New Note"),
                editNoteTitle: L.string("Edit Note"),
                titlePlaceholder: L.string("Title"),
                bodyPlaceholder: L.string("Note"),
                folderPlaceholder: L.string("Folder"),
                defaultFolder: L.string("Notes"),
                checklistTitle: L.string("Checklist"),
                checklistPlaceholder: L.string("List item"),
                addChecklistItem: L.string("Add Checklist Item"),
                deleteButton: L.string("Delete Note"),
                pinButton: L.string("Pin"),
                unpinButton: L.string("Unpin"),
                doneButton: L.string("Done"),
                cancelButton: L.string("Cancel"),
                emptyTitle: L.string("No Notes"),
                emptyDetail: L.string("Tap compose to create a note."),
                noResultsTitle: L.string("No Results"),
                noResultsDetail: L.string("Try a different search."),
                untitledNote: L.string("New Note"),
                emptyPreview: L.string("No additional text")
            ),
            defaultNotes: [
                (
                    id: "default-today",
                    payload: DecoyNotePayload(title: L.string("Today"), body: "", folder: L.string("Notes"), todos: [
                        DecoyTodoPayload(id: "today-electricity", text: L.string("Pay electricity bill before 6 PM"), done: true),
                        DecoyTodoPayload(id: "today-mom", text: L.string("Call Mom after lunch"), done: false),
                        DecoyTodoPayload(id: "today-delivery", text: L.string("Confirm package delivery window"), done: false)
                    ]),
                    isPinned: true
                ),
                (
                    id: "default-dinner",
                    payload: DecoyNotePayload(title: L.string("Dinner"), body: L.string("Bring fruit tonight.\nArrive around 7.\nMake noodles first."), folder: L.string("Personal"), todos: []),
                    isPinned: true
                ),
                (
                    id: "default-cleanup",
                    payload: DecoyNotePayload(title: L.string("Weekly cleanup"), body: "", folder: L.string("Home"), todos: [
                        DecoyTodoPayload(id: "cleanup-laundry", text: L.string("Laundry"), done: true),
                        DecoyTodoPayload(id: "cleanup-receipts", text: L.string("Sort receipts"), done: false),
                        DecoyTodoPayload(id: "cleanup-desk", text: L.string("Clean desk drawer"), done: false),
                        DecoyTodoPayload(id: "cleanup-cable", text: L.string("Find backup cable"), done: false)
                    ]),
                    isPinned: false
                ),
                (
                    id: "default-meeting",
                    payload: DecoyNotePayload(title: L.string("Meeting notes"), body: L.string("Keep the import flow simple.\nAvoid extra confirmation screens unless data could be deleted.\nMake the document preview open inside the app."), folder: L.string("Work"), todos: []),
                    isPinned: false
                )
            ]
        )
    }

    private static var systemLocalized: DecoyNotesContent {
        let language = Locale.autoupdatingCurrent.language.languageCode?.identifier.lowercased() ?? "en"
        if language == "zh" { return .chinese }
        if language == "ja" { return .japanese }
        if language == "de" { return .german }
        if language == "fr" { return .french }
        if language == "ko" { return .korean }
        if language == "es" { return .spanish }
        return .english
    }

    private static let english = DecoyNotesContent(
        copy: DecoyNotesCopy(
            appName: "Notes",
            searchPlaceholder: "Search",
            pinnedTitle: "Pinned",
            todayTitle: "Today",
            quickNoteTitle: "Daily Notes",
            quickNotePreview: "Groceries, messages, and follow-ups",
            settingsTitle: "Notes Settings",
            localNotesLabel: "On My iPhone Notes",
            autoLockLabel: "Lock when leaving app",
            sortingLabel: "Drag notes to reorder",
            encryptedSyncLabel: "Encrypted iCloud Notes",
            maintenanceTitle: "Account",
            resetGestureButton: "Reset Gesture",
            closeButton: "Close Notes",
            newNoteTitle: "New Note",
            editNoteTitle: "Edit Note",
            titlePlaceholder: "Title",
            bodyPlaceholder: "Note",
            folderPlaceholder: "Folder",
            defaultFolder: "Notes",
            checklistTitle: "Checklist",
            checklistPlaceholder: "List item",
            addChecklistItem: "Add Checklist Item",
            deleteButton: "Delete Note",
            pinButton: "Pin",
            unpinButton: "Unpin",
            doneButton: "Done",
            cancelButton: "Cancel",
            emptyTitle: "No Notes",
            emptyDetail: "Tap compose to create a note.",
            noResultsTitle: "No Results",
            noResultsDetail: "Try a different search.",
            untitledNote: "New Note",
            emptyPreview: "No additional text"
        ),
        defaultNotes: [
            (
                id: "default-today",
                payload: DecoyNotePayload(title: "Today", body: "", folder: "Notes", todos: [
                    DecoyTodoPayload(id: "today-electricity", text: "Pay electricity bill before 6 PM", done: true),
                    DecoyTodoPayload(id: "today-mom", text: "Call Mom after lunch", done: false),
                    DecoyTodoPayload(id: "today-delivery", text: "Confirm package delivery window", done: false)
                ]),
                isPinned: true
            ),
            (
                id: "default-dinner",
                payload: DecoyNotePayload(title: "Dinner", body: "Bring fruit tonight.\nArrive around 7.\nMake noodles first.", folder: "Personal", todos: []),
                isPinned: true
            ),
            (
                id: "default-cleanup",
                payload: DecoyNotePayload(title: "Weekly cleanup", body: "", folder: "Home", todos: [
                    DecoyTodoPayload(id: "cleanup-laundry", text: "Laundry", done: true),
                    DecoyTodoPayload(id: "cleanup-receipts", text: "Sort receipts", done: false),
                    DecoyTodoPayload(id: "cleanup-desk", text: "Clean desk drawer", done: false),
                    DecoyTodoPayload(id: "cleanup-cable", text: "Find backup cable", done: false)
                ]),
                isPinned: false
            ),
            (
                id: "default-meeting",
                payload: DecoyNotePayload(title: "Meeting notes", body: "Keep the import flow simple.\nAvoid extra confirmation screens unless data could be deleted.\nMake the document preview open inside the app.", folder: "Work", todos: []),
                isPinned: false
            )
        ]
    )

    private static let chinese = DecoyNotesContent(
        copy: DecoyNotesCopy(
            appName: "备忘录",
            searchPlaceholder: "搜索",
            pinnedTitle: "置顶",
            todayTitle: "今天",
            quickNoteTitle: "今日备忘",
            quickNotePreview: "待办、消息、生活事项",
            settingsTitle: "备忘录设置",
            localNotesLabel: "我的 iPhone 备忘录",
            autoLockLabel: "离开应用后锁定",
            sortingLabel: "拖动备忘录调整顺序",
            encryptedSyncLabel: "加密 iCloud 备忘录",
            maintenanceTitle: "账户",
            resetGestureButton: "重置手势",
            closeButton: "关闭备忘录",
            newNoteTitle: "新建备忘录",
            editNoteTitle: "编辑备忘录",
            titlePlaceholder: "标题",
            bodyPlaceholder: "备忘录",
            folderPlaceholder: "文件夹",
            defaultFolder: "备忘录",
            checklistTitle: "待办清单",
            checklistPlaceholder: "待办事项",
            addChecklistItem: "添加待办事项",
            deleteButton: "删除备忘录",
            pinButton: "置顶",
            unpinButton: "取消置顶",
            doneButton: "完成",
            cancelButton: "取消",
            emptyTitle: "没有备忘录",
            emptyDetail: "点击撰写按钮新建备忘录。",
            noResultsTitle: "没有结果",
            noResultsDetail: "换个关键词试试。",
            untitledNote: "新建备忘录",
            emptyPreview: "没有更多内容"
        ),
        defaultNotes: [
            (
                id: "default-today",
                payload: DecoyNotePayload(title: "今天", body: "", folder: "备忘录", todos: [
                    DecoyTodoPayload(id: "today-electricity", text: "晚上 6 点前交电费", done: true),
                    DecoyTodoPayload(id: "today-mom", text: "午饭后给妈妈打电话", done: false),
                    DecoyTodoPayload(id: "today-delivery", text: "确认快递送达时间", done: false)
                ]),
                isPinned: true
            ),
            (
                id: "default-dinner",
                payload: DecoyNotePayload(title: "晚饭", body: "今晚带点水果。\n七点左右到。\n先煮面。", folder: "生活", todos: []),
                isPinned: true
            ),
            (
                id: "default-cleanup",
                payload: DecoyNotePayload(title: "本周整理", body: "", folder: "家里", todos: [
                    DecoyTodoPayload(id: "cleanup-laundry", text: "洗衣服", done: true),
                    DecoyTodoPayload(id: "cleanup-receipts", text: "整理票据", done: false),
                    DecoyTodoPayload(id: "cleanup-desk", text: "清理书桌抽屉", done: false),
                    DecoyTodoPayload(id: "cleanup-cable", text: "找备用数据线", done: false)
                ]),
                isPinned: false
            ),
            (
                id: "default-meeting",
                payload: DecoyNotePayload(title: "会议记录", body: "导入流程要保持简单。\n除非涉及删除数据，否则不要增加额外确认。\n文档预览要能直接在应用内打开。", folder: "工作", todos: []),
                isPinned: false
            )
        ]
    )

    private static let japanese = english.localized(appName: "メモ", search: "検索", today: "今日", quick: "今日のメモ", settings: "メモ設定", close: "メモを閉じる")
    private static let german = english.localized(appName: "Notizen", search: "Suchen", today: "Heute", quick: "Tagesnotizen", settings: "Notizen", close: "Notizen schließen")
    private static let french = english.localized(appName: "Notes", search: "Rechercher", today: "Aujourd'hui", quick: "Notes du jour", settings: "Réglages Notes", close: "Fermer Notes")
    private static let korean = english.localized(appName: "메모", search: "검색", today: "오늘", quick: "오늘 메모", settings: "메모 설정", close: "메모 닫기")
    private static let spanish = english.localized(appName: "Notas", search: "Buscar", today: "Hoy", quick: "Notas de hoy", settings: "Ajustes de Notas", close: "Cerrar Notas")

    private func localized(appName: String, search: String, today: String, quick: String, settings: String, close: String) -> DecoyNotesContent {
        DecoyNotesContent(
            copy: DecoyNotesCopy(
                appName: appName,
                searchPlaceholder: search,
                pinnedTitle: copy.pinnedTitle,
                todayTitle: today,
                quickNoteTitle: quick,
                quickNotePreview: copy.quickNotePreview,
                settingsTitle: settings,
                localNotesLabel: copy.localNotesLabel,
                autoLockLabel: copy.autoLockLabel,
                sortingLabel: copy.sortingLabel,
                encryptedSyncLabel: copy.encryptedSyncLabel,
                maintenanceTitle: copy.maintenanceTitle,
                resetGestureButton: copy.resetGestureButton,
                closeButton: close,
                newNoteTitle: copy.newNoteTitle,
                editNoteTitle: copy.editNoteTitle,
                titlePlaceholder: copy.titlePlaceholder,
                bodyPlaceholder: copy.bodyPlaceholder,
                folderPlaceholder: copy.folderPlaceholder,
                defaultFolder: appName,
                checklistTitle: copy.checklistTitle,
                checklistPlaceholder: copy.checklistPlaceholder,
                addChecklistItem: copy.addChecklistItem,
                deleteButton: copy.deleteButton,
                pinButton: copy.pinButton,
                unpinButton: copy.unpinButton,
                doneButton: copy.doneButton,
                cancelButton: copy.cancelButton,
                emptyTitle: copy.emptyTitle,
                emptyDetail: copy.emptyDetail,
                noResultsTitle: copy.noResultsTitle,
                noResultsDetail: copy.noResultsDetail,
                untitledNote: copy.untitledNote,
                emptyPreview: copy.emptyPreview
            ),
            defaultNotes: defaultNotes
        )
    }
}

private enum DecoyNotesTheme {
    static let accent = Color(red: 0.86, green: 0.58, blue: 0.02)
}
