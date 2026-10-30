import XCTest
@testable import MeetingCore

final class EmbeddingMathTests: XCTestCase {
    func testCosineSimilarity() {
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 0], [2, 0]), 1, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 0], [0, 3]), 0, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 0], [-1, 0]), -1, accuracy: 1e-6)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([1, 0], [1, 0, 0]), 0)
        XCTAssertEqual(EmbeddingMath.cosineSimilarity([0, 0], [1, 0]), 0)
    }

    func testAddingStartsEmptyCentroidWithNormalizedVector() {
        let empty = EmbeddingMath.WeightedCentroid(vector: nil, weight: 0)

        let result = EmbeddingMath.adding([3, 4], weight: 10, to: empty)

        assertVector(result.vector, [0.6, 0.8])
        XCTAssertEqual(result.weight, 10)
    }

    func testAddingIsWeightedAverageOfUnitVectors() {
        let start = EmbeddingMath.WeightedCentroid(vector: [1, 0], weight: 30)

        let result = EmbeddingMath.adding([0, 5], weight: 10, to: start)

        assertVector(result.vector, [0.75, 0.25])
        XCTAssertEqual(result.weight, 40)
    }

    func testRemovingUndoesAdding() {
        let start = EmbeddingMath.WeightedCentroid(vector: [1, 0], weight: 30)
        let added = EmbeddingMath.adding([0, 2], weight: 10, to: start)

        let removed = EmbeddingMath.removing([0, 2], weight: 10, from: added)

        assertVector(removed.vector, [1, 0])
        XCTAssertEqual(removed.weight, 30, accuracy: 1e-9)
    }

    func testRemovingLastContributionClearsVoiceprint() {
        let only = EmbeddingMath.adding([1, 1], weight: 5, to: .init(vector: nil, weight: 0))

        let removed = EmbeddingMath.removing([1, 1], weight: 5, from: only)

        XCTAssertNil(removed.vector)
        XCTAssertEqual(removed.weight, 0)
    }

    func testMergingCombinesWeights() {
        let lhs = EmbeddingMath.WeightedCentroid(vector: [1, 0], weight: 10)
        let rhs = EmbeddingMath.WeightedCentroid(vector: [0, 1], weight: 30)

        let merged = EmbeddingMath.merging(rhs, into: lhs)

        assertVector(merged.vector, [0.25, 0.75])
        XCTAssertEqual(merged.weight, 40)
        XCTAssertEqual(EmbeddingMath.merging(rhs, into: .init(vector: nil, weight: 0)), rhs)
        XCTAssertEqual(EmbeddingMath.merging(.init(vector: nil, weight: 0), into: lhs), lhs)
    }

    func testEncodeDecodeRoundTrip() {
        let vector: [Float] = [0, 1.5, -2.25, .pi, 1e-7, -0]

        let decoded = EmbeddingMath.decode(EmbeddingMath.encode(vector))

        XCTAssertEqual(decoded, vector)
        XCTAssertEqual(EmbeddingMath.encode(vector).count, vector.count * 4)
        XCTAssertEqual(EmbeddingMath.decode(Data([1, 2, 3])), [])
    }

    private func assertVector(_ actual: [Float]?, _ expected: [Float], file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("vector is nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) {
            XCTAssertEqual(lhs, rhs, accuracy: 1e-5, file: file, line: line)
        }
    }
}
