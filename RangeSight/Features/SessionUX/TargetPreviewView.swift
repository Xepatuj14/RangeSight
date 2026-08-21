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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
                .aspectRatio(0.74, contentMode: .fit)

            GeometryReader { proxy in
                let side = min(proxy.size.width * 0.72, proxy.size.height * 0.78)
                let originX = (proxy.size.width - side) / 2
                let originY = (proxy.size.height - side) / 2

                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.sRGB, red: 0.91, green: 0.90, blue: 0.86, opacity: 1))
                    Circle()
                        .stroke(Color.black, lineWidth: 18)
                        .frame(width: side * 0.58, height: side * 0.58)
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 10, height: 10)

                    ForEach(shots) { shot in
                        Button {
                            onShotSelected(shot.id)
                        } label: {
                            ShotMarkerView(shot: shot, isSelected: shot.id == selectedShotID)
                        }
                        .buttonStyle(.plain)
                            .position(
                                x: shot.normalized.x * side,
                                y: shot.normalized.y * side
                            )
                    }

                    ForEach(candidates) { candidate in
                        Button {
                            onCandidateSelected(candidate.id)
                        } label: {
                            CandidateMarkerView(candidate: candidate, isSelected: candidate.id == selectedCandidateID)
                        }
                        .buttonStyle(.plain)
                            .position(
                                x: candidate.normalized.x * side,
                                y: candidate.normalized.y * side
                            )
                    }
                }
                .frame(width: side, height: side)
                .position(x: originX + side / 2, y: originY + side / 2)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let coordinate = try? TargetDisplayGeometry(
                                containerWidth: side,
                                containerHeight: side
                            ).normalizedCoordinate(at: DisplayPoint(x: value.location.x, y: value.location.y)) else {
                                return
                            }

                            if let coordinate {
                                onTargetTapped(coordinate)
                            }
                        }
                )
            }
            .padding(16)

            Text(status.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.yellow)
                .padding(.bottom, 16)
        }
        .frame(minHeight: 360)
        .accessibilityLabel("Mock target preview")
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
