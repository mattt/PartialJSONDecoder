import Foundation

/// Errors that can occur during JSON completion
public enum JSONCompletionError: Error, LocalizedError {
    case invalidValue(String)
    case depthLimitExceeded(String)

    public var errorDescription: String? {
        switch self {
        case .invalidValue(let message):
            return message
        case .depthLimitExceeded(let message):
            return message
        }
    }
}

/// An object that completes partial JSON strings by adding missing closing characters.
public class JSONCompleter {
    public typealias NonConformingFloatDecodingStrategy = JSONDecoder
        .NonConformingFloatDecodingStrategy

    /// Strategy for handling non-conforming number values like NaN and Infinity.
    /// By default, an error will be thrown if a non-conforming number value is encountered.
    public var nonConformingFloatStrategy: NonConformingFloatDecodingStrategy = .throw

    /// Maximum depth for nested JSON structures to prevent stack overflow from deeply nested inputs.
    /// By default, the maximum depth is 64, which is sufficient for most legitimate JSON.
    ///
    /// - Important: This helps mitigate [CWE-674: Uncontrolled Recursion](https://cwe.mitre.org/data/definitions/674.html)
    ///   by limiting the maximum nesting depth of JSON structures that can be processed.
    public var maximumDepth: Int = 64

    /// Represents a completion result for partial JSON
    /// `string`: The string needed to complete the JSON segment (e.g., `"`, `]`, `}`). Nil if the segment is already complete.
    /// `endIndex`: The index in the original string immediately following the parsed JSON segment (complete or incomplete).
    public typealias Completion = (string: String, endIndex: String.Index)

    /// Creates a new JSON completer with the default settings.
    public init() {}

    /// Completes a partial JSON string by adding any missing closing characters
    /// - Parameter json: The partial JSON string to complete
    /// - Returns: A valid JSON string with all necessary closing characters added
    /// - Throws: An error if an unsupported special numeric value is encountered with `.throw` strategy
    public func complete(_ json: String) throws -> String {
        guard !json.isEmpty else { return "" }

        if let completion = try completion(for: json, from: json.startIndex) {
            return json[..<completion.endIndex] + completion.string
        }

        // If nil, the JSON was already complete
        return json
    }

    /// Returns completion information for partial JSON
    /// - Parameters:
    ///   - json: The JSON string to analyze
    ///   - startIndex: The index to start analyzing from
    /// - Returns: A completion tuple containing the completion string and the end index,
    ///   or nil if the JSON is already complete
    /// - Throws: An error if an unsupported special numeric value is encountered with `.throw` strategy
    public func completion(for json: String, from startIndex: String.Index) throws -> Completion? {
        let start = skipWhitespace(json, from: startIndex)
        guard start < json.endIndex else {
            // Reached end of string after skipping whitespace, nothing to complete from here
            return nil
        }

        return try completeValue(json, from: start, depth: 0)
    }

    // MARK: - Private Methods

    private func skipWhitespace(_ json: String, from index: String.Index) -> String.Index {
        var current = index
        while current < json.endIndex && json[current].isWhitespace {
            current = json.index(after: current)
        }
        return current
    }

    /// Parses a JSON value and returns completion info if needed
    private func completeValue(_ json: String, from startIndex: String.Index, depth: Int = 0) throws
        -> Completion?
    {
        guard depth < maximumDepth else {
            throw JSONCompletionError.depthLimitExceeded(
                "JSON nesting depth exceeds limit of \(maximumDepth)")
        }

        let start = skipWhitespace(json, from: startIndex)
        guard start < json.endIndex else {
            return nil
        }

        let char = json[start]
        switch char {
        case "{":
            return try completeObject(json, from: start, depth: depth + 1)
        case "[":
            return try completeArray(json, from: start, depth: depth + 1)
        case "\"":
            return completeString(json, from: start)
        case "-":
            if let next = json.indices.contains(json.index(after: start))
                ? json[json.index(after: start)] : nil,
                next == "I"
            {
                if case .throw = nonConformingFloatStrategy {
                    throw JSONCompletionError.invalidValue("Invalid numeric value: -Infinity")
                }
                return completeSpecialValue(json, from: start, value: "-Infinity")
            }
            return completeNumber(json, from: start)
        case "0"..."9": return completeNumber(json, from: start)
        case "t":
            return completeSpecialValue(json, from: start, value: "true")
        case "f":
            return completeSpecialValue(json, from: start, value: "false")
        case "n":
            return completeSpecialValue(json, from: start, value: "null")
        case "I":
            if case .throw = nonConformingFloatStrategy {
                throw JSONCompletionError.invalidValue("Invalid numeric value: Infinity")
            }
            return completeSpecialValue(json, from: start, value: "Infinity")
        case "N":
            if case .throw = nonConformingFloatStrategy {
                throw JSONCompletionError.invalidValue("Invalid numeric value: NaN")
            }
            return completeSpecialValue(json, from: start, value: "NaN")
        default:
            // Found an invalid starting character for a JSON value
            return nil
        }
    }

    private func completeString(_ json: String, from startIndex: String.Index) -> Completion? {
        guard startIndex < json.endIndex, json[startIndex] == "\"" else {
            return nil
        }

        var current = json.index(after: startIndex)
        var isEscaped = false

        while current < json.endIndex {
            let char = json[current]
            if char == "\\" {
                isEscaped.toggle()
            } else if char == "\"" && !isEscaped {
                // Found the closing quote, string is complete
                return nil
            } else {
                isEscaped = false
            }
            current = json.index(after: current)
        }

        // Reached end of string without finding a closing quote
        return (string: "\"", endIndex: current)
    }

    private func completeArray(_ json: String, from startIndex: String.Index, depth: Int) throws
        -> Completion?
    {
        guard startIndex < json.endIndex, json[startIndex] == "[" else { return nil }

        var current = json.index(after: startIndex)
        var requiresComma = false  // Track if a comma is expected before the next element
        var lastValidIndex = current  // Track the position after the last successfully parsed element/comma

        // Skip initial whitespace
        current = skipWhitespace(json, from: current)

        // If we've reached the end or only have whitespace, close the array
        if current >= json.endIndex {
            return (string: "]", endIndex: current)
        }

        // The existing closing bracket completes an empty array.
        if json[current] == "]" {
            return nil
        }

        while current < json.endIndex {
            current = skipWhitespace(json, from: current)
            if current >= json.endIndex { break }

            // Check for closing bracket
            if json[current] == "]" {
                // Found closing bracket, array is complete
                return nil
            }

            // If a comma is required but not found (and it's not the closing bracket)
            if requiresComma {
                if json[current] == "," {
                    requiresComma = false
                    current = json.index(after: current)
                    current = skipWhitespace(json, from: current)  // Skip whitespace after comma
                    if current >= json.endIndex { break }  // Reached end after comma
                    lastValidIndex = current
                } else {
                    // Expected comma or closing bracket, found something else.
                    // Consider this array incomplete, needing a closing bracket at the current position.
                    return (string: "]", endIndex: lastValidIndex)
                }
            }

            if current >= json.endIndex { break }  // Reached end before finding element or closing bracket

            // Handle empty array case or first element after `[`
            if json[current] == "]" {
                return nil
            }

            // Parse the element
            if let elementCompletion = try completeValue(json, from: current, depth: depth + 1) {
                // Element is incomplete
                return (
                    string: elementCompletion.string + "]", endIndex: elementCompletion.endIndex
                )
            } else {
                // Element is complete, move past it
                let endOfValue = findEndOfCompleteValue(json, from: current)
                current = endOfValue
                lastValidIndex = current
                requiresComma = true  // Expect a comma after a complete element
            }
        }

        // Reached end of string, incomplete array
        return (string: "]", endIndex: lastValidIndex)
    }

    private func completeObject(_ json: String, from startIndex: String.Index, depth: Int) throws
        -> Completion?
    {
        guard startIndex < json.endIndex, json[startIndex] == "{" else { return nil }

        var current = json.index(after: startIndex)
        var requiresComma = false  // Track if a comma is expected before the next key-value pair
        var lastValidIndex = current  // Track the position after the last successfully parsed element/comma

        // Skip initial whitespace
        current = skipWhitespace(json, from: current)

        // If we've reached the end or only have whitespace, close the object
        if current >= json.endIndex {
            return (string: "}", endIndex: current)
        }

        // The existing closing brace completes an empty object.
        if json[current] == "}" {
            return nil
        }

        while current < json.endIndex {
            current = skipWhitespace(json, from: current)
            if current >= json.endIndex { break }

            // Check for closing brace
            if json[current] == "}" {
                // Found closing brace, object is complete
                return nil
            }

            // If a comma is required but not found (and it's not the closing brace)
            if requiresComma {
                if json[current] == "," {
                    requiresComma = false
                    current = json.index(after: current)
                    current = skipWhitespace(json, from: current)  // Skip whitespace after comma
                    if current >= json.endIndex { break }  // Reached end after comma
                    lastValidIndex = current
                } else {
                    // Expected comma or closing brace, found something else.
                    // Consider this object incomplete, needing a closing brace at the current position.
                    return (string: "}", endIndex: lastValidIndex)
                }
            }

            if current >= json.endIndex { break }  // Reached end before finding key or closing brace

            // Handle empty object case or first key after `{`
            if json[current] == "}" {
                return nil
            }

            // --- Parse Key ---
            if let keyCompletion = completeString(json, from: current) {
                // Key is incomplete, assume null value and close object
                // We need to add the closing quote for the key, the colon, a value (e.g., null), and the closing brace.
                // The keyCompletion.string contains the needed closing quote.
                let missingValue = ": null"
                return (
                    string: keyCompletion.string + missingValue + "}",
                    endIndex: keyCompletion.endIndex
                )
            } else {
                // Key is complete, find its end
                let keyEnd = findEndOfCompleteValue(json, from: current)
                if keyEnd <= current {
                    // Could not find end of supposedly complete key string, or it was empty.
                    return (string: "}", endIndex: lastValidIndex)  // Give up and close object
                }
                current = keyEnd
                lastValidIndex = current
            }

            // --- Parse Colon ---
            current = skipWhitespace(json, from: current)
            if current >= json.endIndex || json[current] != ":" {
                // Missing colon after key
                return (string: ": null}", endIndex: lastValidIndex)
            }
            current = json.index(after: current)  // Move past colon
            lastValidIndex = current

            // --- Parse Value ---
            current = skipWhitespace(json, from: current)
            if current >= json.endIndex {
                // Reached end after colon, value is missing
                return (string: "null}", endIndex: lastValidIndex)
            }

            if let valueCompletion = try completeValue(json, from: current, depth: depth + 1) {
                // Value is incomplete
                return (string: valueCompletion.string + "}", endIndex: valueCompletion.endIndex)
            } else {
                // Value is complete, move past it
                let endOfValue = findEndOfCompleteValue(json, from: current)
                current = endOfValue
                lastValidIndex = current
                requiresComma = true  // Expect a comma after a complete key-value pair
            }
        }

        // Reached end of string, incomplete object
        return (string: "}", endIndex: lastValidIndex)
    }

    private func completeNumber(_ json: String, from startIndex: String.Index) -> Completion? {
        var current = startIndex
        var hasSeenDecimal = false
        var hasSeenExponent = false

        // Optional leading minus sign
        if current < json.endIndex && json[current] == "-" {
            current = json.index(after: current)
        }

        let initialCurrent = current  // Keep track of start after potential minus

        // If we only have a minus sign, we need to add "0"
        if current >= json.endIndex {
            return (string: "0", endIndex: current)
        }

        // If we have a minus sign followed by a decimal point, we need to add "0.0"
        if json[current] == "." {
            return (string: "0.0", endIndex: current)
        }

        // Digits (integer part or part before decimal)
        while current < json.endIndex && json[current].isNumber {
            current = json.index(after: current)
        }

        // Optional decimal part
        if current < json.endIndex && json[current] == "." {
            hasSeenDecimal = true
            current = json.index(after: current)
            // Digits after decimal
            let startFraction = current
            while current < json.endIndex && json[current].isNumber {
                current = json.index(after: current)
            }
            // If we have a decimal point but no digits after it, we need to add "0"
            if current == startFraction {
                return (string: "0", endIndex: current)
            }
        }

        // Optional exponent part
        if current < json.endIndex && (json[current] == "e" || json[current] == "E") {
            hasSeenExponent = true
            current = json.index(after: current)
            // Optional sign for exponent
            if current < json.endIndex && (json[current] == "+" || json[current] == "-") {
                current = json.index(after: current)
            }
            // If we have an exponent but no digits after it (or after the sign), we need to add "0"
            if current >= json.endIndex || !json[current].isNumber {
                return (string: "0", endIndex: current)
            }
            // Digits for exponent
            while current < json.endIndex && json[current].isNumber {
                current = json.index(after: current)
            }
        }

        // Check if any number part was actually found after the optional minus sign
        if current == initialCurrent && !(hasSeenDecimal || hasSeenExponent) {
            // Only found a '-' or nothing valid
            return nil
        }
        if current == json.index(after: initialCurrent) && json[initialCurrent] == "." {
            // Started with "-." and no digits after '.'
            return nil
        }

        // Number is complete
        return nil
    }

    private func completeSpecialValue(
        _ json: String, from startIndex: String.Index, value: String
    ) -> Completion? {
        var current = startIndex
        let valueChars = Array(value)
        var i = 0

        // Try to match the value
        while current < json.endIndex && i < valueChars.count {
            if json[current] != valueChars[i] {
                // Mismatch before completing the special value
                return nil
            }
            current = json.index(after: current)
            i += 1
        }

        if i == valueChars.count {
            // Complete match
            return nil
        }

        // Check if it's a prefix of the value
        let prefix = String(json[startIndex..<current])
        if value.hasPrefix(prefix) {
            // Reached end of input while matching a prefix
            return (string: String(valueChars[i...]), endIndex: current)
        }

        // It started matching but deviated - handled by mismatch check inside loop
        return nil
    }

    /// Finds the index immediately after a complete JSON value (string, number, object, array, bool, null).
    private func findEndOfCompleteValue(
        _ json: String, from startIndex: String.Index, lookingFor: Character? = nil
    ) -> String.Index {
        let start = skipWhitespace(json, from: startIndex)
        guard start < json.endIndex else { return start }

        // Try to parse the value
        if let result = try? completeValue(json, from: start, depth: 0) {
            // Value is incomplete, use its endIndex
            return result.endIndex
        }

        // Value is complete, need to find its end index
        let firstChar = json[start]

        switch firstChar {
        case "\"":  // String
            var current = json.index(after: start)
            var isEscaped = false
            while current < json.endIndex {
                let char = json[current]
                if char == "\\" {
                    isEscaped.toggle()
                } else if char == "\"" && !isEscaped {
                    return json.index(after: current)
                } else {
                    isEscaped = false
                }
                current = json.index(after: current)
            }
            return current  // Shouldn't reach here for complete strings
        case "{":  // Object
            return findMatchingBrace(json, from: start, open: "{", close: "}")
        case "[":  // Array
            return findMatchingBrace(json, from: start, open: "[", close: "]")
        case "t":  // true
            if json[start...].hasPrefix("true") {
                return json.index(start, offsetBy: 4)
            }
        case "f":  // false
            if json[start...].hasPrefix("false") {
                return json.index(start, offsetBy: 5)
            }
        case "n":  // null
            if json[start...].hasPrefix("null") {
                return json.index(start, offsetBy: 4)
            }
        case "-", "0"..."9":  // Number
            var current = start
            while current < json.endIndex && "1234567890.-+eE".contains(json[current]) {
                current = json.index(after: current)
            }
            return current
        case "I":  // Infinity
            if json[start...].hasPrefix("Infinity") {
                return json.index(start, offsetBy: 8)
            }
        case "N":  // NaN
            if json[start...].hasPrefix("NaN") {
                return json.index(start, offsetBy: 3)
            }
        default:
            break
        }

        // Default case - couldn't find end index
        return start
    }

    /// Helper to find the matching closing brace/bracket, skipping nested ones and strings.
    private func findMatchingBrace(
        _ json: String, from startIndex: String.Index, open: Character, close: Character
    ) -> String.Index {
        var level = 0
        var current = startIndex
        var inString = false
        var isEscaped = false

        while current < json.endIndex {
            let char = json[current]

            if inString {
                if char == "\\" {
                    isEscaped.toggle()
                } else if char == "\"" && !isEscaped {
                    inString = false
                } else {
                    isEscaped = false
                }
            } else {
                if char == "\"" {
                    inString = true
                    isEscaped = false
                } else if char == open {
                    level += 1
                } else if char == close {
                    level -= 1
                    if level == 0 {
                        return json.index(after: current)
                    }
                }
            }
            current = json.index(after: current)
        }
        return current  // No matching brace found
    }
}
