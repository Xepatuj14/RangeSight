import SwiftUI

struct TargetPreviewView: View {
    let shots: [MockShotMarker]
    let candidates: [MockImpactCandidateMarker]
    let status: String

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
                        ShotMarkerView(shot: shot)
                            .position(
                                x: shot.normalized.x * side,
                                y: shot.normalized.y * side
                            )
                    }

                    ForEach(candidates) { candidate in
                        CandidateMarkerView(candidate: candidate)
                            .position(
                                x: candidate.normalized.x * side,
                                y: candidate.normalized.y * side
                            )
                    }
                }
                .frame(width: side, height: side)
                .position(x: originX + side / 2, y: originY + side / 2)
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

    var body: some View {
        Circle()
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            .frame(width: 34, height: 34)
            .accessibilityLabel("Candidate impact \(candidate.id)")
    }
}

private struct ShotMarkerView: View {
    let shot: MockShotMarker

    var body: some View {
        ZStack {
            Circle()
                .fill(shot.source == .autoConfirmed ? Color.yellow : Color.orange)
                .frame(width: 30, height: 30)
            Circle()
                .stroke(Color.black, lineWidth: 2)
                .frame(width: 30, height: 30)
            Text("\(shot.id)")
                .font(.caption.bold())
                .foregroundStyle(Color.black)
        }
        .accessibilityLabel("Shot \(shot.id)")
    }
}
