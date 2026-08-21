import Foundation
import SwiftUI
import RangeSightCore

struct SessionShellView: View {
    @State private var selectedScreen: AppScreenID = .home
    @State private var targetLockSource: TargetLockSource = .assisted
    @State private var selectedShotID: Int?
    @State private var selectedCandidateID: String?
    @State private var isAddingImpact = false
    @State private var isMovingImpact = false
    @State private var audioAssistEnabled = false
    @State private var editableShots = MockRangeSessionData.sample.shots
    @State private var editableCandidates = MockRangeSessionData.sample.candidates
    @State private var analyticsResult = SessionAnalyticsEngine().analytics(for: PersistedRangeSightStore())
    @State private var analyticsStatus = "No saved sessions yet."
    @State private var selectedDateRange: HistoryDateRangeSelection = .allTime
    @State private var selectedFirearmFilter: FirearmProfileID?
    @State private var selectedTargetFilter: TargetDefinitionID?
    @State private var selectedDistanceFilter: HistoryDistanceFilterOption?
    @State private var selectedHistorySessionID: RangeSessionID?
    @State private var firearmFilterOptions: [FirearmProfile] = []
    @State private var targetFilterOptions: [TargetDefinition] = []
    @State private var distanceFilterOptions: [HistoryDistanceFilterOption] = []
    private let data = MockRangeSessionData.sample
    private let historyRepository = LocalRangeSightRepository(storeURL: RangeSightStoreLocation.defaultStoreURL)

    private var screen: AppScreen {
        AppNavigation.screen(for: selectedScreen)
    }

    private var targetLockAssessment: TargetLockAssessment {
        TargetLockPreviewData.assessment(source: targetLockSource)
    }

    private var currentStringScore: Int {
        editableShots.map(\.score).reduce(0, +)
    }

    private var latestShotScore: String {
        editableShots.last.map { "\($0.score)" } ?? "No score"
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
            metric(value: latestShotScore, label: "Latest")
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
            section("Audio Assist") {
                row(title: "Status", value: audioAssistEnabled ? "Listening for impulses" : "Visual only")
            }
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
            section("Scoring") {
                row(title: "Target", value: data.targetName)
                row(title: "Accepted shots", value: "\(editableShots.count)")
                row(title: "Total score", value: "\(currentStringScore)")
                ForEach(editableShots) { shot in
                    row(title: "Shot \(shot.id)", value: "\(shot.score)")
                }
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
                    score: scoreValue(for: coordinate),
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
            editableShots[index] = editableShots[index].moved(to: coordinate, score: scoreValue(for: coordinate))
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
                score: scoreValue(for: candidate.normalized),
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
            section("Current String") {
                row(title: "Target", value: data.targetName)
                row(title: "Accepted shots", value: "\(editableShots.count)")
                row(title: "Score", value: "\(currentStringScore)")
                row(title: "Group", value: data.groupSize)
            }
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

    private func scoreValue(for coordinate: NormalizedTargetCoordinate) -> Int {
        guard let target = SupportedTargetCatalog.scoringTarget(for: SupportedTargetCatalog.bullseyePracticeID),
              let dimensions = target.physicalDimensions,
              let score = TargetScoringEngine().score(
                TargetCoordinateConverter.physicalPoint(from: coordinate, dimensions: dimensions),
                using: target
              ) else {
            return 0
        }

        return Int(score.value)
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            historyFilterSection
            historyAnalyticsSection
            historyTrendSection
            historyListSection
            if let selectedItem = selectedHistoryItem {
                historyDetailSection(selectedItem)
            }
        }
        .task {
            await loadHistoryAnalytics()
        }
        .onChange(of: selectedDateRange) { _, _ in
            Task { await loadHistoryAnalytics() }
        }
        .onChange(of: selectedFirearmFilter) { _, _ in
            Task { await loadHistoryAnalytics() }
        }
        .onChange(of: selectedTargetFilter) { _, _ in
            Task { await loadHistoryAnalytics() }
        }
        .onChange(of: selectedDistanceFilter) { _, _ in
            Task { await loadHistoryAnalytics() }
        }
    }

    private var historyFilterSection: some View {
        section("Filters") {
            Picker("Period", selection: $selectedDateRange) {
                ForEach(HistoryDateRangeSelection.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                filterMenu(
                    title: "Firearm",
                    value: selectedFirearmFilter.flatMap(firearmName) ?? "All"
                ) {
                    Button("All") { selectedFirearmFilter = nil }
                    ForEach(firearmFilterOptions, id: \.id) { firearm in
                        Button(firearm.nickname) { selectedFirearmFilter = firearm.id }
                    }
                }

                filterMenu(
                    title: "Distance",
                    value: selectedDistanceFilter.map(distanceLabel) ?? "All"
                ) {
                    Button("All") { selectedDistanceFilter = nil }
                    ForEach(distanceFilterOptions) { option in
                        Button(distanceLabel(option)) { selectedDistanceFilter = option }
                    }
                }

                filterMenu(
                    title: "Target",
                    value: selectedTargetFilter.flatMap(targetName) ?? "All"
                ) {
                    Button("All") { selectedTargetFilter = nil }
                    ForEach(targetFilterOptions, id: \.id) { target in
                        Button(target.name) { selectedTargetFilter = target.id }
                    }
                }
            }
        }
    }

    private var historyAnalyticsSection: some View {
        section("Analytics") {
            if analyticsResult.summary.sessionCount == 0 {
                row(title: "Status", value: analyticsStatus)
            } else {
                row(title: "Sessions", value: "\(analyticsResult.summary.sessionCount)")
                row(title: "Strings", value: "\(analyticsResult.summary.stringCount)")
                row(title: "Accepted shots", value: "\(analyticsResult.summary.acceptedShotCount)")
                row(
                    title: "Avg group",
                    value: lengthLabel(
                        analyticsResult.summary.averageGroupSize,
                        unit: analyticsResult.summary.metricUnit
                    )
                )
                row(
                    title: "Best group",
                    value: lengthLabel(
                        analyticsResult.summary.bestGroup?.value,
                        unit: analyticsResult.summary.bestGroup?.unit
                    )
                )
                row(title: "Avg score", value: scoreLabel(analyticsResult.summary.averageScorePerString))
                row(title: "Best score", value: scoreLabel(analyticsResult.summary.bestScore?.value))
                row(
                    title: "Avg POI",
                    value: pointLabel(analyticsResult.summary.averagePointOfImpactOffset)
                )
                row(
                    title: "Dispersion",
                    value: dispersionLabel(
                        horizontal: analyticsResult.summary.averageHorizontalDispersion,
                        vertical: analyticsResult.summary.averageVerticalDispersion,
                        unit: analyticsResult.summary.metricUnit
                    )
                )
                if analyticsResult.summary.needsMoreDataForTrendClassification {
                    row(title: "Trend", value: "More data needed")
                }
            }
        }
    }

    private var historyTrendSection: some View {
        section("Recent Trend") {
            let recentGroups = analyticsResult.groupSizeTrend.suffix(3)
            if recentGroups.isEmpty {
                row(title: "Group size", value: "Unavailable")
            } else {
                ForEach(Array(recentGroups)) { point in
                    row(
                        title: shortDate(point.date),
                        value: lengthLabel(
                            point.groupMetrics?.extremeSpread,
                            unit: point.groupMetrics?.groupCenter.unit
                        )
                    )
                }
            }

            if analyticsResult.scoreTrend.isEmpty {
                row(title: "Score trend", value: "Unavailable")
            } else {
                row(title: "Score target", value: analyticsResult.summary.scoreTargetDefinitionID.flatMap(targetName) ?? "Selected target")
            }
        }
    }

    private var historyListSection: some View {
        section("History") {
            if analyticsResult.historyItems.isEmpty {
                row(title: "Sessions", value: analyticsStatus)
            } else {
                ForEach(analyticsResult.historyItems) { item in
                    Button {
                        selectedHistorySessionID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            row(title: shortDate(item.startedAt), value: item.firearmName ?? "No firearm")
                            row(title: "Target", value: item.targetName ?? item.targetDefinitionID.rawValue)
                            row(title: "Distance", value: distanceLabel(item.distance, unit: item.distanceUnit))
                            row(title: "Shots", value: "\(item.acceptedShotCount)")
                            row(title: "Best group", value: lengthLabel(item.bestGroupSize, unit: item.groupUnit))
                            row(title: "Score", value: scoreLabel(item.totalScore))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedHistoryItem: SessionHistoryItem? {
        guard let selectedHistorySessionID else {
            return nil
        }

        return analyticsResult.historyItems.first { $0.id == selectedHistorySessionID }
    }

    private func historyDetailSection(_ item: SessionHistoryItem) -> some View {
        section("Session Detail") {
            row(title: "Started", value: fullDate(item.startedAt))
            row(title: "Firearm", value: item.firearmName ?? "No firearm")
            row(title: "Target", value: item.targetName ?? item.targetDefinitionID.rawValue)
            row(title: "Distance", value: distanceLabel(item.distance, unit: item.distanceUnit))
            row(title: "Strings", value: "\(item.stringCount)")
            row(title: "Accepted shots", value: "\(item.acceptedShotCount)")
            row(title: "Best group", value: lengthLabel(item.bestGroupSize, unit: item.groupUnit))
            row(title: "Score", value: scoreLabel(item.totalScore))
        }
    }

    @MainActor
    private func loadHistoryAnalytics() async {
        do {
            let store = try await historyRepository.loadStore()
            updateHistoryFilterOptions(from: store)
            analyticsResult = SessionAnalyticsEngine().analytics(for: store, filter: analyticsFilter())
            analyticsStatus = store.rangeSessions.isEmpty ? "No saved sessions yet" : "No matching sessions"
        } catch {
            analyticsResult = SessionAnalyticsEngine().analytics(for: PersistedRangeSightStore(), filter: analyticsFilter())
            analyticsStatus = "Unable to load history"
        }
    }

    @MainActor
    private func updateHistoryFilterOptions(from store: PersistedRangeSightStore) {
        firearmFilterOptions = store.firearmProfiles.sorted { $0.nickname < $1.nickname }
        targetFilterOptions = store.targetDefinitions.sorted { $0.name < $1.name }
        distanceFilterOptions = Array(
            Set(
                store.rangeSessions.map {
                    HistoryDistanceFilterOption(distance: $0.distance, unit: $0.distanceUnit)
                }
            )
        )
        .sorted {
            if $0.unit == $1.unit {
                return $0.distance < $1.distance
            }

            return $0.unit.rawValue < $1.unit.rawValue
        }

        if let selectedFirearmFilter,
           !firearmFilterOptions.contains(where: { $0.id == selectedFirearmFilter }) {
            self.selectedFirearmFilter = nil
        }

        if let selectedTargetFilter,
           !targetFilterOptions.contains(where: { $0.id == selectedTargetFilter }) {
            self.selectedTargetFilter = nil
        }

        if let selectedDistanceFilter,
           !distanceFilterOptions.contains(selectedDistanceFilter) {
            self.selectedDistanceFilter = nil
        }
    }

    private func analyticsFilter() -> AnalyticsFilter {
        AnalyticsFilter(
            firearmID: selectedFirearmFilter,
            distance: selectedDistanceFilter?.distance,
            distanceUnit: selectedDistanceFilter?.unit,
            targetDefinitionID: selectedTargetFilter,
            dateRange: selectedDateRange.dateRange(referenceDate: Date())
        )
    }

    private func filterMenu<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Label(value, systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .accessibilityLabel(title)
        .buttonStyle(.bordered)
    }

    private func firearmName(for id: FirearmProfileID) -> String? {
        firearmFilterOptions.first { $0.id == id }?.nickname
    }

    private func targetName(for id: TargetDefinitionID) -> String? {
        targetFilterOptions.first { $0.id == id }?.name
    }

    private func lengthLabel(_ value: Double?, unit: LengthUnit?) -> String {
        guard let value, let unit else {
            return "Unavailable"
        }

        return "\(decimal(value)) \(unit.rawValue)"
    }

    private func scoreLabel(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }

        return decimal(value)
    }

    private func pointLabel(_ point: PhysicalPoint?) -> String {
        guard let point else {
            return "Unavailable"
        }

        return "x \(decimal(point.x)), y \(decimal(point.y)) \(point.unit.rawValue)"
    }

    private func dispersionLabel(horizontal: Double?, vertical: Double?, unit: LengthUnit?) -> String {
        guard let horizontal, let vertical, let unit else {
            return "Unavailable"
        }

        return "H \(decimal(horizontal)), V \(decimal(vertical)) \(unit.rawValue)"
    }

    private func distanceLabel(_ option: HistoryDistanceFilterOption) -> String {
        distanceLabel(option.distance, unit: option.unit)
    }

    private func distanceLabel(_ distance: Double, unit: DistanceUnit) -> String {
        "\(decimal(distance)) \(unit.rawValue)"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }

        return String(format: "%.1f", rounded)
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
                Toggle(isOn: $audioAssistEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio assist")
                        Text(audioAssistEnabled ? "Microphone requested when monitoring starts" : "Visual detection remains active")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accent)
                row(title: "Shot source", value: "Visual confirmation required")
            }
            section("Privacy") {
                row(title: "Camera frames", value: "Local")
                row(title: "Microphone audio", value: "On-device impulse metadata")
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

private enum HistoryDateRangeSelection: String, CaseIterable, Identifiable {
    case allTime
    case last30Days
    case last90Days

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .allTime:
            return "All"
        case .last30Days:
            return "30d"
        case .last90Days:
            return "90d"
        }
    }

    func dateRange(referenceDate: Date) -> AnalyticsDateRange {
        switch self {
        case .allTime:
            return .allTime
        case .last30Days:
            return .last30Days(referenceDate: referenceDate)
        case .last90Days:
            return .last90Days(referenceDate: referenceDate)
        }
    }
}

private struct HistoryDistanceFilterOption: Hashable, Identifiable {
    let distance: Double
    let unit: DistanceUnit

    var id: String {
        "\(distance)-\(unit.rawValue)"
    }
}

private enum RangeSightStoreLocation {
    static var defaultStoreURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("RangeSight", isDirectory: true)
            .appendingPathComponent("store.json")
    }
}
