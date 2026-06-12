import Foundation

enum JSONLine {
    static func object(from line: String) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func dictionary(_ object: [String: Any], at path: [String]) -> [String: Any]? {
        value(object, at: path) as? [String: Any]
    }

    static func string(_ object: [String: Any], at path: [String]) -> String? {
        if let value = value(object, at: path) as? String {
            return value
        }
        return nil
    }

    static func int(_ object: [String: Any], at path: [String]) -> Int? {
        guard let raw = value(object, at: path) else {
            return nil
        }
        if let int = raw as? Int {
            return int
        }
        if let double = raw as? Double {
            return Int(double)
        }
        if let string = raw as? String {
            return Int(string)
        }
        return nil
    }

    static func date(_ object: [String: Any], at path: [String]) -> Date? {
        guard let raw = string(object, at: path) else {
            return nil
        }
        return DateParsers.iso8601.date(from: raw) ?? DateParsers.iso8601NoFraction.date(from: raw)
    }

    private static func value(_ object: [String: Any], at path: [String]) -> Any? {
        var cursor: Any = object
        for key in path {
            guard let dictionary = cursor as? [String: Any], let next = dictionary[key] else {
                return nil
            }
            cursor = next
        }
        return cursor
    }
}

enum DateParsers {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

