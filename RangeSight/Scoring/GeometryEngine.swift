public enum GeometryError: Error, Equatable {
    case insufficientShots
    case mixedUnits
}

public enum TargetCoordinateConverter {
    public static func physicalPoint(
        from normalized: NormalizedTargetCoordinate,
        dimensions: PhysicalDimensions
    ) -> PhysicalPoint {
        PhysicalPoint(
            x: (normalized.x - 0.5) * dimensions.width,
            y: (0.5 - normalized.y) * dimensions.height,
            unit: dimensions.unit
        )
    }
}

public struct GroupMetrics: Equatable, Sendable {
    public let shotCount: Int
    public let groupCenter: PhysicalPoint
    public let extremeSpread: Double
    public let meanRadius: Double
    public let pointOfImpactOffset: PhysicalPoint
    public let horizontalStandardDeviation: Double
    public let verticalStandardDeviation: Double

    public init(
        shotCount: Int,
        groupCenter: PhysicalPoint,
        extremeSpread: Double,
        meanRadius: Double,
        pointOfImpactOffset: PhysicalPoint,
        horizontalStandardDeviation: Double,
        verticalStandardDeviation: Double
    ) {
        self.shotCount = shotCount
        self.groupCenter = groupCenter
        self.extremeSpread = extremeSpread
        self.meanRadius = meanRadius
        self.pointOfImpactOffset = pointOfImpactOffset
        self.horizontalStandardDeviation = horizontalStandardDeviation
        self.verticalStandardDeviation = verticalStandardDeviation
    }
}

public enum GroupMetricCalculator {
    public static func metrics(
        for points: [PhysicalPoint],
        aimPoint: PhysicalPoint
    ) throws -> GroupMetrics {
        guard !points.isEmpty else {
            throw GeometryError.insufficientShots
        }

        let unit = points[0].unit
        guard points.allSatisfy({ $0.unit == unit }) && aimPoint.unit == unit else {
            throw GeometryError.mixedUnits
        }

        let count = Double(points.count)
        let centerX = points.map(\.x).reduce(0, +) / count
        let centerY = points.map(\.y).reduce(0, +) / count
        let center = PhysicalPoint(x: centerX, y: centerY, unit: unit)

        let extremeSpread = maxPairwiseDistance(points)
        let meanRadius = points
            .map { distance($0, center) }
            .reduce(0, +) / count

        let poiOffset = PhysicalPoint(
            x: center.x - aimPoint.x,
            y: center.y - aimPoint.y,
            unit: unit
        )

        return GroupMetrics(
            shotCount: points.count,
            groupCenter: center,
            extremeSpread: extremeSpread,
            meanRadius: meanRadius,
            pointOfImpactOffset: poiOffset,
            horizontalStandardDeviation: standardDeviation(points.map(\.x), mean: center.x),
            verticalStandardDeviation: standardDeviation(points.map(\.y), mean: center.y)
        )
    }

    public static func distance(_ lhs: PhysicalPoint, _ rhs: PhysicalPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func maxPairwiseDistance(_ points: [PhysicalPoint]) -> Double {
        guard points.count > 1 else {
            return 0
        }

        var maxDistance = 0.0

        for leftIndex in points.indices {
            for rightIndex in points.index(after: leftIndex)..<points.endIndex {
                maxDistance = max(maxDistance, distance(points[leftIndex], points[rightIndex]))
            }
        }

        return maxDistance
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let variance = values
            .map { value in
                let delta = value - mean
                return delta * delta
            }
            .reduce(0, +) / Double(values.count)

        return variance.squareRoot()
    }
}
