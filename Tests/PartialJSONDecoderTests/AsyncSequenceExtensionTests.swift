import Foundation
import PartialJSONDecoder
import Testing

@Suite("AsyncSequence+PartialJSON Extension Tests")
struct AsyncSequenceExtensionTests {
    struct SimpleValue: Codable, Equatable {
        let value: Int
    }

    @Test("Custom JSONDecoder Configuration")
    func testCustomJSONDecoderConfiguration() async throws {
        // Create a custom JSONDecoder that uses snake_case conversion
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .convertFromSnakeCase

        // Create a struct with a camelCase property that corresponds to snake_case in the JSON
        struct SnakeCaseValue: Codable, Equatable {
            let actualValue: Int
        }

        let asyncSequence = AsyncThroughSequence<UInt8>()

        // JSON with snake_case keys
        let json = "{\"actual_value\": 42}"

        // Start collecting
        let collectTask = Task {
            var results: [(SnakeCaseValue, Bool)] = []
            for try await result in asyncSequence.partialJSON(
                decoding: SnakeCaseValue.self,
                with: customDecoder
            ) {
                results.append(result)
            }
            return results
        }

        // Send JSON
        for byte in json.utf8 {
            await asyncSequence.send(byte)
        }

        await asyncSequence.finish()
        let results = try await collectTask.value

        // Check custom decoder properly converted snake_case to camelCase
        #expect(results.count > 0)
        if let (result, isComplete) = results.last {
            #expect(isComplete)
            #expect(result.actualValue == 42)
        }
    }

    @Test("Custom Buffer Size")
    func testCustomBufferSize() async throws {
        // Test with different buffer sizes
        let smallBufferSize = 8
        let largeBufferSize = 1024

        let json = "{\"value\": 100}"

        // Test with small buffer
        let smallBufferSequence = AsyncThroughSequence<UInt8>()

        let smallBufferTask = Task {
            var results: [(SimpleValue, Bool)] = []
            for try await result in smallBufferSequence.partialJSON(
                decoding: SimpleValue.self,
                bufferSize: smallBufferSize
            ) {
                results.append(result)
            }
            return results
        }

        // Send JSON to small buffer sequence
        for byte in json.utf8 {
            await smallBufferSequence.send(byte)
        }
        await smallBufferSequence.finish()
        let smallBufferResults = try await smallBufferTask.value

        // Test with large buffer
        let largeBufferSequence = AsyncThroughSequence<UInt8>()

        let largeBufferTask = Task {
            var results: [(SimpleValue, Bool)] = []
            for try await result in largeBufferSequence.partialJSON(
                decoding: SimpleValue.self,
                bufferSize: largeBufferSize
            ) {
                results.append(result)
            }
            return results
        }

        // Send JSON to large buffer sequence
        for byte in json.utf8 {
            await largeBufferSequence.send(byte)
        }
        await largeBufferSequence.finish()
        let largeBufferResults = try await largeBufferTask.value

        // Both should successfully decode
        #expect(smallBufferResults.count > 0)
        #expect(largeBufferResults.count > 0)

        if let (smallResult, smallComplete) = smallBufferResults.last,
            let (largeResult, largeComplete) = largeBufferResults.last
        {
            #expect(smallComplete)
            #expect(largeComplete)
            #expect(smallResult.value == 100)
            #expect(largeResult.value == 100)
        }
    }

    @Test("Extension Default Parameters")
    func testExtensionDefaultParameters() async throws {
        // Test the defaults of the extension method
        let asyncSequence = AsyncThroughSequence<UInt8>()
        let json = "{\"value\": 123}"

        // Start collecting
        let collectTask = Task {
            var results: [(SimpleValue, Bool)] = []
            // Use the method with just the required parameter
            for try await result in asyncSequence.partialJSON(decoding: SimpleValue.self) {
                results.append(result)
            }
            return results
        }

        // Send JSON
        for byte in json.utf8 {
            await asyncSequence.send(byte)
        }
        await asyncSequence.finish()
        let results = try await collectTask.value

        // Default parameters should work fine
        #expect(results.count > 0)
        if let (result, isComplete) = results.last {
            #expect(isComplete)
            #expect(result.value == 123)
        }
    }

    @Test("Working with Different AsyncSequences")
    func testDifferentAsyncSequences() async throws {
        // Create a simple array-backed async sequence
        let bytes = "{\"value\": 999}".utf8.map { $0 }
        let arrayAsyncSequence = AsyncStream<UInt8> { continuation in
            for byte in bytes {
                continuation.yield(byte)
            }
            continuation.finish()
        }

        // Use the extension method
        var results: [(SimpleValue, Bool)] = []
        for try await result in arrayAsyncSequence.partialJSON(decoding: SimpleValue.self) {
            results.append(result)
        }

        // Verify results
        #expect(results.count > 0)
        if let (result, isComplete) = results.last {
            #expect(isComplete)
            #expect(result.value == 999)
        }
    }
}
