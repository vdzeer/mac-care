import CoreGraphics

/// Lays weighted boxes out so that each takes area in proportion to its weight and stays close to square.
public enum Treemap {
    /// Returns one rectangle per weight, in the same order. Weights must be sorted largest first for a good picture.
    public static func layout(_ weights: [Double], in bounds: CGRect) -> [CGRect] {
        let total = weights.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: weights.count)
        }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = weights.map { max($0, 0) * scale }

        var rects = Array(repeating: CGRect.zero, count: weights.count)
        var free = bounds
        var start = 0
        while start < areas.count {
            // Grow the current row while that keeps its boxes closer to square.
            let side = Double(min(free.width, free.height))
            var end = start + 1
            while end < areas.count,
                worstRatio(areas[start..<(end + 1)], side: side) <= worstRatio(areas[start..<end], side: side)
            {
                end += 1
            }
            let row = areas[start..<end]
            let rowArea = row.reduce(0, +)
            let thickness = side > 0 ? CGFloat(rowArea / side) : 0
            var offset: CGFloat = 0
            for index in start..<end {
                let length = thickness > 0 ? CGFloat(areas[index]) / thickness : 0
                if free.width >= free.height {
                    rects[index] = CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                } else {
                    rects[index] = CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                }
                offset += length
            }
            if free.width >= free.height {
                free = CGRect(
                    x: free.minX + thickness, y: free.minY, width: max(free.width - thickness, 0), height: free.height)
            } else {
                free = CGRect(
                    x: free.minX, y: free.minY + thickness, width: free.width, height: max(free.height - thickness, 0))
            }
            start = end
        }
        return rects
    }

    /// The worst width-to-height ratio in a row of the given areas laid along a side of the given length.
    private static func worstRatio(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let largest = row.max(), let smallest = row.min(), smallest > 0 else {
            return .infinity
        }
        let square = side * side
        return max(square * largest / (sum * sum), (sum * sum) / (square * smallest))
    }
}
