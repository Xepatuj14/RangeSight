import SwiftUI
import RangeSightCore

struct TargetPreviewView: View {
    let shots: [MockShotMarker]
    let candidates: [MockImpactCandidateMarker]
    let status: String
    let selectedShotID: Int?
    let selectedCandidateID: String?
    let onShotSelected: (Int) -> Void
    let onCandidateSelected: (String) -> Void
    let onTargetTapped: (NormalizedTargetCoordinate) -> Void

    init(
        shots: [MockShotMarker],
        candidates: [MockImpactCandidateMarker],
        status: String,
        selectedShotID: Int? = nil,
        selectedCandidateID: String? = nil,
        onShotSelected: @escaping (Int) -> Void = { _ in },
        onCandidateSelected: @escaping (String) -> Void = { _ in },
        onTargetTapped: @escaping (NormalizedTargetCoordinate) -> Void = { _ in }
    ) {
        self.shots = shots
        self.candidates = candidates
        self.status = status
        self.selectedShotID = selectedShotID
        self.selectedCandidateID = selectedCandidateID
        self.onShotSelected = onShotSelected
        self.onCandidateSelected = onCandidateSelected
        self.onTargetTapped = onTargetTapped
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TargetPreviewBackground()
            TargetPreviewGeometryView(
                shots: shots,
                candidates: candidates,
                selectedShotID: selectedShotID,
                selectedCandidateID: selectedCandidateID,
                onShotSelected: onShotSelected,
                onCandidateSelected: onCandidateSelected,
                onTargetTapped: onTargetTapped
            )
            StatusBadge(text: status)
        }
        .frame(minHeight: 360)
        .accessibilityLabel("Mock target preview")
    }
}

private struct TargetPreviewBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.black)
            .aspectRatio(0.74, contentMode: .fit)
    }
}

private struct TargetPreviewGeometryView: View {
    let shots: [MockShotMarker]
    let candidates: [MockImpactCandidateMarker]
    let selectedShotID: Int?
    let selectedCandidateID: String?
    let onShotSelected: (Int) -> Void
    let onCandidateSelected: (String) -> Void
    let onTargetTapped: (NormalizedTargetCoordinate) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = TargetPreviewLayout(size: proxy.size)

            TargetSurfaceView(
                shots: shots,
                candidates: candidates,
                selectedShotID: selectedShotID,
                selectedCandidateID: selectedCandidateID,
                side: layout.side,
                onShotSelected: onShotSelected,
                onCandidateSelected: onCandidateSelected,
                onTargetTapped: onTargetTapped
            )
            .frame(width: layout.side, height: layout.side)
            .position(x: layout.centerX, y: layout.centerY)
        }
        .padding(16)
    }
}

private struct TargetPreviewLayout {
    let side: CGFloat
    let centerX: CGFloat
    let centerY: CGFloat

    init(size: CGSize) {
        side = min(size.width * 0.72, size.height * 0.78)
        centerX = size.width / 2
        centerY = size.height / 2
    }
}

private struct TargetSurfaceView: View {
    let shots: [MockShotMarker]
    let candidates: [MockImpactCandidateMarker]
    let selectedShotID: Int?
    let selectedCandidateID: String?
    let side: CGFloat
    let onShotSelected: (Int) -> Void
    let onCandidateSelected: (String) -> Void
    let onTargetTapped: (NormalizedTargetCoordinate) -> Void

    var body: some View {
        ZStack {
            TargetFaceView(side: side)
            ConfirmedImpactMarkerLayer(
                shots: shots,
                selectedShotID: selectedShotID,
                side: side,
                onShotSelected: onShotSelected
            )
            MediumCandidateMarkerLayer(
                candidates: candidates,
                selectedCandidateID: selectedCandidateID,
                side: side,
                onCandidateSelected: onCandidateSelected
            )
        }
        .contentShape(Rectangle())
        .gesture(targetTapGesture)
    }

    private var targetTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if let coordinate = normalizedCoordinate(for: value.location) {
                    onTargetTapped(coordinate)
                }
            }
    }

    private func normalizedCoordinate(for location: CGPoint) -> NormalizedTargetCoordinate? {
        guard let coordinate = try? TargetDisplayGeometry(
            containerWidth: Double(side),
            containerHeight: Double(side)
        ).normalizedCoordinate(at: DisplayPoint(x: Double(location.x), y: Double(location.y))) else {
            return nil
        }

        return coordinate
    }
}

private struct TargetFaceView: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.sRGB, red: 0.91, green: 0.90, blue: 0.86, opacity: 1))
            Circle()
                .stroke(Color.black, lineWidth: 18)
                .frame(width: side * 0.58, height: side * 0.58)
            Circle()
                .fill(Color.yellow)
                .frame(width: 10, height: 10)
        }
    }
}

private struct ConfirmedImpactMarkerLayer: View {
    let shots: [MockShotMarker]
    let selectedShotID: Int?
    let side: CGFloat
    let onShotSelected: (Int) -> Void

    var body: some View {
        ForEach(shots) { shot in
            ConfirmedImpactMarkerButton(
                shot: shot,
                isSelected: shot.id == selectedShotID,
                side: side,
                onShotSelected: onShotSelected
            )
        }
    }
}

private struct ConfirmedImpactMarkerButton: View {
    let shot: MockShotMarker
    let isSelected: Bool
    let side: CGFloat
    let onShotSelected: (Int) -> Void

    var body: some View {
        Button {
            onShotSelected(shot.id)
        } label: {
            ShotMarkerView(shot: shot, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .position(markerPosition)
    }

    private var markerPosition: CGPoint {
        CGPoint(
            x: CGFloat(shot.normalized.x) * side,
            y: CGFloat(shot.normalized.y) * side
        )
    }
}

private struct MediumCandidateMarkerLayer: View {
    let candidates: [MockImpactCandidateMarker]
    let selectedCandidateID: String?
    let side: CGFloat
    let onCandidateSelected: (String) -> Void

    var body: some View {
        ForEach(candidates) { candidate in
            MediumCandidateMarkerButton(
                candidate: candidate,
                isSelected: candidate.id == selectedCandidateID,
                side: side,
                onCandidateSelected: onCandidateSelected
            )
        }
    }
}

private struct MediumCandidateMarkerButton: View {
    let candidate: MockImpactCandidateMarker
    let isSelected: Bool
    let side: CGFloat
    let onCandidateSelected: (String) -> Void

    var body: some View {
        Button {
            onCandidateSelected(candidate.id)
        } label: {
            CandidateMarkerView(candidate: candidate, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .position(markerPosition)
    }

    private var markerPosition: CGPoint {
        CGPoint(
            x: CGFloat(candidate.normalized.x) * side,
            y: CGFloat(candidate.normalized.y) * side
        )
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.yellow)
            .padding(.bottom, 16)
    }
}

private struct CandidateMarkerView: View {
    let candidate: MockImpactCandidateMarker
    let isSelected: Bool

    var body: some View {
        Circle()
            .stroke(isSelected ? Color.white : Color.orange, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            .frame(width: 34, height: 34)
            .accessibilityLabel("Candidate impact \(candidate.id)")
    }
}

private struct ShotMarkerView: View {
    let shot: MockShotMarker
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(shot.source == .autoConfirmed ? Color.yellow : Color.orange)
                .frame(width: 30, height: 30)
            Circle()
                .stroke(isSelected ? Color.white : Color.black, lineWidth: isSelected ? 4 : 2)
                .frame(width: isSelected ? 34 : 30, height: isSelected ? 34 : 30)
            Text("\(shot.id)")
                .font(.caption.bold())
                .foregroundStyle(Color.black)
        }
        .accessibilityLabel("Shot \(shot.id)")
    }
}
