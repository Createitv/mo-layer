import SwiftUI
import UIKit

struct PalimpsestCoverView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var archiveCode = ""
    @State private var gesturePoints: [GesturePoint] = []

    private let recentFiles = DecoyFile.samples.prefix(4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Palimpsest")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text("Personal file archive")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "folder.fill")
                                    .font(.title)
                                    .foregroundStyle(AppTheme.accent)
                            }

                            HStack {
                                StatusPill(title: "本机文件", systemImage: "iphone", tint: AppTheme.accent)
                                StatusPill(title: "离线归档", systemImage: "tray.full", tint: AppTheme.success)
                            }
                        }
                    }

                    GestureEntryCard(points: $gesturePoints) { points in
                        auth.openFromDisguiseGesture(points)
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("访问归档")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            SecureField("输入归档访问码", text: $archiveCode)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    archiveCode = ""
                                    auth.openDecoyVault()
                                }
                            Button {
                                archiveCode = ""
                                auth.openDecoyVault()
                            } label: {
                                Label("打开文件归档", systemImage: "folder")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    Text("最近文件")
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
            .navigationTitle("文件")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        auth.openDecoyVault()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

private struct GestureEntryCard: View {
    @Binding var points: [GesturePoint]
    let onComplete: ([GesturePoint]) -> Void

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
                            Text("快速整理")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text("在这里拖动，可快速整理最近文件。")
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
                .tabItem { Label("文件", systemImage: "folder") }
            DecoyRecentView()
                .tabItem { Label("最近", systemImage: "clock") }
            DecoySettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(AppTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            auth.lock()
        }
    }
}

private struct DecoyFilesHomeView: View {
    @State private var selectedFile: DecoyFile?
    private let folders = DecoyFolder.samples

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("文件归档")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("\(DecoyFile.samples.count) 个文件 · \(folders.count) 个文件夹")
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

                    Text("示例文件")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)

                    VStack(spacing: 10) {
                        ForEach(DecoyFile.samples) { file in
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
            .navigationTitle("Palimpsest")
            .sheet(item: $selectedFile) { file in
                DecoyFileDetailView(file: file)
            }
        }
    }
}

private struct DecoyRecentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("今天") {
                    ForEach(DecoyFile.samples.prefix(3)) { file in
                        DecoyListFileRow(file: file)
                    }
                }
                Section("本周") {
                    ForEach(DecoyFile.samples.dropFirst(3)) { file in
                        DecoyListFileRow(file: file)
                    }
                }
            }
            .navigationTitle("最近")
        }
    }
}

private struct DecoySettingsView: View {
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        NavigationStack {
            Form {
                Section("归档") {
                    Label("本机示例文件", systemImage: "iphone")
                    Label("不使用网络同步", systemImage: "icloud.slash")
                    Label("自动锁定", systemImage: "lock")
                }

                Section("维护") {
                    Button("重新载入示例文件") {}
                    Button("关闭归档") {
                        auth.lock()
                    }
                }
            }
            .navigationTitle("设置")
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
                Text("\(folder.count) 项")
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
            .navigationTitle("文件详情")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DecoyFolder: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let icon: String

    static let samples = [
        DecoyFolder(title: "Invoices", count: 3, icon: "doc.text"),
        DecoyFolder(title: "Receipts", count: 4, icon: "receipt"),
        DecoyFolder(title: "Scans", count: 5, icon: "doc.viewfinder"),
        DecoyFolder(title: "Archive", count: 8, icon: "archivebox")
    ]
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

    static let samples = [
        DecoyFile(name: "Sample Contract.pdf", folder: "Archive", size: "1.2 MB", modified: "今天 09:20", icon: "doc.richtext", tint: AppTheme.danger, preview: "这是一个示例合同文件，用于展示本机文件归档。"),
        DecoyFile(name: "Travel Receipt.jpg", folder: "Receipts", size: "820 KB", modified: "今天 08:42", icon: "photo", tint: AppTheme.success, preview: "旅行票据图片示例，可用于普通文件整理演示。"),
        DecoyFile(name: "Meeting Notes.txt", folder: "Notes", size: "24 KB", modified: "昨天 18:11", icon: "note.text", tint: AppTheme.warning, preview: "会议记录示例：待整理事项、附件、归档标签。"),
        DecoyFile(name: "ID Scan Demo.pdf", folder: "Scans", size: "940 KB", modified: "周二 14:35", icon: "doc.viewfinder", tint: AppTheme.accent, preview: "扫描件示例文件，不包含真实个人信息。"),
        DecoyFile(name: "Warranty Card.png", folder: "Archive", size: "610 KB", modified: "周一 11:08", icon: "photo.on.rectangle", tint: AppTheme.primary, preview: "保修卡示例图片，用于展示归档分类。"),
        DecoyFile(name: "Budget Draft.xlsx", folder: "Invoices", size: "76 KB", modified: "上周五 16:27", icon: "tablecells", tint: AppTheme.success, preview: "预算草稿示例文件，可用于普通办公归档。")
    ]
}
