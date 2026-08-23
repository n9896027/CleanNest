import CoreGraphics
import Foundation

public struct TreemapItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let weight: Double

    public init(id: String, weight: Double) {
        self.id = id
        self.weight = weight
    }
}

public struct TreemapPlacement: Identifiable, Equatable, Sendable {
    public let id: String
    public let rect: CGRect
    public let fraction: Double

    public init(id: String, rect: CGRect, fraction: Double) {
        self.id = id
        self.rect = rect
        self.fraction = fraction
    }
}

/// Deterministic squarified-treemap geometry with no UI or file-system access.
public enum TreemapLayout {
    private struct WeightedItem {
        let id: String
        let area: Double
        let fraction: Double
    }

    public static func layout(
        items: [TreemapItem],
        in bounds: CGRect
    ) -> [TreemapPlacement] {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else { return [] }

        let valid = items
            .filter { $0.weight.isFinite && $0.weight > 0 }
            .sorted {
                if $0.weight == $1.weight { return $0.id < $1.id }
                return $0.weight > $1.weight
            }
        let total = valid.reduce(0) { $0 + $1.weight }
        guard total.isFinite, total > 0 else { return [] }

        let boundsArea = Double(bounds.width * bounds.height)
        var remaining = valid.map {
            WeightedItem(
                id: $0.id,
                area: boundsArea * ($0.weight / total),
                fraction: $0.weight / total
            )
        }
        var available = bounds.standardized
        var row: [WeightedItem] = []
        var placements: [TreemapPlacement] = []

        while let next = remaining.first {
            let side = Double(min(available.width, available.height))
            if row.isEmpty || worstAspectRatio(row + [next], side: side) <= worstAspectRatio(row, side: side) {
                row.append(next)
                remaining.removeFirst()
            } else {
                layout(row: row, in: &available, into: &placements)
                row.removeAll(keepingCapacity: true)
            }
        }
        if !row.isEmpty {
            layout(row: row, in: &available, into: &placements)
        }
        return placements
    }

    private static func worstAspectRatio(_ row: [WeightedItem], side: Double) -> Double {
        guard !row.isEmpty, side > 0 else { return .infinity }
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0,
              let smallest = row.map(\.area).min(), smallest > 0,
              let largest = row.map(\.area).max() else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return max(
            sideSquared * largest / sumSquared,
            sumSquared / (sideSquared * smallest)
        )
    }

    private static func layout(
        row: [WeightedItem],
        in available: inout CGRect,
        into placements: inout [TreemapPlacement]
    ) {
        guard !row.isEmpty, available.width > 0, available.height > 0 else { return }
        let rowArea = row.reduce(0) { $0 + $1.area }

        if available.width >= available.height {
            let stripWidth = min(Double(available.width), rowArea / Double(available.height))
            var y = Double(available.minY)
            for (index, item) in row.enumerated() {
                let remainingHeight = Double(available.maxY) - y
                let height = index == row.count - 1
                    ? remainingHeight
                    : min(remainingHeight, item.area / max(stripWidth, .leastNonzeroMagnitude))
                placements.append(
                    TreemapPlacement(
                        id: item.id,
                        rect: CGRect(x: Double(available.minX), y: y, width: stripWidth, height: height),
                        fraction: item.fraction
                    )
                )
                y += height
            }
            available = CGRect(
                x: Double(available.minX) + stripWidth,
                y: Double(available.minY),
                width: max(0, Double(available.width) - stripWidth),
                height: Double(available.height)
            )
        } else {
            let stripHeight = min(Double(available.height), rowArea / Double(available.width))
            var x = Double(available.minX)
            for (index, item) in row.enumerated() {
                let remainingWidth = Double(available.maxX) - x
                let width = index == row.count - 1
                    ? remainingWidth
                    : min(remainingWidth, item.area / max(stripHeight, .leastNonzeroMagnitude))
                placements.append(
                    TreemapPlacement(
                        id: item.id,
                        rect: CGRect(x: x, y: Double(available.minY), width: width, height: stripHeight),
                        fraction: item.fraction
                    )
                )
                x += width
            }
            available = CGRect(
                x: Double(available.minX),
                y: Double(available.minY) + stripHeight,
                width: Double(available.width),
                height: max(0, Double(available.height) - stripHeight)
            )
        }
    }
}
