import SwiftUI
import RangeSightCore

struct TargetLockPanel: View {
    let source: TargetLockSource
    let assessment: TargetLockAssessment
    let onSourceSelected: (TargetLockSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sourceButton(.assisted, title: "Assisted", systemImage: "viewfinder")
                sourceButton(.manual, title: "Manual", systemImage: "hand.point.up.left.fill")
            }

            VStack(spacing: 8) {
                qualityRow(
                    title: "Framing",
                    value: assessment.qualityIssues.contains(.targetTooSmall) ? "Target too small" : "Target fills frame",
                    isPassing: !assessment.qualityIssues.contains(.targetTooSmall)
                )
                qualityRow(
                    title: "Sharpness",
                    value: formatted(assessment.qualityMetrics.sharpness),
                    isPassing: !assessment.qualityIssues.contains(.blurred)
                )
                qualityRow(
                    title: "Exposure",
                    value: exposureText,
                    isPassing: !assessment.qualityIssues.contains(.underExposed) && !assessment.qualityIssues.contains(.overExposed)
                )
                qualityRow(
                    title: "Features",
                    value: "\(assessment.qualityMetrics.registrationFeatureCount)",
                    isPassing: !assessment.qualityIssues.contains(.insufficientRegistrationFeatures)
                )
            }

            HStack {
                Label(assessment.canLock ? "Target ready" : "Lock unavailable", systemImage: assessment.canLock ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(assessment.canLock ? Theme.success : Theme.warning)
                Spacer()
                Text("\(Int(assessment.quadrilateral.normalizedArea * 100))% ROI")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var exposureText: String {
        if assessment.qualityIssues.contains(.underExposed) {
            return "Too dark"
        }

        if assessment.qualityIssues.contains(.overExposed) {
            return "Too bright"
        }

        return formatted(assessment.qualityMetrics.brightness)
    }

    private func sourceButton(_ candidate: TargetLockSource, title: String, systemImage: String) -> some View {
        Button {
            onSourceSelected(candidate)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(candidate == source ? Theme.accent : Theme.control)
    }

    private func qualityRow(title: String, value: String, isPassing: Bool) -> some View {
        HStack {
            Image(systemName: isPassing ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(isPassing ? Theme.success : Theme.warning)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

enum TargetLockPreviewData {
    static func assessment(source: TargetLockSource) -> TargetLockAssessment {
        let metrics: ImageQualityMetrics

        switch source {
        case .assisted:
            metrics = try! ImageQualityMetrics(
                sharpness: 0.84,
                brightness: 0.52,
                clippedHighlightRatio: 0.01,
                clippedShadowRatio: 0.02,
                registrationFeatureCount: 46
            )
        case .manual:
            metrics = try! ImageQualityMetrics(
                sharpness: 0.78,
                brightness: 0.49,
                clippedHighlightRatio: 0.02,
                clippedShadowRatio: 0.02,
                registrationFeatureCount: 38
            )
        }

        return try! TargetLockEvaluator.assess(
            source: source,
            quadrilateral: quadrilateral(source: source),
            qualityMetrics: metrics,
            targetDimensions: try! PhysicalDimensions(width: 18, height: 30, unit: .inch)
        )
    }

    private static func quadrilateral(source: TargetLockSource) -> TargetQuadrilateral {
        switch source {
        case .assisted:
            return try! TargetQuadrilateral(
                topLeft: try! NormalizedImagePoint(x: 0.18, y: 0.16),
                topRight: try! NormalizedImagePoint(x: 0.82, y: 0.18),
                bottomRight: try! NormalizedImagePoint(x: 0.78, y: 0.88),
                bottomLeft: try! NormalizedImagePoint(x: 0.2, y: 0.86)
            )
        case .manual:
            return try! TargetQuadrilateral(
                topLeft: try! NormalizedImagePoint(x: 0.21, y: 0.18),
                topRight: try! NormalizedImagePoint(x: 0.79, y: 0.19),
                bottomRight: try! NormalizedImagePoint(x: 0.77, y: 0.85),
                bottomLeft: try! NormalizedImagePoint(x: 0.23, y: 0.84)
            )
        }
    }
}
