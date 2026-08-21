import Foundation
import SwiftUI
import RangeSightCore

struct SessionShellView: View {
    @State private var workflow = RangeSightWorkflow()
    @State private var targetLockSource: TargetLockSource = .assisted
    @State private var selectedShotID: Int?
    @State private var selectedCandidateID: String?
    @State private var isAddingImpact = false
    @State private var isMovingImpact = false
    @State private var editableShots: [MockShotMarker] = []
    @State private var editableCandidates: [MockImpactCandidateMarker] = []
    @State private var deletedShots: [MockShotMarker] = []
    @State private var saveFlowState: ReleaseSaveFlowState = .review
    @State private var saveErrorMessage: String?
    @State private var saveGeneration = 0
    @State private var activeStringStartedAt = Date()
    @State private var lastSavedResult: SessionSaveResult?
    @State private var firearmProfiles: [FirearmProfile] = []
    @State private var newFirearmNickname = ""
    @State private var customDistanceText = "10"
    @State private var customDistanceActive = false
    @State private var setupValidationMessage: String?
    @State private var showLiveExitConfirmation = false
    @State private var showReviewDiscardConfirmation = false
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

    private let historyRepository = LocalRangeSightRepository(storeURL: RangeSightStoreLocation.defaultStoreURL)
    private let saveCoordinator = ProductionSessionSaveCoordinator()

    private var draft: SessionDraft? {
        workflow.draft
    }

    private var targetLockAssessment: TargetLockAssessment {
        TargetLockPreviewData.assessment(source: targetLockSource)
    }

    private var currentStringScore: Int {
        editableShots.map(\.score).reduce(0, +)
    }

    private var saveInProgress: Bool {
        saveFlowState == .saving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                }
                .padding(16)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.text)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if workflow.route != .home {
                        Button(backTitle) {
                            handleBack()
                        }
                        .accessibilityLabel(backAccessibilityLabel)
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .alert("End active string?", isPresented: $showLiveExitConfirmation) {
                Button("Continue Shooting", role: .cancel) {}
                Button("End String", role: .destructive) {
                    endString()
                }
            } message: {
                Text("Leaving live monitoring should be intentional so the current string is not abandoned.")
            }
            .alert("Discard this string?", isPresented: $showReviewDiscardConfirmation) {
                Button("Keep Reviewing", role: .cancel) {}
                Button("Discard String", role: .destructive) {
                    discardReview()
                }
            } message: {
                Text("Unsaved corrections and impacts for this string will be lost.")
            }
        }
        .task {
            await loadInitialData()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch workflow.route {
        case .home:
            homeView
        case .sessionSetup:
            setupView
        case .cameraSetup:
            cameraSetupView
        case .ready:
            readyView
        case .liveString:
            liveStringView
        case .pausedString:
            pausedStringView
        case .stringReview:
            reviewView
        case .stringSummary:
            stringSummaryView
        case .sessionSummary:
            sessionSummaryView
        case .history:
            historyView
        case .historyDetail:
            historyDetailView
        case .settings:
            settingsView
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routeEyebrow)
                .font(.caption.bold())
                .foregroundStyle(Theme.accent)
            Text(navigationTitle)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.8)
            if let draft, workflow.route != .home {
                HStack(spacing: 10) {
                    metadataChip(draft.selectedTarget?.name ?? "Select target")
                    metadataChip(distanceLabel(draft.distance, unit: draft.distanceUnit))
                    metadataChip(draft.selectedFirearm?.nickname ?? "Select firearm")
                }
            }
        }
    }

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                beginNewSession()
            } label: {
                Label("New Session", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .accessibilityLabel("New Session")

            HStack(spacing: 12) {
                secondaryAction("History", systemImage: "clock.arrow.circlepath") {
                    workflow.openHistory()
                    Task { await loadHistoryAnalytics() }
                }
                secondaryAction("Settings", systemImage: "gearshape") {
                    workflow.openSettings()
                }
            }

            section("Recent Sessions") {
                if analyticsResult.historyItems.isEmpty {
                    Text(analyticsStatus)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(analyticsResult.historyItems.prefix(3)) { session in
                        Button {
                            selectedHistorySessionID = session.id
                            workflow.openHistoryDetail()
                        } label: {
                            historySummaryRows(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            firearmSetupSection
            targetSetupSection
            distanceSetupSection
            section("Audio") {
                Toggle(isOn: audioAssistBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Assist")
                        Text("Optional timing support only; visual confirmation is still required.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accent)
            }

            if let setupValidationMessage {
                Text(setupValidationMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                continueToCamera()
            } label: {
                Label("Continue", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!setupCanContinue)
            .accessibilityLabel("Continue to Camera Setup")
        }
    }

    private var firearmSetupSection: some View {
        section("Firearm") {
            if firearmProfiles.isEmpty {
                Text("Add a basic firearm profile to save this session with real metadata.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                Picker("Select Firearm", selection: selectedFirearmBinding) {
                    Text("Select Firearm").tag(Optional<FirearmProfileID>.none)
                    ForEach(firearmProfiles, id: \.id) { firearm in
                        Text(firearm.nickname).tag(Optional(firearm.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Select Firearm")
            }

            HStack(spacing: 10) {
                TextField("Firearm nickname", text: $newFirearmNickname)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Firearm nickname")
                Button("Add") {
                    addFirearmProfile()
                }
                .buttonStyle(.bordered)
                .disabled(newFirearmNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var targetSetupSection: some View {
        section("Target") {
            Picker("Select Target", selection: selectedTargetBinding) {
                ForEach(SupportedTargetCatalog.allTargetDefinitions, id: \.id) { target in
                    Text(target.name).tag(Optional(target.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select Target")
        }
    }

    private var distanceSetupSection: some View {
        section("Distance") {
            Picker("Distance", selection: distancePresetBinding) {
                ForEach([5.0, 7.0, 10.0, 15.0, 20.0, 25.0], id: \.self) { distance in
                    Text(distanceLabel(distance, unit: .yard)).tag(Optional(distance))
                }
                Text("Custom").tag(Optional<Double>.none)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Distance picker")

            if customDistanceActive {
                TextField("Custom yards", text: $customDistanceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Custom distance")
                    .onChange(of: customDistanceText) { _, newValue in
                        applyCustomDistance(newValue)
                    }
                if !(draft.map { SessionDraft.isValidDistance($0.distance) } ?? false) {
                    Text("Enter a distance from 1 to 100 yards.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private var cameraSetupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            CameraPreviewSurface(targetLockAssessment: targetLockAssessment)
            TargetLockPanel(
                source: targetLockSource,
                assessment: targetLockAssessment,
                onSourceSelected: { targetLockSource = $0 }
            )
            section("Framing") {
                row(title: "Preview", value: "Camera preview")
                row(title: "Target lock", value: targetLockAssessment.canLock ? "Ready" : "Improve framing")
                row(title: "Detection", value: "Not running")
            }
            Button {
                lockTarget()
            } label: {
                Label("Lock Target", systemImage: "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!targetLockAssessment.canLock)
            .accessibilityLabel("Lock Target")
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Target Locked") {
                row(title: "Target", value: draft?.selectedTarget?.name ?? "Selected target")
                row(title: "Distance", value: draft.map { distanceLabel($0.distance, unit: $0.distanceUnit) } ?? "Unavailable")
                row(title: "Firearm", value: draft?.selectedFirearm?.nickname ?? "No firearm")
                row(title: "Audio Assist", value: draft?.audioAssistEnabled == true ? "On" : "Off")
            }
            Text("Set the phone down, return to position, and start the string only when ready.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Button {
                startString()
            } label: {
                Label("Start String", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.success)
            .accessibilityLabel("Start String")
            secondaryAction("Re-lock Target", systemImage: "viewfinder") {
                workflow.back()
            }
        }
    }

    private var liveStringView: some View {
        VStack(alignment: .leading, spacing: 14) {
            correctionTargetPreview(status: "Live")
            section("String") {
                row(title: "Shot count", value: "\(editableShots.count)")
                row(title: "Audio Assist", value: draft?.audioAssistEnabled == true ? "On" : "Off")
                row(title: "Target lock", value: "Locked")
            }
            HStack(spacing: 12) {
                secondaryAction("Pause", systemImage: "pause.fill") {
                    workflow.pause()
                }
                Button {
                    endString()
                } label: {
                    Label("End String", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.warning)
                .accessibilityLabel("End String")
            }
        }
    }

    private var pausedStringView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Monitoring Paused") {
                row(title: "String", value: "\(workflow.activeStringIndex)")
                row(title: "Shots held", value: "\(editableShots.count)")
                Text("Resume to continue monitoring this string, or end it and review impacts.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            Button {
                workflow.resume()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.success)
            secondaryAction("End String", systemImage: "stop.fill") {
                endString()
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
                row(title: "Accepted shots", value: "\(editableShots.count)")
                row(title: "Total score", value: "\(currentStringScore)")
                row(title: "Distance", value: draft.map { distanceLabel($0.distance, unit: $0.distanceUnit) } ?? "Unavailable")
                ForEach(editableShots) { shot in
                    row(title: "Shot \(shot.id)", value: "\(shot.score)")
                }
            }
            saveStringControls
        }
    }

    private var saveStringControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                startSaveString()
            } label: {
                Label(saveButtonTitle, systemImage: saveButtonSystemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(saveFlowState == .failed ? Theme.warning : Theme.accent)
            .disabled(saveFlowState == .saving)
            .accessibilityLabel("Save String")

            if saveFlowState == .saving {
                ProgressView("Saving string")
                    .foregroundStyle(Theme.muted)
            }

            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stringSummaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("String Summary") {
                row(title: "String", value: "\(workflow.activeStringIndex)")
                row(title: "Shots", value: "\(lastSavedResult?.acceptedShotCount ?? editableShots.count)")
                row(title: "Score", value: scoreLabel(lastSavedResult?.scoringResult.totalScore))
                row(title: "Group", value: lengthLabel(lastSavedResult?.scoringResult.groupMetrics?.extremeSpread, unit: lastSavedResult?.scoringResult.groupMetrics?.groupCenter.unit))
                row(title: "Distance", value: draft.map { distanceLabel($0.distance, unit: $0.distanceUnit) } ?? "Unavailable")
                row(title: "Firearm", value: draft?.selectedFirearm?.nickname ?? "No firearm")
                row(title: "Target", value: draft?.selectedTarget?.name ?? "Selected target")
            }
            Button {
                shootAnotherString()
            } label: {
                Label("Shoot Another String", systemImage: "scope")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            secondaryAction("End Session", systemImage: "checkmark.seal") {
                workflow.endSession()
            }
        }
    }

    private var sessionSummaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Session Summary") {
                row(title: "Strings", value: "\(workflow.savedStrings.count)")
                row(title: "Total shots", value: "\(workflow.savedStrings.map(\.acceptedShotCount).reduce(0, +))")
                row(title: "Total score", value: scoreLabel(workflow.savedStrings.compactMap(\.totalScore).isEmpty ? nil : workflow.savedStrings.compactMap(\.totalScore).reduce(0, +)))
                row(title: "Distance", value: draft.map { distanceLabel($0.distance, unit: $0.distanceUnit) } ?? "Unavailable")
                row(title: "Firearm", value: draft?.selectedFirearm?.nickname ?? "No firearm")
                row(title: "Target", value: draft?.selectedTarget?.name ?? "Selected target")
            }
            Button {
                resetToHome()
            } label: {
                Label("Done", systemImage: "house.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            secondaryAction("View History", systemImage: "clock.arrow.circlepath") {
                workflow.openHistory()
                Task { await loadHistoryAnalytics() }
            }
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            historyFilterSection
            historyAnalyticsSection
            historyListSection
        }
        .task {
            await loadHistoryAnalytics()
        }
        .onChange(of: selectedDateRange) { _, _ in Task { await loadHistoryAnalytics() } }
        .onChange(of: selectedFirearmFilter) { _, _ in Task { await loadHistoryAnalytics() } }
        .onChange(of: selectedTargetFilter) { _, _ in Task { await loadHistoryAnalytics() } }
        .onChange(of: selectedDistanceFilter) { _, _ in Task { await loadHistoryAnalytics() } }
    }

    private var historyDetailView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item = selectedHistoryItem {
                historyDetailSection(item)
            } else {
                section("Session Detail") {
                    row(title: "Status", value: "Session unavailable")
                }
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Audio") {
                Toggle(isOn: settingsAudioBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Assist default")
                        Text("Microphone support remains optional and visual detection remains primary.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.accent)
            }
            section("Privacy") {
                ForEach(ReleasePrivacyDisclosure.allCopy, id: \.self) { disclosure in
                    Text(disclosure)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func beginNewSession() {
        workflow.beginNewSession(sessionID: SessionSaveIdentityFactory.sessionID(), createdAt: Date())
        targetLockSource = .assisted
        setupValidationMessage = nil
        newFirearmNickname = ""
        customDistanceText = "10"
        customDistanceActive = false
        resetWorkingString()
    }

    private func continueToCamera() {
        do {
            if customDistanceActive {
                guard let value = Double(customDistanceText), SessionDraft.isValidDistance(value) else {
                    setupValidationMessage = "Enter a distance from 1 to 100 yards."
                    return
                }
                try workflow.selectDistance(value, unit: .yard)
            }
            try workflow.continueToCamera()
            setupValidationMessage = nil
        } catch {
            setupValidationMessage = setupValidationText()
        }
    }

    private func lockTarget() {
        workflow.lockTarget(at: Date())
    }

    private func startString() {
        resetWorkingString()
        activeStringStartedAt = Date()
        workflow.startString(id: SessionSaveIdentityFactory.stringID())
    }

    private func endString() {
        workflow.endString()
        saveFlowState = .review
        saveErrorMessage = nil
    }

    private func shootAnotherString() {
        resetWorkingString()
        workflow.shootAnotherString()
    }

    private func resetToHome() {
        workflow.done()
        resetWorkingString()
        selectedHistorySessionID = nil
        Task { await loadHistoryAnalytics() }
    }

    private func discardReview() {
        resetWorkingString()
        workflow.discardStringToCamera()
    }

    private func handleBack() {
        switch workflow.exitPolicy {
        case .confirmEndOrContinue:
            showLiveExitConfirmation = true
        case .confirmDiscardString:
            showReviewDiscardConfirmation = true
        case .doneToHome:
            resetToHome()
        case .normalBack:
            workflow.back()
        }
    }

    private func addFirearmProfile() {
        let trimmed = newFirearmNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        let firearm = FirearmProfile(
            id: FirearmProfileID(rawValue: "firearm-\(UUID().uuidString)"),
            nickname: trimmed,
            category: .handgun,
            caliber: nil,
            notes: nil,
            createdAt: Date()
        )
        firearmProfiles.append(firearm)
        firearmProfiles.sort { $0.nickname < $1.nickname }
        workflow.selectFirearm(firearm)
        newFirearmNickname = ""
        setupValidationMessage = nil
    }

    private func applyCustomDistance(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setupValidationMessage = "Enter a distance from 1 to 100 yards."
            return
        }
        guard let value = Double(text), SessionDraft.isValidDistance(value) else {
            setupValidationMessage = "Enter a distance from 1 to 100 yards."
            return
        }
        try? workflow.selectDistance(value, unit: .yard)
        setupValidationMessage = nil
    }

    private var setupCanContinue: Bool {
        guard draft?.isValidForCameraSetup == true else {
            return false
        }
        if customDistanceActive {
            guard let value = Double(customDistanceText) else {
                return false
            }
            return SessionDraft.isValidDistance(value)
        }
        return true
    }

    private func setupValidationText() -> String {
        guard let draft else {
            return "Start a new session first."
        }
        if draft.validationErrors.contains(.missingFirearm) {
            return "Select or add a firearm before continuing."
        }
        if draft.validationErrors.contains(.missingTarget) {
            return "Select a target before continuing."
        }
        if draft.validationErrors.contains(.invalidDistance) {
            return "Choose a valid distance from 1 to 100 yards."
        }
        return "Complete setup before continuing."
    }

    private func resetWorkingString() {
        editableShots = []
        editableCandidates = []
        deletedShots = []
        selectedShotID = nil
        selectedCandidateID = nil
        isAddingImpact = false
        isMovingImpact = false
        saveErrorMessage = nil
        saveFlowState = .review
        saveGeneration += 1
        lastSavedResult = nil
    }

    private var saveButtonTitle: String {
        switch saveFlowState {
        case .review, .discarded:
            return "Save String"
        case .saving:
            return "Saving..."
        case .saved:
            return "Saved"
        case .failed:
            return "Retry Save"
        }
    }

    private var saveButtonSystemImage: String {
        switch saveFlowState {
        case .review, .discarded:
            return "checkmark.circle.fill"
        case .saving:
            return "hourglass"
        case .saved:
            return "checkmark.seal.fill"
        case .failed:
            return "arrow.clockwise.circle.fill"
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
                    workflow.markReviewChanged()
                } label: {
                    Label(isAddingImpact ? "Cancel Add" : "Add Impact", systemImage: isAddingImpact ? "xmark.circle" : "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(isAddingImpact ? Theme.warning : Theme.accent)
                .disabled(saveInProgress)
                .accessibilityLabel("Add Impact")

                Button {
                    confirmSelectedCandidate()
                } label: {
                    Label("Confirm Candidate", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selectedCandidateID == nil || saveInProgress)
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
                .disabled(selectedShotID == nil || saveInProgress)
                .accessibilityLabel("Move Impact")

                Button {
                    deleteSelectedShot()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Theme.warning)
                .disabled(selectedShotID == nil || saveInProgress)
                .accessibilityLabel("Delete Impact")
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
                    originalNormalized: nil,
                    score: scoreValue(for: coordinate),
                    confidence: 0,
                    source: .manualAdded
                )
            )
            selectedShotID = nextID
            isAddingImpact = false
            workflow.markReviewChanged()
            return
        }

        if isMovingImpact,
           let selectedShotID,
           let index = editableShots.firstIndex(where: { $0.id == selectedShotID }) {
            editableShots[index] = editableShots[index].moved(to: coordinate, score: scoreValue(for: coordinate))
            isMovingImpact = false
            workflow.markReviewChanged()
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
                originalNormalized: nil,
                score: scoreValue(for: candidate.normalized),
                confidence: candidate.confidence,
                source: .userConfirmed
            )
        )
        self.selectedCandidateID = nil
        selectedShotID = nextID
        isMovingImpact = false
        workflow.markReviewChanged()
    }

    private func deleteSelectedShot() {
        guard let selectedShotID else {
            return
        }
        if let deleted = editableShots.first(where: { $0.id == selectedShotID }) {
            deletedShots.append(deleted)
        }
        editableShots.removeAll { $0.id == selectedShotID }
        self.selectedShotID = nil
        isMovingImpact = false
        workflow.markReviewChanged()
    }

    private func startSaveString() {
        let event: ReleaseSaveFlowEvent = saveFlowState == .failed ? .retry : .saveTapped
        guard let nextState = ReleaseSaveFlow.nextState(from: saveFlowState, event: event),
              let stringID = workflow.activeStringID else {
            return
        }
        saveGeneration += 1
        let generation = saveGeneration
        saveFlowState = nextState
        saveErrorMessage = nil

        let request: SessionSaveRequest
        do {
            request = try makeSessionSaveRequest(stringID: stringID)
        } catch {
            saveFlowState = ReleaseSaveFlow.nextState(from: saveFlowState, event: .saveFailed) ?? .failed
            saveErrorMessage = "Save failed. Your reviewed string is still here; retry when ready."
            return
        }

        Task {
            do {
                let result = try await saveCoordinator.save(request, to: historyRepository)
                await MainActor.run {
                    guard generation == saveGeneration,
                          let savedState = ReleaseSaveFlow.nextState(from: saveFlowState, event: .saveSucceeded) else {
                        return
                    }
                    saveFlowState = savedState
                    lastSavedResult = result
                    workflow.saveString(
                        SavedStringSummary(
                            id: result.stringID,
                            index: workflow.activeStringIndex,
                            acceptedShotCount: result.acceptedShotCount,
                            totalScore: result.scoringResult.totalScore
                        )
                    )
                    Task { await loadHistoryAnalytics() }
                }
            } catch {
                await MainActor.run {
                    guard generation == saveGeneration,
                          let failedState = ReleaseSaveFlow.nextState(from: saveFlowState, event: .saveFailed) else {
                        return
                    }
                    saveFlowState = failedState
                    saveErrorMessage = "Save failed. Your reviewed string is still here; retry when ready."
                }
            }
        }
    }

    private func makeSessionSaveRequest(stringID: RangeStringID) throws -> SessionSaveRequest {
        guard let draft,
              let target = draft.selectedTarget else {
            throw SessionDraftValidationError.missingTarget
        }
        var correctionState = ImpactCorrectionState()
        for shot in editableShots.sorted(by: { $0.id < $1.id }) {
            try applyShot(shot, deleted: false, to: &correctionState, stringID: stringID)
        }
        for shot in deletedShots.sorted(by: { $0.id < $1.id }) {
            try applyShot(shot, deleted: true, to: &correctionState, stringID: stringID)
        }
        for candidate in editableCandidates {
            try correctionState.addMediumCandidate(
                RawImpactEvidence(
                    detectorEventID: nil,
                    candidateID: candidate.id,
                    coordinate: candidate.normalized,
                    confidence: candidate.confidence,
                    timestamp: nil
                )
            )
        }

        let session = RangeSession(
            id: draft.sessionID,
            startedAt: draft.createdAt,
            endedAt: nil,
            distance: draft.distance,
            distanceUnit: draft.distanceUnit,
            firearmID: draft.selectedFirearm?.id,
            targetDefinitionID: target.id,
            device: DeviceMetadata(platform: .iOS, modelName: nil, osVersion: nil, appVersion: nil)
        )
        let rangeString = RangeString(
            id: stringID,
            sessionID: draft.sessionID,
            index: workflow.activeStringIndex,
            baselineAssetID: nil,
            startedAt: activeStringStartedAt,
            endedAt: Date()
        )
        return try SessionSaveRequest(
            session: session,
            rangeString: rangeString,
            firearmProfile: draft.selectedFirearm,
            targetDefinition: target,
            correctionState: correctionState
        )
    }

    private func applyShot(
        _ shot: MockShotMarker,
        deleted: Bool,
        to state: inout ImpactCorrectionState,
        stringID: RangeStringID
    ) throws {
        let id = ShotID(rawValue: "shot-\(shot.id)")
        let timestamp = activeStringStartedAt.addingTimeInterval(Double(shot.id))
        switch shot.source {
        case .manualAdded:
            _ = try state.manuallyAddImpact(stringID: stringID, coordinate: shot.normalized, timestamp: timestamp)
        case .userConfirmed:
            let raw = try RawImpactEvidence(
                detectorEventID: nil,
                candidateID: "candidate-\(shot.id)",
                coordinate: shot.normalized,
                confidence: shot.confidence,
                timestamp: timestamp
            )
            state.addMediumCandidate(raw)
            _ = try state.confirmMediumCandidate(candidateID: "candidate-\(shot.id)", as: id, stringID: stringID, timestamp: timestamp)
        case .autoConfirmed, .corrected:
            _ = try state.ingestDetectorEvent(
                id: id,
                stringID: stringID,
                eventID: "detector-\(shot.id)",
                coordinate: shot.originalNormalized ?? shot.normalized,
                confidence: shot.confidence,
                timestamp: timestamp
            )
        }
        if let original = shot.originalNormalized, original != shot.normalized {
            try state.moveImpact(id: id, to: shot.normalized)
        }
        if deleted {
            try state.deleteImpact(id: id)
        }
    }

    private func scoreValue(for coordinate: NormalizedTargetCoordinate) -> Int {
        guard let targetID = draft?.selectedTarget?.id,
              let target = SupportedTargetCatalog.scoringTarget(for: targetID),
              let dimensions = target.physicalDimensions,
              let score = TargetScoringEngine().score(
                TargetCoordinateConverter.physicalPoint(from: coordinate, dimensions: dimensions),
                using: target
              ) else {
            return 0
        }
        return Int(score.value)
    }

    @MainActor
    private func loadInitialData() async {
        await loadHistoryAnalytics()
        do {
            let store = try await historyRepository.loadStore()
            firearmProfiles = store.firearmProfiles.sorted { $0.nickname < $1.nickname }
        } catch {
            firearmProfiles = []
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
            Set(store.rangeSessions.map { HistoryDistanceFilterOption(distance: $0.distance, unit: $0.distanceUnit) })
        )
        .sorted {
            if $0.unit == $1.unit {
                return $0.distance < $1.distance
            }
            return $0.unit.rawValue < $1.unit.rawValue
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

    private var selectedFirearmBinding: Binding<FirearmProfileID?> {
        Binding(
            get: { draft?.selectedFirearm?.id },
            set: { id in
                if let id, let firearm = firearmProfiles.first(where: { $0.id == id }) {
                    workflow.selectFirearm(firearm)
                    setupValidationMessage = nil
                }
            }
        )
    }

    private var selectedTargetBinding: Binding<TargetDefinitionID?> {
        Binding(
            get: { draft?.selectedTarget?.id },
            set: { id in
                if let id, let target = SupportedTargetCatalog.allTargetDefinitions.first(where: { $0.id == id }) {
                    workflow.selectTarget(target)
                    setupValidationMessage = nil
                }
            }
        )
    }

    private var distancePresetBinding: Binding<Double?> {
        Binding(
            get: {
                if customDistanceActive {
                    return nil
                }
                guard let distance = draft?.distance else {
                    return 10
                }
                return [5.0, 7.0, 10.0, 15.0, 20.0, 25.0].contains(distance) ? distance : nil
            },
            set: { value in
                if let value {
                    customDistanceActive = false
                    try? workflow.selectDistance(value, unit: .yard)
                    customDistanceText = decimal(value)
                    setupValidationMessage = nil
                } else {
                    customDistanceActive = true
                    customDistanceText = ""
                }
            }
        )
    }

    private var audioAssistBinding: Binding<Bool> {
        Binding(
            get: { draft?.audioAssistEnabled ?? false },
            set: { workflow.setAudioAssistEnabled($0) }
        )
    }

    private var settingsAudioBinding: Binding<Bool> {
        Binding(
            get: { draft?.audioAssistEnabled ?? false },
            set: { workflow.setAudioAssistEnabled($0) }
        )
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
                filterMenu(title: "Firearm", value: selectedFirearmFilter.flatMap(firearmName) ?? "All") {
                    Button("All") { selectedFirearmFilter = nil }
                    ForEach(firearmFilterOptions, id: \.id) { firearm in
                        Button(firearm.nickname) { selectedFirearmFilter = firearm.id }
                    }
                }
                filterMenu(title: "Distance", value: selectedDistanceFilter.map(distanceLabel) ?? "All") {
                    Button("All") { selectedDistanceFilter = nil }
                    ForEach(distanceFilterOptions) { option in
                        Button(distanceLabel(option)) { selectedDistanceFilter = option }
                    }
                }
                filterMenu(title: "Target", value: selectedTargetFilter.flatMap(targetName) ?? "All") {
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
                row(title: "Avg group", value: lengthLabel(analyticsResult.summary.averageGroupSize, unit: analyticsResult.summary.metricUnit))
                row(title: "Avg score", value: scoreLabel(analyticsResult.summary.averageScorePerString))
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
                        workflow.openHistoryDetail()
                    } label: {
                        historySummaryRows(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historySummaryRows(_ item: SessionHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row(title: shortDate(item.startedAt), value: item.firearmName ?? "No firearm")
            row(title: "Target", value: item.targetName ?? item.targetDefinitionID.rawValue)
            row(title: "Distance", value: distanceLabel(item.distance, unit: item.distanceUnit))
            row(title: "Shots", value: "\(item.acceptedShotCount)")
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

    private func filterMenu<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
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

    private var navigationTitle: String {
        switch workflow.route {
        case .home: return "RangeSight"
        case .sessionSetup: return "Session Setup"
        case .cameraSetup: return "Camera Setup"
        case .ready: return "Ready"
        case .liveString: return "Live String"
        case .pausedString: return "Paused"
        case .stringReview: return "String Review"
        case .stringSummary: return "String Summary"
        case .sessionSummary: return "Session Summary"
        case .history: return "History"
        case .historyDetail: return "Session Detail"
        case .settings: return "Settings"
        }
    }

    private var routeEyebrow: String {
        switch workflow.route {
        case .home: return "HOME"
        case .sessionSetup: return "SETUP"
        case .cameraSetup: return "FRAME TARGET"
        case .ready: return "TARGET LOCKED"
        case .liveString: return "MONITORING"
        case .pausedString: return "PAUSED"
        case .stringReview: return "REVIEW"
        case .stringSummary: return "SAVED STRING"
        case .sessionSummary: return "SESSION COMPLETE"
        case .history: return "LOCAL HISTORY"
        case .historyDetail: return "LOCAL HISTORY"
        case .settings: return "SETTINGS"
        }
    }

    private var backTitle: String {
        switch workflow.route {
        case .sessionSummary:
            return "Done"
        case .liveString, .pausedString:
            return "Leave"
        default:
            return "Back"
        }
    }

    private var backAccessibilityLabel: String {
        switch workflow.route {
        case .sessionSummary:
            return "Done and return home"
        case .liveString, .pausedString:
            return "Leave active string"
        default:
            return "Back"
        }
    }

    private func secondaryAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }

    private func metadataChip(_ value: String) -> some View {
        Text(value)
            .font(.caption.bold())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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
}

enum Theme {
    static let background = Color(.sRGB, red: 0.06, green: 0.07, blue: 0.08, opacity: 1)
    static let panel = Color(.sRGB, red: 0.10, green: 0.12, blue: 0.14, opacity: 1)
    static let text = Color(.sRGB, red: 0.94, green: 0.96, blue: 0.97, opacity: 1)
    static let muted = Color(.sRGB, red: 0.58, green: 0.63, blue: 0.68, opacity: 1)
    static let accent = Color(.sRGB, red: 0.96, green: 0.77, blue: 0.26, opacity: 1)
    static let success = Color(.sRGB, red: 0.48, green: 0.86, blue: 0.58, opacity: 1)
    static let warning = Color(.sRGB, red: 1.0, green: 0.42, blue: 0.36, opacity: 1)
}

private enum HistoryDateRangeSelection: String, CaseIterable, Identifiable {
    case allTime
    case last30Days
    case last90Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: return "All"
        case .last30Days: return "30d"
        case .last90Days: return "90d"
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

private enum SessionSaveIdentityFactory {
    static func sessionID() -> RangeSessionID {
        RangeSessionID(rawValue: "session-\(UUID().uuidString)")
    }

    static func stringID() -> RangeStringID {
        RangeStringID(rawValue: "string-\(UUID().uuidString)")
    }
}
