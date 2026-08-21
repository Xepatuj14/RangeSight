import SwiftUI
import RangeSightCore

struct SessionShellView: View {
    @State private var selectedScreen: AppScreenID = .home
    @State private var targetLockSource: TargetLockSource = .assisted
    @State private var selectedShotID: Int?
    @State private var selectedCandidateID: String?
    @State private var isAddingImpact = false
    @State private var isMovingImpact = false
    @State private var editableShots = MockRangeSessionData.sample.shots
    @State private var editableCandidates = MockRangeSessionData.sample.candidates
    private let data = MockRangeSessionData.sample

    private var screen: AppScreen {
        AppNavigation.screen(for: selectedScreen)
    }

    private var targetLockAssessment: TargetLockAssessment {
        TargetLockPreviewData.assessment(source: targetLockSource)
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
            metric(value: "\(editableShots.count)", label: "Shots")
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
            TargetLockPanel(
                source: targetLockSource,
                assessment: targetLockAssessment,
                onSourceSelected: { targetLockSource = $0 }
            )
            section("Framing") {
                row(title: "Preview", value: "Native AVFoundation")
                row(title: "Target lock", value: targetLockAssessment.canLock ? "Ready" : "Quality blocked")
                row(title: "Normalization", value: "Perspective metadata")
                row(title: "Detection", value: "Not running")
            }
            Button {
                selectedScreen = .liveMonitor
            } label: {
                Label("Lock Target", systemImage: "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!targetLockAssessment.canLock)
        }
    }

    private var liveMonitorView: some View {
        VStack(alignment: .leading, spacing: 14) {
            correctionTargetPreview(status: correctionStatus(defaultStatus: "Monitoring"))
            correctionControls
            HStack(spacing: 12) {
                primaryAction("Pause", systemImage: "pause.fill", destination: .cameraSetup)
                primaryAction("End String", systemImage: "stop.fill", destination: .stringReview)
            }
        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            correctionTargetPreview(status: correctionStatus(defaultStatus: "Review"))
            section("Corrections") {
                correctionControls
            }
            primaryAction("Save String", systemImage: "checkmark.circle.fill", destination: .sessionSummary)
        }
    }

    private func correctionTargetPreview(status: String) -> some View {
        TargetPreviewView(
            shots: editableShots,
            candidates: editableCandidates,
            status: status,
            selectedShotID: selectedShotID,
            selectedCandidateID: selectedCandidateID,
            onShotSelected: { shotID in
                selectedShotID = shotID
                selectedCandidateID = nil
                isAddingImpact = false
                isMovingImpact = false
            },
            onCandidateSelected: { candidateID in
                selectedCandidateID = candidateID
                selectedShotID = nil
                isAddingImpact = false
                isMovingImpact = false
            },
            onTargetTapped: { coordinate in
                handleTargetTap(coordinate)
            }
        )
    }

    private var correctionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    isAddingImpact.toggle()
                    isMovingImpact = false
                    selectedShotID = nil
                    selectedCandidateID = nil
                } label: {
                    Label(isAddingImpact ? "Cancel Add" : "Add Impact", systemImage: isAddingImpact ? "xmark.circle" : "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(isAddingImpact ? Theme.warning : Theme.accent)

                Button {
                    confirmSelectedCandidate()
                } label: {
                    Label("Confirm", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selectedCandidateID == nil)
            }

            HStack(spacing: 10) {
                Button {
                    isMovingImpact.toggle()
                    isAddingImpact = false
                } label: {
                    Label(isMovingImpact ? "Cancel Move" : "Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selectedShotID == nil)

                Button {
                    deleteSelectedShot()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.warning)
                .disabled(selectedShotID == nil)

                Button {
                    selectedShotID = nil
                    selectedCandidateID = nil
                    isAddingImpact = false
                    isMovingImpact = false
                } label: {
                    Label("Clear", systemImage: "circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func correctionStatus(defaultStatus: String) -> String {
        if isAddingImpact {
            return "Tap target to add"
        }

        if isMovingImpact {
            return "Tap target to move"
        }

        return defaultStatus
    }

    private func handleTargetTap(_ coordinate: NormalizedTargetCoordinate) {
        if isAddingImpact {
            let nextID = (editableShots.map(\.id).max() ?? 0) + 1
            editableShots.append(
                MockShotMarker(
                    id: nextID,
                    normalized: coordinate,
                    score: 0,
                    confidence: 0,
                    source: .manualAdded
                )
            )
            selectedShotID = nextID
            isAddingImpact = false
            return
        }

        if isMovingImpact,
           let selectedShotID,
           let index = editableShots.firstIndex(where: { $0.id == selectedShotID }) {
            editableShots[index] = editableShots[index].moved(to: coordinate)
            isMovingImpact = false
        }
    }

    private func confirmSelectedCandidate() {
        guard let selectedCandidateID,
              let index = editableCandidates.firstIndex(where: { $0.id == selectedCandidateID }) else {
            return
        }

        let candidate = editableCandidates.remove(at: index)
        let nextID = (editableShots.map(\.id).max() ?? 0) + 1
        editableShots.append(
            MockShotMarker(
                id: nextID,
                normalized: candidate.normalized,
                score: 0,
                confidence: candidate.confidence,
                source: .userConfirmed
            )
        )
        self.selectedCandidateID = nil
        selectedShotID = nextID
        isMovingImpact = false
    }

    private func deleteSelectedShot() {
        guard let selectedShotID else {
            return
        }

        editableShots.removeAll { $0.id == selectedShotID }
        self.selectedShotID = nil
        isMovingImpact = false
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

enum Theme {
    static let background = Color(.sRGB, red: 0.06, green: 0.07, blue: 0.08, opacity: 1)
    static let panel = Color(.sRGB, red: 0.10, green: 0.12, blue: 0.14, opacity: 1)
    static let text = Color(.sRGB, red: 0.94, green: 0.96, blue: 0.97, opacity: 1)
    static let muted = Color(.sRGB, red: 0.58, green: 0.63, blue: 0.68, opacity: 1)
    static let accent = Color(.sRGB, red: 0.96, green: 0.77, blue: 0.26, opacity: 1)
    static let success = Color(.sRGB, red: 0.48, green: 0.86, blue: 0.58, opacity: 1)
    static let warning = Color(.sRGB, red: 1.0, green: 0.42, blue: 0.36, opacity: 1)
    static let control = Color(.sRGB, red: 0.24, green: 0.29, blue: 0.32, opacity: 1)
}
