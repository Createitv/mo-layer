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
                    NotesSearchBar(text: content.copy.searchPlaceholder)

                    NotesGestureEntrySurface(points: $gesturePoints) { points in
                        auth.openFromDisguiseGesture(points)
                    } label: {
                        NotesQuickNoteRow(copy: content.copy)
                    }

                    NotesSectionHeader(title: content.copy.pinnedTitle)

                    VStack(spacing: 0) {
                        let previewNotes = Array(content.notes.prefix(4))
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
    @EnvironmentObject private var auth: AuthenticationManager
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @State private var notes = DecoyNotesContent.current.notes
    @State private var selectedNote: DecoyNote?
    @State private var showSettings = false
    @State private var showResetGesture = false

    private var content: DecoyNotesContent { .current }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NotesSearchBar(text: content.copy.searchPlaceholder)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section(content.copy.todayTitle) {
                    ForEach(notes) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            DecoyNoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { source, destination in
                        notes.move(fromOffsets: source, toOffset: destination)
                    }
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
                    Button {} label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .tint(DecoyNotesTheme.accent)
            .sheet(item: $selectedNote) { note in
                DecoyNoteDetailView(note: note)
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
            .onChange(of: language) { _, _ in
                notes = DecoyNotesContent.current.notes
            }
        }
    }
}

private struct NotesSearchBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text(text)
            Spacer()
            Image(systemName: "mic.fill")
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
    let note: DecoyNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.kind.icon)
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

private struct DecoyNoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let note: DecoyNote

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(note.title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(note.modified)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    switch note.kind {
                    case .todo:
                        VStack(spacing: 10) {
                            ForEach(note.todos) { todo in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(todo.done ? DecoyNotesTheme.accent : .secondary)
                                    Text(todo.text)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .font(.body)
                            }
                        }
                    case .conversation:
                        VStack(spacing: 10) {
                            ForEach(note.messages) { message in
                                HStack {
                                    if message.isMine { Spacer(minLength: 42) }
                                    Text(message.text)
                                        .font(.body)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 9)
                                        .foregroundStyle(message.isMine ? .white : .primary)
                                        .background(message.isMine ? DecoyNotesTheme.accent : Color(uiColor: .secondarySystemGroupedBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    if !message.isMine { Spacer(minLength: 42) }
                                }
                            }
                        }
                    case .plain:
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(note.bodyLines, id: \.self) { line in
                                Text(line)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(note.folder)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L.string("Done"))
                    }
                    .foregroundStyle(DecoyNotesTheme.accent)
                }
            }
        }
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
                    Button(L.string("Done")) { dismiss() }
                }
            }
        }
    }
}

private enum DecoyNoteKind {
    case todo
    case conversation
    case plain

    var icon: String {
        switch self {
        case .todo: "checklist"
        case .conversation: "bubble.left.and.bubble.right"
        case .plain: "note.text"
        }
    }
}

private struct DecoyTodo: Identifiable {
    let id = UUID()
    let text: String
    let done: Bool
}

private struct DecoyMessage: Identifiable {
    let id = UUID()
    let text: String
    let isMine: Bool
}

private struct DecoyNote: Identifiable {
    let id = UUID()
    let title: String
    let preview: String
    let modified: String
    let folder: String
    let kind: DecoyNoteKind
    let isPinned: Bool
    let todos: [DecoyTodo]
    let messages: [DecoyMessage]
    let bodyLines: [String]
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
    let maintenanceTitle: String
    let resetGestureButton: String
    let closeButton: String
}

private struct DecoyNotesContent {
    let copy: DecoyNotesCopy
    let notes: [DecoyNote]

    static var current: DecoyNotesContent {
        switch AppLanguage.current {
        case .simplifiedChinese:
            .chinese
        case .japanese:
            .japanese
        case .german:
            .german
        case .french:
            .french
        case .korean:
            .korean
        case .spanish:
            .spanish
        case .system:
            systemLocalized
        case .english:
            .english
        }
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
            maintenanceTitle: "Account",
            resetGestureButton: "Reset Gesture",
            closeButton: "Close Notes"
        ),
        notes: [
            DecoyNote(title: "Today", preview: "Pay electricity bill, call Mom, confirm delivery window", modified: "9:42 AM", folder: "Notes", kind: .todo, isPinned: true, todos: [
                DecoyTodo(text: "Pay electricity bill before 6 PM", done: true),
                DecoyTodo(text: "Call Mom after lunch", done: false),
                DecoyTodo(text: "Confirm package delivery window", done: false)
            ], messages: [], bodyLines: []),
            DecoyNote(title: "Dinner chat", preview: "Alex: can you bring fruit? Me: yes, around 7.", modified: "Yesterday", folder: "Personal", kind: .conversation, isPinned: true, todos: [], messages: [
                DecoyMessage(text: "Can you bring fruit tonight?", isMine: false),
                DecoyMessage(text: "Yes. I should arrive around 7.", isMine: true),
                DecoyMessage(text: "Great, I will make noodles first.", isMine: false)
            ], bodyLines: []),
            DecoyNote(title: "Weekly cleanup", preview: "Laundry, receipts, desk drawer, backup cable.", modified: "Mon", folder: "Home", kind: .todo, isPinned: false, todos: [
                DecoyTodo(text: "Laundry", done: true),
                DecoyTodo(text: "Sort receipts", done: false),
                DecoyTodo(text: "Clean desk drawer", done: false),
                DecoyTodo(text: "Find backup cable", done: false)
            ], messages: [], bodyLines: []),
            DecoyNote(title: "Meeting notes", preview: "Keep the import flow simple and avoid extra steps.", modified: "May 27", folder: "Work", kind: .plain, isPinned: false, todos: [], messages: [], bodyLines: [
                "Keep the import flow simple.",
                "Avoid extra confirmation screens unless data could be deleted.",
                "Make the document preview open inside the app."
            ])
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
            maintenanceTitle: "账户",
            resetGestureButton: "重置手势",
            closeButton: "关闭备忘录"
        ),
        notes: [
            DecoyNote(title: "今天", preview: "交电费、给妈妈打电话、确认快递时间", modified: "09:42", folder: "备忘录", kind: .todo, isPinned: true, todos: [
                DecoyTodo(text: "晚上 6 点前交电费", done: true),
                DecoyTodo(text: "午饭后给妈妈打电话", done: false),
                DecoyTodo(text: "确认快递送达时间", done: false)
            ], messages: [], bodyLines: []),
            DecoyNote(title: "晚饭聊天", preview: "阿远：带点水果？我：可以，七点左右到。", modified: "昨天", folder: "生活", kind: .conversation, isPinned: true, todos: [], messages: [
                DecoyMessage(text: "今晚可以带点水果吗？", isMine: false),
                DecoyMessage(text: "可以，我大概七点到。", isMine: true),
                DecoyMessage(text: "好，那我先煮面。", isMine: false)
            ], bodyLines: []),
            DecoyNote(title: "本周整理", preview: "洗衣服、收票据、整理抽屉、找备用线。", modified: "周一", folder: "家里", kind: .todo, isPinned: false, todos: [
                DecoyTodo(text: "洗衣服", done: true),
                DecoyTodo(text: "整理票据", done: false),
                DecoyTodo(text: "清理书桌抽屉", done: false),
                DecoyTodo(text: "找备用数据线", done: false)
            ], messages: [], bodyLines: []),
            DecoyNote(title: "会议记录", preview: "导入流程保持简单，不增加多余步骤。", modified: "5月27日", folder: "工作", kind: .plain, isPinned: false, todos: [], messages: [], bodyLines: [
                "导入流程要保持简单。",
                "除非涉及删除数据，否则不要增加额外确认。",
                "文档预览要能直接在应用内打开。"
            ])
        ]
    )

    private static let japanese = english.with(
        appName: "メモ",
        search: "検索",
        today: "今日",
        quick: "今日のメモ",
        settings: "メモ設定",
        close: "メモを閉じる"
    )

    private static let german = english.with(
        appName: "Notizen",
        search: "Suchen",
        today: "Heute",
        quick: "Tagesnotizen",
        settings: "Notizen",
        close: "Notizen schließen"
    )

    private static let french = english.with(
        appName: "Notes",
        search: "Rechercher",
        today: "Aujourd'hui",
        quick: "Notes du jour",
        settings: "Réglages Notes",
        close: "Fermer Notes"
    )

    private static let korean = english.with(
        appName: "메모",
        search: "검색",
        today: "오늘",
        quick: "오늘 메모",
        settings: "메모 설정",
        close: "메모 닫기"
    )

    private static let spanish = english.with(
        appName: "Notas",
        search: "Buscar",
        today: "Hoy",
        quick: "Notas de hoy",
        settings: "Ajustes de Notas",
        close: "Cerrar Notas"
    )

    private func with(appName: String, search: String, today: String, quick: String, settings: String, close: String) -> DecoyNotesContent {
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
                maintenanceTitle: copy.maintenanceTitle,
                resetGestureButton: copy.resetGestureButton,
                closeButton: close
            ),
            notes: notes
        )
    }
}

private enum DecoyNotesTheme {
    static let accent = Color(red: 0.86, green: 0.58, blue: 0.02)
}
