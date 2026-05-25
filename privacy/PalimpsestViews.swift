import SwiftUI
import UIKit

struct PalimpsestCoverView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var gesturePoints: [GesturePoint] = []

    private var copy: DecoyCopy { DecoyContent.current.copy }
    private var recentFiles: ArraySlice<DecoyFile> { DecoyContent.current.files.prefix(4) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(copy.appName)
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text(copy.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "folder.fill")
                                    .font(.title)
                                    .foregroundStyle(AppTheme.accent)
                            }

                            HStack {
                                StatusPill(title: copy.localStatus, systemImage: "iphone", tint: AppTheme.accent)
                                StatusPill(title: copy.archiveStatus, systemImage: "tray.full", tint: AppTheme.success)
                            }
                        }
                    }

                    GestureEntryCard(points: $gesturePoints) { points in
                        auth.openFromDisguiseGesture(points)
                    }

                    Text(copy.recentTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    VStack(spacing: 10) {
                        ForEach(Array(recentFiles)) { file in
                            DecoyFileRow(file: file)
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(copy.filesTitle)
        }
    }
}

private struct GestureEntryCard: View {
    @Binding var points: [GesturePoint]
    let onComplete: ([GesturePoint]) -> Void
    private var copy: DecoyCopy { DecoyContent.current.copy }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                AppCard {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.draw")
                            .font(.title2)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.quickTitle)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text(copy.quickDetail)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = GesturePoint(
                            x: min(max(value.location.x / max(proxy.size.width, 1), 0), 1),
                            y: min(max(value.location.y / max(proxy.size.height, 1), 0), 1),
                            t: Date().timeIntervalSinceReferenceDate
                        )
                        points.append(normalized)
                    }
                    .onEnded { _ in
                        onComplete(points)
                        points = []
                    }
            )
        }
        .frame(height: 80)
    }
}

struct DecoyVaultView: View {
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        TabView {
            DecoyFilesHomeView()
                .tabItem { Label("Files", systemImage: "folder") }
            DecoyRecentView()
                .tabItem { Label("Recent", systemImage: "clock") }
            DecoySettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(AppTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            auth.lock()
        }
    }
}

private struct DecoyFilesHomeView: View {
    @State private var selectedFile: DecoyFile?
    private var copy: DecoyCopy { DecoyContent.current.copy }
    private var folders: [DecoyFolder] { DecoyContent.current.folders }
    private var files: [DecoyFile] { DecoyContent.current.files }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(copy.archiveTitle)
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(AppTheme.ink)
                                Text(copy.summary(files.count, folders.count))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "folder.badge.gearshape")
                                .font(.title)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(folders) { folder in
                            DecoyFolderCard(folder: folder)
                        }
                    }

                    Text(copy.fileSectionTitle)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    VStack(spacing: 10) {
                        ForEach(files) { file in
                            Button {
                                selectedFile = file
                            } label: {
                                DecoyFileRow(file: file)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(copy.appName)
            .sheet(item: $selectedFile) { file in
                DecoyFileDetailView(file: file)
            }
        }
    }
}

private struct DecoyRecentView: View {
    private var copy: DecoyCopy { DecoyContent.current.copy }
    private var files: [DecoyFile] { DecoyContent.current.files }

    var body: some View {
        NavigationStack {
            List {
                Section(copy.todaySection) {
                    ForEach(files.prefix(3)) { file in
                        DecoyListFileRow(file: file)
                    }
                }
                Section(copy.weekSection) {
                    ForEach(files.dropFirst(3)) { file in
                        DecoyListFileRow(file: file)
                    }
                }
            }
            .navigationTitle(copy.recentTitle)
        }
    }
}

private struct DecoySettingsView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    private var copy: DecoyCopy { DecoyContent.current.copy }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.archiveTitle) {
                    Label(copy.localFilesLabel, systemImage: "iphone")
                    Label(copy.offlineLabel, systemImage: "icloud.slash")
                    Label(copy.autoLockLabel, systemImage: "lock")
                }

                LanguagePickerSection()

                Section(copy.maintenanceTitle) {
                    Button(copy.reloadButton) {}
                    Button(copy.closeButton) {
                        auth.lock()
                    }
                }
            }
            .navigationTitle(copy.settingsTitle)
        }
    }
}

private struct DecoyFolderCard: View {
    let folder: DecoyFolder

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: folder.icon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                Text(folder.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(L.format("%d items", folder.count))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DecoyFileRow: View {
    let file: DecoyFile

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                DecoyFileIcon(file: file)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text("\(file.folder) · \(file.size)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct DecoyListFileRow: View {
    let file: DecoyFile

    var body: some View {
        HStack(spacing: 12) {
            DecoyFileIcon(file: file)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                Text(file.modified)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct DecoyFileIcon: View {
    let file: DecoyFile

    var body: some View {
        Image(systemName: file.icon)
            .font(.title3)
            .foregroundStyle(file.tint)
            .frame(width: 38, height: 38)
            .background(file.tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DecoyFileDetailView: View {
    let file: DecoyFile

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DecoyFileIcon(file: file)
                    .scaleEffect(1.3)
                    .padding(.top, 20)
                Text(file.name)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(file.preview)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding()
            .navigationTitle("File Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DecoyFolder: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let icon: String

}

private struct DecoyFile: Identifiable {
    let id = UUID()
    let name: String
    let folder: String
    let size: String
    let modified: String
    let icon: String
    let tint: Color
    let preview: String

}

private struct DecoyCopy {
    let appName: String
    let subtitle: String
    let localStatus: String
    let archiveStatus: String
    let accessTitle: String
    let accessPlaceholder: String
    let openButton: String
    let recentTitle: String
    let filesTitle: String
    let quickTitle: String
    let quickDetail: String
    let archiveTitle: String
    let fileSectionTitle: String
    let todaySection: String
    let weekSection: String
    let settingsTitle: String
    let localFilesLabel: String
    let offlineLabel: String
    let autoLockLabel: String
    let maintenanceTitle: String
    let reloadButton: String
    let closeButton: String
    let summary: (Int, Int) -> String
}

private struct DecoyContent {
    let copy: DecoyCopy
    let folders: [DecoyFolder]
    let files: [DecoyFile]

    static var current: DecoyContent {
        let locale = AppLanguage.current.locale
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let region = locale.region?.identifier.uppercased() ?? "US"

        if language == "zh" || ["CN", "HK", "MO", "TW", "SG"].contains(region) {
            return .localized(
                appName: L.string("File Cabinet"),
                subtitle: L.string("Offline documents and receipts"),
                folders: [L.string("Invoices"), L.string("Receipts"), L.string("Identity"), L.string("Warranties")],
                modified: [L.string("Today 09:20"), L.string("Today 08:42"), L.string("Yesterday 18:11"), L.string("Tue 14:35"), L.string("Mon 11:08"), L.string("Fri 16:27")]
            )
        }

        if language == "ja" || region == "JP" {
            return .localized(
                appName: L.string("File Cabinet"),
                subtitle: L.string("Offline documents and receipts"),
                folders: [L.string("Invoices"), L.string("Receipts"), L.string("Identity"), L.string("Warranties")],
                modified: [L.string("Today 09:20"), L.string("Today 08:42"), L.string("Yesterday 18:11"), L.string("Tue 14:35"), L.string("Mon 11:08"), L.string("Fri 16:27")]
            )
        }

        if language == "de" || ["DE", "AT", "CH"].contains(region) {
            return .german
        }

        if language == "fr" || ["FR", "BE", "LU"].contains(region) {
            return .french
        }

        if language == "ko" || region == "KR" {
            return .korean
        }

        if language == "es" || ["ES", "MX", "AR", "CL", "CO", "PE"].contains(region) {
            return .spanish
        }

        return .english
    }

    private static let english = DecoyContent(
        copy: DecoyCopy(
            appName: "File Cabinet",
            subtitle: "Offline documents and receipts",
            localStatus: "On this iPhone",
            archiveStatus: "Offline archive",
            accessTitle: "Open Archive",
            accessPlaceholder: "Archive passcode",
            openButton: "Open File Cabinet",
            recentTitle: "Recent Files",
            filesTitle: "Files",
            quickTitle: "Quick Sort",
            quickDetail: "Drag here to organize recent documents.",
            archiveTitle: "File Archive",
            fileSectionTitle: "Documents",
            todaySection: "Today",
            weekSection: "This Week",
            settingsTitle: "Settings",
            localFilesLabel: "Local archive files",
            offlineLabel: "No network sync",
            autoLockLabel: "Auto lock",
            maintenanceTitle: "Maintenance",
            reloadButton: "Refresh archive index",
            closeButton: "Close archive",
            summary: { "\($0) files · \($1) folders" }
        ),
        folders: [
            DecoyFolder(title: "Invoices", count: 5, icon: "doc.text"),
            DecoyFolder(title: "Receipts", count: 7, icon: "receipt"),
            DecoyFolder(title: "Identity", count: 3, icon: "doc.viewfinder"),
            DecoyFolder(title: "Warranties", count: 4, icon: "shippingbox")
        ],
        files: [
            DecoyFile(name: "2026-05_United_Airlines_E-Receipt.jpg", folder: "Receipts", size: "864 KB", modified: "Today 09:20", icon: "photo", tint: AppTheme.success, preview: "United Airlines itinerary receipt for May travel, total USD 286.40, tagged for business expense review."),
            DecoyFile(name: "May_2026_Internet_Service_Invoice.pdf", folder: "Invoices", size: "1.3 MB", modified: "Today 08:42", icon: "doc.text", tint: AppTheme.danger, preview: "Monthly internet service invoice with account summary, billing period, tax line, and payment confirmation."),
            DecoyFile(name: "Product_Review_Notes_2026-05-21.txt", folder: "Invoices", size: "31 KB", modified: "Yesterday 18:11", icon: "note.text", tint: AppTheme.warning, preview: "Meeting notes covering import flow, encrypted sync disclosure, paywall copy, and App Review preparation."),
            DecoyFile(name: "Passport_Copy_For_Bank_Verification.pdf", folder: "Identity", size: "948 KB", modified: "Tue 14:35", icon: "doc.viewfinder", tint: AppTheme.accent, preview: "Passport copy prepared for bank verification, with purpose note and document date visible in the footer."),
            DecoyFile(name: "MacBook_AppleCare_Coverage.png", folder: "Warranties", size: "632 KB", modified: "Mon 11:08", icon: "photo.on.rectangle", tint: AppTheme.primary, preview: "AppleCare coverage screenshot with serial number, eligible device name, and coverage expiration date."),
            DecoyFile(name: "Household_Budget_2026_Q2.xlsx", folder: "Invoices", size: "84 KB", modified: "Fri 16:27", icon: "tablecells", tint: AppTheme.success, preview: "Quarterly household budget workbook with tabs for fixed costs, subscriptions, travel, and equipment purchases.")
        ]
    )

    private static let german = DecoyContent.localized(
        appName: "Dokumentenmappe",
        subtitle: "Lokale Dokumente und Belege",
        folders: ["Rechnungen", "Belege", "Identitat", "Garantien"],
        modified: ["Heute 09:20", "Heute 08:42", "Gestern 18:11", "Di 14:35", "Mo 11:08", "Fr 16:27"]
    )

    private static let french = DecoyContent.localized(
        appName: "Classeur",
        subtitle: "Documents et recus hors ligne",
        folders: ["Factures", "Recus", "Identite", "Garanties"],
        modified: ["Aujourd'hui 09:20", "Aujourd'hui 08:42", "Hier 18:11", "Mar 14:35", "Lun 11:08", "Ven 16:27"]
    )

    private static let korean = DecoyContent.localized(
        appName: "파일 캐비닛",
        subtitle: "오프라인 문서와 영수증",
        folders: ["청구서", "영수증", "신분증", "보증서"],
        modified: ["오늘 09:20", "오늘 08:42", "어제 18:11", "화 14:35", "월 11:08", "금 16:27"]
    )

    private static let spanish = DecoyContent.localized(
        appName: "Archivador",
        subtitle: "Documentos y recibos sin conexion",
        folders: ["Facturas", "Recibos", "Identidad", "Garantias"],
        modified: ["Hoy 09:20", "Hoy 08:42", "Ayer 18:11", "Mar 14:35", "Lun 11:08", "Vie 16:27"]
    )

    private static func localized(appName: String, subtitle: String, folders: [String], modified: [String]) -> DecoyContent {
        let invoice = folders[0]
        let receipts = folders[1]
        let identity = folders[2]
        let warranties = folders[3]

        return DecoyContent(
            copy: DecoyCopy(
                appName: appName,
                subtitle: subtitle,
                localStatus: L.string("On this iPhone"),
                archiveStatus: L.string("Offline archive"),
                accessTitle: L.string("Open Archive"),
                accessPlaceholder: L.string("Archive passcode"),
                openButton: L.string("Open File Cabinet"),
                recentTitle: L.string("Recent Files"),
                filesTitle: L.string("Files"),
                quickTitle: L.string("Quick Sort"),
                quickDetail: L.string("Drag here to organize recent documents."),
                archiveTitle: L.string("File Archive"),
                fileSectionTitle: L.string("Documents"),
                todaySection: L.string("Today"),
                weekSection: L.string("This Week"),
                settingsTitle: L.string("Settings"),
                localFilesLabel: L.string("Local archive files"),
                offlineLabel: L.string("No network sync"),
                autoLockLabel: L.string("Auto lock"),
                maintenanceTitle: L.string("Maintenance"),
                reloadButton: L.string("Refresh archive index"),
                closeButton: L.string("Close archive"),
                summary: { L.format("%d files · %d folders", $0, $1) }
            ),
            folders: [
                DecoyFolder(title: invoice, count: 5, icon: "doc.text"),
                DecoyFolder(title: receipts, count: 7, icon: "receipt"),
                DecoyFolder(title: identity, count: 3, icon: "doc.viewfinder"),
                DecoyFolder(title: warranties, count: 4, icon: "shippingbox")
            ],
            files: [
                DecoyFile(name: "2026-05_United_Airlines_E-Receipt.jpg", folder: receipts, size: "864 KB", modified: modified[0], icon: "photo", tint: AppTheme.success, preview: L.string("United Airlines itinerary receipt for May travel, total USD 286.40, tagged for business expense review.")),
                DecoyFile(name: "May_2026_Internet_Service_Invoice.pdf", folder: invoice, size: "1.3 MB", modified: modified[1], icon: "doc.text", tint: AppTheme.danger, preview: L.string("Monthly internet service invoice with account summary, billing period, tax line, and payment confirmation.")),
                DecoyFile(name: "Product_Review_Notes_2026-05-21.txt", folder: invoice, size: "31 KB", modified: modified[2], icon: "note.text", tint: AppTheme.warning, preview: L.string("Meeting notes covering import flow, encrypted sync disclosure, paywall copy, and App Review preparation.")),
                DecoyFile(name: "Passport_Copy_For_Bank_Verification.pdf", folder: identity, size: "948 KB", modified: modified[3], icon: "doc.viewfinder", tint: AppTheme.accent, preview: L.string("Passport copy prepared for bank verification, with purpose note and document date visible in the footer.")),
                DecoyFile(name: "MacBook_AppleCare_Coverage.png", folder: warranties, size: "632 KB", modified: modified[4], icon: "photo.on.rectangle", tint: AppTheme.primary, preview: L.string("AppleCare coverage screenshot with serial number, eligible device name, and coverage expiration date.")),
                DecoyFile(name: "Household_Budget_2026_Q2.xlsx", folder: invoice, size: "84 KB", modified: modified[5], icon: "tablecells", tint: AppTheme.success, preview: L.string("Quarterly household budget workbook with tabs for fixed costs, subscriptions, travel, and equipment purchases."))
            ]
        )
    }
}
