import Foundation
import SwiftData
import SwiftUI
import UIKit

struct AlbumFloatingActionIcon: View {
    let systemImage: String
    let isActive: Bool
    let activeColor: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(isActive ? activeColor.opacity(0.88) : Color.black.opacity(0.52))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.68), lineWidth: 1.1))
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.42), radius: 10, y: 5)
    }
}

struct MediaCalendarRecord: Equatable, Sendable {
    let id: String
    let date: Date
}

enum MediaCalendarDatePolicy {
    nonisolated static func displayDate(
        capturedAt: Date?,
        locationCapturedAt: Date?,
        importedAt: Date?,
        itemCreatedAt: Date
    ) -> Date {
        capturedAt ?? locationCapturedAt ?? importedAt ?? itemCreatedAt
    }
}

enum MediaCalendarPolicy {
    nonisolated static func representativeID(records: [MediaCalendarRecord]) -> String? {
        records.max { lhs, rhs in lhs.date < rhs.date }?.id
    }

    nonisolated static func groupedIDs(
        records: [MediaCalendarRecord],
        calendar: Calendar
    ) -> [Date: [String]] {
        Dictionary(grouping: records, by: { calendar.startOfDay(for: $0.date) })
            .mapValues { $0.map(\.id) }
    }

    nonisolated static func monthCells(containing date: Date, calendar: Calendar) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leadingCount)
        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        }.map(Optional.some))
        let trailingCount = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailingCount))
        return cells
    }
}

struct VaultMediaCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let items: [VaultItem]
    let displayDates: [String: Date]
    let isInnerVaultActive: Bool
    @State private var displayedMonth = Date()
    @State private var positionedAtLatestMonth = false
    private var calendar: Calendar {
        var value = Calendar.current
        value.locale = locale
        return value
    }

    private var groupedItems: [Date: [VaultItem]] {
        Dictionary(grouping: items) { item in
            calendar.startOfDay(for: displayDates[item.id] ?? item.createdAt)
        }
    }

    private var latestDate: Date? {
        items.compactMap { displayDates[$0.id] }.max()
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    monthHeader

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(Array(MediaCalendarPolicy.monthCells(containing: displayedMonth, calendar: calendar).enumerated()), id: \.offset) { _, date in
                            if let date {
                                dayCell(date)
                            } else {
                                Color.clear.frame(height: 58)
                            }
                        }
                    }

                    if items.isEmpty {
                        ContentUnavailableView(
                            L.string("No media for this calendar"),
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(L.string("Photos and videos will appear on their capture dates."))
                        )
                        .padding(.top, 48)
                    }
                }
                .padding(16)
            }
            .background(AppGlassBackground().ignoresSafeArea())
            .navigationTitle(L.string("Photo Calendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.string("Close")) { dismiss() }
                }
            }
            .onAppear {
                guard !positionedAtLatestMonth else { return }
                positionedAtLatestMonth = true
                if let latestDate { displayedMonth = latestDate }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel(L.string("Previous Month"))

            Spacer()

            Text(displayedMonth.formatted(.dateTime.locale(locale).year().month(.wide)))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            Spacer()

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel(L.string("Next Month"))
        }
        .foregroundStyle(AppTheme.ink)
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let dayItems = groupedItems[day] ?? []
        let records = dayItems.map {
            MediaCalendarRecord(id: $0.id, date: displayDates[$0.id] ?? $0.createdAt)
        }
        let backgroundID = MediaCalendarPolicy.representativeID(records: records)
        let backgroundItem = dayItems.first { $0.id == backgroundID }
        let content = MediaCalendarDayCell(
            date: date,
            itemCount: dayItems.count,
            isToday: calendar.isDateInToday(date),
            backgroundItem: backgroundItem
        )

        if dayItems.isEmpty {
            content
        } else {
            NavigationLink {
                MediaCalendarDayView(
                    date: date,
                    items: dayItems,
                    isInnerVaultActive: isInnerVaultActive
                )
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    private func moveMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.snappy(duration: 0.2)) { displayedMonth = newMonth }
    }
}

private struct MediaCalendarDayCell: View {
    @Environment(\.locale) private var locale
    let date: Date
    let itemCount: Int
    let isToday: Bool
    let backgroundItem: VaultItem?

    var body: some View {
        ZStack {
            if let backgroundItem {
                MediaCalendarDayBackground(item: backgroundItem)
                LinearGradient(
                    colors: [.black.opacity(0.08), .black.opacity(0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.locale(locale).day()))
                    .font(.subheadline.weight(itemCount > 0 ? .bold : .regular))
                    .foregroundStyle(itemCount > 0 ? .white : AppTheme.secondaryText)
                    .shadow(color: .black.opacity(itemCount > 0 ? 0.75 : 0), radius: 2, y: 1)

                if itemCount > 0 {
                    Text(itemCount.formatted(.number.locale(locale)))
                        .font(.caption2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(minHeight: 18)
                        .background(.black.opacity(0.58), in: Capsule())
                } else {
                    Color.clear.frame(height: 18)
                }
            }
            .padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(itemCount > 0 ? Color.black.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isToday ? AppTheme.primary : .white.opacity(itemCount > 0 ? 0.28 : 0), lineWidth: isToday ? 2 : 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale)))
        .accessibilityValue(L.format("Items: %d", itemCount))
    }
}

private struct MediaCalendarDayBackground: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(AppTheme.card)
            }
        }
        .clipped()
        .task(id: "calendar-day:\(item.id):\(item.encryptedThumbPath ?? "")") {
            if let cached = vaultStore.cachedThumbnail(for: item) {
                image = cached
            } else {
                image = await vaultStore.loadThumbnail(for: item)
            }
        }
    }
}

private struct MediaCalendarDayView: View {
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @Environment(\.locale) private var locale
    let date: Date
    let items: [VaultItem]
    let isInnerVaultActive: Bool
    @State private var previewSelection: MediaPreviewSelection?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { item in
                    MediaCalendarThumbnail(item: item)
                        .onTapGesture {
                            previewSelection = MediaPreviewSelection(item: item, items: items)
                        }
                }
            }
            .padding(3)
        }
        .background(AppTheme.background)
        .navigationTitle(date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale)))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $previewSelection) { selection in
            VaultMediaPreviewView(
                items: selection.items,
                initialItemID: selection.initialItemID,
                isInnerVaultActive: isInnerVaultActive
            )
            .environmentObject(subscription)
            .environmentObject(sync)
            .environmentObject(vaultStore)
        }
    }
}

private struct MediaCalendarThumbnail: View {
    @EnvironmentObject private var vaultStore: VaultStore
    let item: VaultItem
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(AppTheme.card)
                        .overlay {
                            Image(systemName: item.kind.previewBadgeSystemImage ?? "photo")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            if item.kind == .livePhoto {
                Image(systemName: "livephoto")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(5)
                .accessibilityLabel(L.string("Live Photo"))
            } else if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.58), in: Circle())
                    .padding(5)
            }
        }
        .contentShape(Rectangle())
        .task(id: "\(item.id):\(item.encryptedThumbPath ?? "")") {
            if let cached = vaultStore.cachedThumbnail(for: item) {
                image = cached
            } else {
                image = await vaultStore.loadThumbnail(for: item)
            }
        }
    }
}
