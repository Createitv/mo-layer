import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PrivacyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
    }
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.86))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "privacy://quick-recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RecordingIconView(size: 34)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusText(for: context.state.phase))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.74))
                        Text(format(context.state.elapsedTime))
                            .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingWaveBars(level: context.state.level, barCount: 9, compact: false)
                        .frame(width: 70, height: 34)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        RecordingDot(phase: context.state.phase)
                        Text(bottomText(for: context.state.phase))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Text("Tap to return")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                RecordingIconView(size: 20)
            } compactTrailing: {
                HStack(spacing: 4) {
                    RecordingDot(phase: context.state.phase)
                    Text(formatCompact(context.state.elapsedTime))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(.white)
            } minimal: {
                RecordingDot(phase: context.state.phase)
            }
            .widgetURL(URL(string: "privacy://quick-recording"))
            .keylineTint(.red)
        }
    }

    private func statusText(for phase: RecordingActivityPhase) -> String {
        switch phase {
        case .recording: "Recording"
        case .saving: "Saving"
        case .saved: "Saved"
        case .failed: "Stopped"
        }
    }

    private func bottomText(for phase: RecordingActivityPhase) -> String {
        switch phase {
        case .recording: "Audio is being captured"
        case .saving: "Encrypting recording"
        case .saved: "Saved to vault"
        case .failed: "Recording ended"
        }
    }

    private func format(_ elapsedTime: TimeInterval) -> String {
        let total = max(Int(elapsedTime.rounded(.down)), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func formatCompact(_ elapsedTime: TimeInterval) -> String {
        let total = max(Int(elapsedTime.rounded(.down)), 0)
        if total < 600 {
            return "\(total / 60):\(String(format: "%02d", total % 60))"
        }
        return "\(total / 60)m"
    }
}

private struct RecordingLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            RecordingIconView(size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RecordingDot(phase: context.state.phase)
                    Text(label)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Text(format(context.state.elapsedTime))
                    .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
            RecordingWaveBars(level: context.state.level, barCount: 9, compact: false)
                .frame(width: 86, height: 44)
        }
        .padding(.vertical, 8)
        .widgetURL(URL(string: "privacy://quick-recording"))
    }

    private var label: String {
        switch context.state.phase {
        case .recording: "Recording"
        case .saving: "Saving"
        case .saved: "Saved"
        case .failed: "Stopped"
        }
    }

    private func format(_ elapsedTime: TimeInterval) -> String {
        let total = max(Int(elapsedTime.rounded(.down)), 0)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct RecordingIconView: View {
    let size: CGFloat

    var body: some View {
        Image("RecordingIslandIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct RecordingDot: View {
    let phase: RecordingActivityPhase

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(phase == .recording ? 1 : 0.72)
    }

    private var color: Color {
        switch phase {
        case .recording: .red
        case .saving: .orange
        case .saved: .green
        case .failed: .gray
        }
    }
}

private struct RecordingWaveBars: View {
    let level: Double
    let barCount: Int
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 2 : 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let center = Double(barCount - 1) / 2
                let distance = abs(Double(index) - center) / max(center, 1)
                let base = compact ? 5.0 : 8.0
                let peak = compact ? 18.0 : 32.0
                let height = base + (1 - distance) * 8 + max(level, 0.05) * (peak - distance * 12)
                Capsule()
                    .fill(.red.gradient)
                    .frame(width: compact ? 3 : 4, height: height)
            }
        }
    }
}
