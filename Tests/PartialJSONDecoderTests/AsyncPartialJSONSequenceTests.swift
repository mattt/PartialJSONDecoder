import Foundation
import PartialJSONDecoder
import Testing

@Suite("AsyncPartialJSONSequence Tests")
struct AsyncPartialJSONSequenceTests {
    struct Person: Codable, Equatable, Sendable {
        let name: String
        let age: Int
        let hobbies: [String]
    }

    struct SimpleValue: Codable, Equatable, Sendable {
        let value: Int
    }

    @Test("Top-level numbers retain their digits until EOF", arguments: [
        ("42", 42.0), ("-12.75", -12.75), ("3.5e-2", 0.035), ("2E+12", 2e12),
    ])
    func testNumberAtEOF(json: String, expected: Double) async throws {
        var completed: [Double] = []
        for try await result in AsyncBytes(json.utf8).partialJSON(decoding: Double.self)
        where result.isComplete {
            completed.append(result.value)
        }
        #expect(completed == [expected])
    }

    @Test("JSON whitespace terminates each top-level number")
    func testDelimitedNumbers() async throws {
        let json = " \t42\r\n42 7\t"
        var provisional: [Int] = []
        var completed: [Int] = []
        for try await result in AsyncBytes(json.utf8).partialJSON(decoding: Int.self) {
            if result.isComplete {
                completed.append(result.value)
            } else {
                provisional.append(result.value)
            }
        }
        #expect(provisional == [4, 42, 4, 42, 7])
        #expect(completed == [42, 42, 7])
    }

    @Test("Whitespace inside a numeric-looking string remains part of the value")
    func testStreamedString() async throws {
        let bytes = AsyncBytes(#""42 7""#.utf8)
        var completed: [String] = []
        for try await result in bytes.partialJSON(decoding: String.self) where result.isComplete {
            completed.append(result.value)
        }
        #expect(completed == ["42 7"])
    }

    @Test("Basic Async Partial JSON Sequence")
    func testBasicAsyncPartialJSONSequence() async throws {
        // Create a simpler sequence with fewer chunks for testing
        let json = "{\"name\": \"Charlie\", \"age\": 35, \"hobbies\": [\"cooking\", \"traveling\"]}"

        // Convert json to a byte sequence
        let byteSequence = json.utf8.map { $0 }
        let asyncSequence = AsyncThroughSequence<UInt8>()

        // Send all bytes at once
        for byte in byteSequence {
            await asyncSequence.send(byte)
        }

        // Signal end of sequence
        await asyncSequence.finish()

        // Now collect the results
        var results: [(Person, Bool)] = []

        for try await result in asyncSequence.partialJSON(decoding: Person.self) {
            results.append(result)
        }

        // After all iterations, check the results
        #expect(results.count > 0)

        // The last result should be complete and match expected values
        if let (lastResult, isComplete) = results.last {
            #expect(isComplete)
            #expect(lastResult.name == "Charlie")
            #expect(lastResult.age == 35)
            #expect(lastResult.hobbies == ["cooking", "traveling"])
        } else {
            Issue.record("No results from AsyncPartialJSONSequence")
        }
    }

    @Test("JSON Array Streaming")
    func testJSONArrayStreaming() async throws {
        // Test with an array of values
        let jsonArray = "[{\"value\": 10}, {\"value\": 20}, {\"value\": 30}]"
        let asyncSequence = AsyncThroughSequence<UInt8>()

        // Stream in the entire array
        for byte in jsonArray.utf8 {
            await asyncSequence.send(byte)
        }
        await asyncSequence.finish()

        // Collect results
        var results: [([SimpleValue], Bool)] = []
        for try await result in asyncSequence.partialJSON(decoding: [SimpleValue].self) {
            results.append(result)
        }

        // Should have at least one result
        #expect(results.count > 0)

        // Final result should contain all three values
        if let (finalArray, isComplete) = results.last {
            #expect(isComplete)
            #expect(finalArray.count == 3)
            #expect(finalArray[0].value == 10)
            #expect(finalArray[1].value == 20)
            #expect(finalArray[2].value == 30)
        }
    }

    @Test("Error Handling")
    func testErrorHandling() async throws {
        // Test malformed JSON
        let malformedJSON = "{\"name\": \"broken, \"age\": 50}"
        let asyncSequence = AsyncThroughSequence<UInt8>()

        // Send malformed JSON
        for byte in malformedJSON.utf8 {
            await asyncSequence.send(byte)
        }
        await asyncSequence.finish()

        // Try to decode - should eventually throw an error
        do {
            for try await _ in asyncSequence.partialJSON(decoding: Person.self) {
                // Should not get any valid results
            }
            Issue.record("Expected error with malformed JSON")
        } catch {
            // We expect an error
            #expect(Bool(true))
        }
    }
}
