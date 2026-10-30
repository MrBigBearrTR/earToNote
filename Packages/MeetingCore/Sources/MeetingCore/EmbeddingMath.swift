import Foundation

/// Vector helpers for speaker voiceprints (speaker embeddings).
///
/// A profile's voiceprint is the weighted mean of the L2-normalized embeddings it absorbed, together
/// with the total weight. Keeping the weight makes it possible to take a contribution back out
/// exactly, e.g. when the user says a speaker was matched to the wrong person.
public enum EmbeddingMath {
    public static func normalized(_ vector: [Float]) -> [Float] {
        let norm = magnitude(vector)
        guard norm > .ulpOfOne else { return vector }
        return vector.map { $0 / norm }
    }

    public static func magnitude(_ vector: [Float]) -> Float {
        var sum: Float = 0
        for value in vector {
            sum += value * value
        }
        return sum.squareRoot()
    }

    /// Cosine similarity in [-1, 1]. Returns 0 for empty, zero, or mismatched vectors.
    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var lhsSquared: Float = 0
        var rhsSquared: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsSquared += lhs[index] * lhs[index]
            rhsSquared += rhs[index] * rhs[index]
        }
        let denominator = lhsSquared.squareRoot() * rhsSquared.squareRoot()
        guard denominator > .ulpOfOne else { return 0 }
        return dot / denominator
    }

    public struct WeightedCentroid: Equatable, Sendable {
        public var vector: [Float]?
        public var weight: Double

        public init(vector: [Float]?, weight: Double) {
            self.vector = vector
            self.weight = vector == nil ? 0 : weight
        }
    }

    /// Adds `vector` (normalized first) with `vectorWeight` to the centroid.
    public static func adding(_ vector: [Float], weight vectorWeight: Double, to centroid: WeightedCentroid) -> WeightedCentroid {
        let unit = normalized(vector)
        guard vectorWeight > 0, !unit.isEmpty else { return centroid }
        guard let current = centroid.vector, centroid.weight > 0, current.count == unit.count else {
            return WeightedCentroid(vector: unit, weight: vectorWeight)
        }
        let total = centroid.weight + vectorWeight
        let currentShare = Float(centroid.weight / total)
        let addedShare = Float(vectorWeight / total)
        let merged = zip(current, unit).map { $0 * currentShare + $1 * addedShare }
        return WeightedCentroid(vector: merged, weight: total)
    }

    /// Combines two centroids as if all of their contributions had been added to one.
    public static func merging(_ other: WeightedCentroid, into centroid: WeightedCentroid) -> WeightedCentroid {
        guard let otherVector = other.vector, other.weight > 0 else { return centroid }
        guard let current = centroid.vector, centroid.weight > 0, current.count == otherVector.count else {
            return other
        }
        let total = centroid.weight + other.weight
        let currentShare = Float(centroid.weight / total)
        let otherShare = Float(other.weight / total)
        let merged = zip(current, otherVector).map { $0 * currentShare + $1 * otherShare }
        return WeightedCentroid(vector: merged, weight: total)
    }

    /// Reverses a previous `adding(_:weight:to:)` call. Removing everything clears the voiceprint.
    public static func removing(_ vector: [Float], weight vectorWeight: Double, from centroid: WeightedCentroid) -> WeightedCentroid {
        let unit = normalized(vector)
        guard vectorWeight > 0, let current = centroid.vector, current.count == unit.count else { return centroid }
        let remaining = centroid.weight - vectorWeight
        guard remaining > 1e-6 else { return WeightedCentroid(vector: nil, weight: 0) }
        let total = Float(centroid.weight)
        let removed = Float(vectorWeight)
        let rest = Float(remaining)
        let vector = zip(current, unit).map { ($0 * total - $1 * removed) / rest }
        return WeightedCentroid(vector: vector, weight: remaining)
    }

    public static func encode(_ vector: [Float]) -> Data {
        var data = Data(capacity: vector.count * MemoryLayout<UInt32>.size)
        for value in vector {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decode(_ data: Data) -> [Float] {
        let stride = MemoryLayout<UInt32>.size
        guard data.count % stride == 0 else { return [] }
        var vector: [Float] = []
        vector.reserveCapacity(data.count / stride)
        var index = data.startIndex
        while index < data.endIndex {
            var bits: UInt32 = 0
            for offset in 0..<stride {
                bits |= UInt32(data[index + offset]) << (8 * UInt32(offset))
            }
            vector.append(Float(bitPattern: bits))
            index += stride
        }
        return vector
    }
}
