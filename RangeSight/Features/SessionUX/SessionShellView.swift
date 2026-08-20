import SwiftUI
import RangeSightCore

struct SessionShellView: View {
    @State private var selectedScreen: AppScreenID = .home
    private let data = MockRangeSessionData.sample

    private var screen: AppScreen {
        AppNavigation.screen(for: selectedScreen)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                screenTabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        statusHeader
                        content
                    }
                    .padding(16)
                }
            }
            .background(Theme.background)
            .foregroundStyle(Theme.text)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RangeSight")
                    .font(.title2.bold())
                Text(data.status.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Button {
                selectedScreen = selectedScreen == .liveMonitor ? .stringReview : .liveMonitor
            } label: {
                Image(systemName: selectedScreen == .liveMonitor ? "pause.fill" : "scope")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedScreen == .liveMonitor ? .red : Theme.accent)
            .accessibilityLabel(selectedScreen == .liveMonitor ? "Pause monitoring" : "Open live monitor")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.panel)
    }

    private var screenTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppNavigation.screens) { candidate in
                    Button(candidate.title) {
                        selectedScreen = candidate.id
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .tint(candidate.id == selectedScreen ? Theme.accent : Theme.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.background)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(screen.phase.rawValue.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(data.qualityStatus)
                    .font(.caption.bold())
                    .foregroundStyle(Theme.success)
            }
            Text(screen.title)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.8)
            metricStrip
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 12) {
            metric(value: "\(data.shotCount)", label: "Shots")
            metric(value: data.latestScore, label: "Latest")
            metric(value: data.groupSize, label: "Group")
        }
        .padding(14)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedScreen {
        case .home:
            homeView
        case .sessionSetup:
            setupView
        case .cameraSetup:
            cameraSetupView
        case .liveMonitor:
            liveMonitorView
        case .stringReview:
            reviewView
        case .sessionSummary:
            summaryView
        case .history:
            historyView
        case .firearmProfiles:
            profilesView
        case .settings:
            settingsView
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            primaryAction("New Session", systemImage: "plus.circle.fill", destination: .sessionSetup)
            primaryAction("Resume Monitor", systemImage: "scope", destination: .liveMonitor)
            section("Recent") {
                ForEach(data.history) { session in
                    row(title: session.date, value: "\(session.distance) · \(session.bestGroup)")
                }
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            selectionRow("Target", data.targetName)
            selectionRow("Distance", data.distance)
            selectionRow("Firearm", data.firearm)
            primaryAction("Continue to Camera", systemImage: "camera.fill", destination: .cameraSetup)
        }
    }

    private var cameraSetupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraPreviewSurface()
            section("Framing") {
                row(title: "Preview", value: "Native AVFoundation")
                row(title: "Target lock", value: "Slice 7")
                row(title: "Detection", value: "Not running")
            }
            primaryAction("Lock Target", systemImage: "lock.fill", destination: .liveMonitor)
        }
    }

    private var liveMonitorView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TargetPreviewView(shots: data.shots, status: "Monitoring", showsCandidate: true)
            HStack(spacing: 12) {
                primaryAction("Pause", systemImage: "pause.fill", destination: .cameraSetup)
                primaryAction("End String", systemImage: "stop.fill", destination: .stringReview)
            }
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            TargetPreviewView(shots: data.shots, status: "Review", showsCandidate: false)
            section("Corrections") {
                row(title: "Candidate", value: "Confirm or ignore")
                row(title: "Manual add", value: "Available")
                row(title: "Move/delete", value: "Tap marker")
            }
            primaryAction("Save String", systemImage: "checkmark.circle.fill", destination: .sessionSummary)
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(data.summaries) { summary in
                section(summary.title) {
                    row(title: "Shots", value: "\(summary.shots)")
                    row(title: "Score", value: "\(summary.score)")
                    row(title: "Group", value: summary.groupSize)
                }
            }
            primaryAction("New String", systemImage: "scope", destination: .cameraSetup)
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(data.history) { session in
                section(session.date) {
                    row(title: "Firearm", value: session.firearm)
                    row(title: "Target", value: session.target)
                    row(title: "Distance", value: session.distance)
                    row(title: "Best group", value: session.bestGroup)
                }
            }
        }
    }

    private var profilesView: some View {
        section(data.firearm) {
            row(title: "Category", value: "Handgun")
            row(title: "Caliber", value: "9mm")
            row(title: "Default distance", value: data.distance)
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Audio") {
                row(title: "Announcements", value: "Off")
                row(title: "Audio assist", value: "Available later")
            }
            section("Privacy") {
                row(title: "Camera frames", value: "Local")
                row(title: "Debug imagery", value: "Off")
            }
        }
    }

    private func primaryAction(_ title: String, systemImage: String, destination: AppScreenID) -> some View {
        Button {
            selectedScreen = destination
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    private func selectionRow(_ title: String, _ value: String) -> some View {
        row(title: title, value: value)
            .padding(14)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(Theme.accent)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }
}

private enum Theme {
    static let background = Color(.sRGB, red: 0.06, green: 0.07, blue: 0.08, opacity: 1)
    static let panel = Color(.sRGB, red: 0.10, green: 0.12, blue: 0.14, opacity: 1)
    static let text = Color(.sRGB, red: 0.94, green: 0.96, blue: 0.97, opacity: 1)
    static let muted = Color(.sRGB, red: 0.58, green: 0.63, blue: 0.68, opacity: 1)
    static let accent = Color(.sRGB, red: 0.96, green: 0.77, blue: 0.26, opacity: 1)
    static let success = Color(.sRGB, red: 0.48, green: 0.86, blue: 0.58, opacity: 1)
}
