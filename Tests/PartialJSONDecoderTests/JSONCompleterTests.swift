import Foundation
import PartialJSONDecoder
import Testing

@Suite("JSONCompleter Tests")
final class JSONCompleterTests {
    @Test("Complete JSON")
    func testCompleteJSON() throws {
        let completer = JSONCompleter()

        // Test complete JSON with various types
        #expect(try completer.complete("42") == "42")
        #expect(try completer.complete("\"hello\"") == "\"hello\"")
        #expect(try completer.complete("[1, 2, 3]") == "[1, 2, 3]")
        #expect(try completer.complete("{\"a\": 1}") == "{\"a\": 1}")
        #expect(try completer.complete("true") == "true")
        #expect(try completer.complete("null") == "null")
    }

    @Test("Partial JSON Completion")
    func testPartialJSONCompletion() throws {
        let completer = JSONCompleter()

        // Test partial JSON
        #expect(try completer.complete("[1, 2, 3") == "[1, 2, 3]")
        #expect(try completer.complete("{\"a\": 1") == "{\"a\": 1}")
        #expect(try completer.complete("\"hello") == "\"hello\"")
        #expect(
            try completer.complete(
                "{\"name\": \"Alice\", \"age\": 30, \"hobbies\": [\"reading\", \"hiking\"")
                == "{\"name\": \"Alice\", \"age\": 30, \"hobbies\": [\"reading\", \"hiking\"]}")
    }

    @Test("Values after empty nested collections")
    func testValuesAfterEmptyNestedCollections() throws {
        let completer = JSONCompleter()

        #expect(try completer.complete("{\"a\": {}, \"b\": 2") == "{\"a\": {}, \"b\": 2}")
        #expect(try completer.complete("{\"a\": [], \"b\": 2") == "{\"a\": [], \"b\": 2}")
        #expect(try completer.complete("[{}, 2") == "[{}, 2]")
        #expect(try completer.complete("[[], 2") == "[[], 2]")
    }

    @Test("Whitespace before collection delimiters")
    func testWhitespaceBeforeCollectionDelimiters() throws {
        let completer = JSONCompleter()

        #expect(try completer.complete("[1 , 2") == "[1 , 2]")
        #expect(try completer.complete("{\"a\": 1 , \"b\": 2") == "{\"a\": 1 , \"b\": 2}")
    }

    @Test("Public Completion Method")
    func testPublicCompletionMethod() throws {
        let completer = JSONCompleter()

        // Test with complete JSON - should return nil
        #expect(try completer.completion(for: "[1, 2, 3]", from: "[1, 2, 3]".startIndex) == nil)
        #expect(try completer.completion(for: "{\"a\": 1}", from: "{\"a\": 1}".startIndex) == nil)
        #expect(try completer.completion(for: "\"hello\"", from: "\"hello\"".startIndex) == nil)

        // Test with partial JSON - should return completion info
        let arrayCompletion = try completer.completion(for: "[1, 2, 3", from: "[1, 2, 3".startIndex)
        #expect(arrayCompletion != nil)
        #expect(arrayCompletion?.string == "]")

        let objectCompletion = try completer.completion(
            for: "{\"a\": 1", from: "{\"a\": 1".startIndex)
        #expect(objectCompletion != nil)
        #expect(objectCompletion?.string == "}")

        let stringCompletion = try completer.completion(for: "\"hello", from: "\"hello".startIndex)
        #expect(stringCompletion != nil)
        #expect(stringCompletion?.string == "\"")

        // Test with partial nested object
        let nestedCompletion = try completer.completion(
            for: "{\"obj\": {\"arr\": [1, 2,",
            from: "{\"obj\": {\"arr\": [1, 2,".startIndex
        )
        #expect(nestedCompletion != nil)
        #expect(nestedCompletion?.string == "]}}")

        // Test calling the method from a specific point in the string
        let partialString = "{\"complete\": true, \"partial\": {\"arr\": [1, 2,"
        let midIndex = partialString.lastIndex(of: "{")!
        let partialCompletion = try completer.completion(for: partialString, from: midIndex)
        #expect(partialCompletion != nil)
        #expect(partialCompletion?.string == "]}")
    }

    @Test("Depth Limit Protection")
    func testDepthLimitError() {
        // Create a completer with a small max depth for testing
        let completer = JSONCompleter()
        completer.maximumDepth = 10

        // Test with a JSON structure that exceeds the max depth
        let deepArrayOpening = String(repeating: "[", count: 20)

        do {
            _ = try completer.complete(deepArrayOpening)
            // If we reach here, the test should fail because no error was thrown
            #expect(Bool(false), "Expected an error to be thrown for deep nesting, but none was")
        } catch {
            // We expect an error, so this is success
            // Check that it's the right type
            #expect(error is JSONCompletionError)
        }

        // Check with a valid depth (5 levels of nesting is safe)
        do {
            let validDepthArrayOpening = String(repeating: "[", count: 5)
            let validDepthArrayClosing = String(repeating: "]", count: 5)
            let completed = try completer.complete(validDepthArrayOpening)
            #expect(completed == validDepthArrayOpening + validDepthArrayClosing)
        } catch {
            #expect(Bool(false), "Should not throw an error for valid depth: \(error)")
        }

        // Default completer should have a higher limit
        let defaultCompleter = JSONCompleter()
        #expect(defaultCompleter.maximumDepth >= 32)
    }

    @Test("Complex Nested Structures")
    func testComplexNestedStructures() throws {
        let completer = JSONCompleter()

        // Test a complex nested structure with many different types
        let complexPartial = """
            {
              "name": "Complex Test",
              "data": {
                "numbers": [1, 2, 3, 4, 5],
                "boolean": true,
                "nested": {
                  "array": [
                    {"id": 1, "value": "first"},
                    {"id": 2, "value": "second"},
                    {"id": 3, "value": "third"
            """

        let completed = try completer.complete(complexPartial)

        // Expected completion should close all the open structures
        #expect(completed.hasSuffix("}]}}}"))

        // The result should be valid JSON
        #expect(isValidJSON(completed))
    }

    @Test("Special Character Handling")
    func testSpecialCharacterHandling() throws {
        let completer = JSONCompleter()

        // Test strings with special characters and escapes
        let specialCharString =
            "\"Special \\\"quoted\\\" and \\n newline and \\t tab and \\u2665 unicode"
        let completed = try completer.complete(specialCharString)

        // Should close the string properly
        #expect(completed.hasSuffix("\""))
        #expect(
            completed
                == "\"Special \\\"quoted\\\" and \\n newline and \\t tab and \\u2665 unicode\"")

        // Test partial escape sequence
        let partialEscape = "\"Partial escape: \\"
        let completedEscape = try completer.complete(partialEscape)
        #expect(completedEscape == "\"Partial escape: \"")
        #expect(isValidJSON(completedEscape))

        // Test partial Unicode escape
        let partialUnicode = "\"Unicode escape: \\u26"
        let completedUnicode = try completer.complete(partialUnicode)
        #expect(completedUnicode == "\"Unicode escape: \"")
        #expect(isValidJSON(completedUnicode))

        for unicodeEscape in ["\\u", "\\u2", "\\u26", "\\u266"] {
            let completedPrefix = try completer.complete("\"Prefix: \(unicodeEscape)")
            #expect(completedPrefix == "\"Prefix: \"")
            #expect(isValidJSON(completedPrefix))
        }

        // Test a complete escaped backslash at the end of a partial string
        let escapedBackslash = "\"Escaped backslash: \\\\"
        let completedBackslash = try completer.complete(escapedBackslash)
        #expect(completedBackslash == "\"Escaped backslash: \\\\\"")
        #expect(isValidJSON(completedBackslash))

        let partialObjectEscape = "{\"text\": \"Partial escape: \\"
        let completedObject = try completer.complete(partialObjectEscape)
        #expect(completedObject == "{\"text\": \"Partial escape: \"}")
        #expect(isValidJSON(completedObject))
    }

    @Test("Empty and Whitespace-Only JSON")
    func testEmptyAndWhitespaceJSON() throws {
        let completer = JSONCompleter()

        // Test with empty string
        #expect(try completer.complete("") == "")

        // Test with whitespace only
        #expect(try completer.complete("   ") == "   ")
        #expect(try completer.complete("\n\t\r ") == "\n\t\r ")

        // Test with open brace followed by whitespace
        #expect(try completer.complete("{  ") == "{  }")
        #expect(try completer.complete("[  ") == "[  ]")
    }

    @Test("Partial Number Handling")
    func testPartialNumberHandling() throws {
        let completer = JSONCompleter()

        // Test with partial number literals
        #expect(try completer.complete("123") == "123")
        #expect(try completer.complete("123.") == "123.0")
        #expect(try completer.complete("123.4") == "123.4")
        #expect(try completer.complete("-") == "-0")
        #expect(try completer.complete("-.") == "-0.0")
        #expect(try completer.complete("-123.") == "-123.0")

        // Test with scientific notation
        #expect(try completer.complete("1.23e") == "1.23e0")
        #expect(try completer.complete("1.23e+") == "1.23e+0")
        #expect(try completer.complete("1.23e-") == "1.23e-0")
    }

    @Test("Objects with Missing Values")
    func testObjectsWithMissingValues() throws {
        let completer = JSONCompleter()

        // Test object with key but no value
        #expect(try completer.complete("{\"key\":") == "{\"key\":null}")

        // Test object with key and partial value
        #expect(try completer.complete("{\"key\": \"value") == "{\"key\": \"value\"}")

        // Test object with multiple keys and some missing values
        #expect(
            try completer.complete("{\"key1\": true, \"key2\":")
                == "{\"key1\": true, \"key2\":null}")

        // Test object with trailing comma
        #expect(try completer.complete("{\"key\": 42,") == "{\"key\": 42}")

        // Test complex nested object with missing values
        let complexMissing = "{\"outer\": {\"inner\": [1, 2, {\"nested\":"
        #expect(
            try completer.complete(complexMissing)
                == "{\"outer\": {\"inner\": [1, 2, {\"nested\":null}]}}")
    }

    @Test("Arrays with Missing Values")
    func testArraysWithMissingValues() throws {
        let completer = JSONCompleter()

        // Test array with trailing comma
        #expect(try completer.complete("[1, 2, 3,") == "[1, 2, 3]")

        // Test array with missing value after comma
        #expect(try completer.complete("[1, 2,") == "[1, 2]")

        // Test nested array with missing values
        #expect(try completer.complete("[[1, 2], [3,") == "[[1, 2], [3]]")
    }

    // Helper function to validate JSON using JSONSerialization
    private func isValidJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else {
            return false
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return true
        } catch {
            return false
        }
    }
}
