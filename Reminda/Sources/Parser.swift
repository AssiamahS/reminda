import Foundation
import FoundationModels

/// Turns "set up lomedico 9am appointment in red bank" into a structured reminder.
/// On-device model first; date-detector fallback when Apple Intelligence is unavailable.
enum ReminderParser {

    @Generable
    struct Parsed {
        @Guide(description: "Short imperative title of the task, without the time or place words")
        var title: String
        @Guide(description: "The time or date mentioned, exactly as spoken (e.g. '9am', 'tomorrow 3pm'), or empty string if none")
        var when: String
        @Guide(description: "The place name mentioned (e.g. 'Red Bank'), or empty string if none")
        var place: String
    }

    static func parse(_ text: String) async -> Reminder {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Reminder(title: "New reminder") }

        if case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions:
                    "Extract reminder parts from spoken text. Keep titles short and natural.")
                let response = try await session.respond(
                    to: "Spoken reminder: \"\(trimmed)\"", generating: Parsed.self)
                let parsed = response.content
                return Reminder(
                    title: parsed.title.isEmpty ? trimmed : parsed.title,
                    due: detectDate(in: parsed.when.isEmpty ? trimmed : parsed.when),
                    place: parsed.place.isEmpty ? nil : parsed.place)
            } catch {
                // fall through to detector
            }
        }
        return fallback(trimmed)
    }

    static func fallback(_ text: String) -> Reminder {
        var title = text
        let due = detectDate(in: text)
        var place: String?
        // "... in Red Bank" / "... at Red Bank"
        for marker in [" in ", " at ", " un "] {
            if let range = text.range(of: marker, options: [.backwards, .caseInsensitive]) {
                let candidate = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && candidate.count < 40 && detectDate(in: candidate) == nil {
                    place = candidate
                    title = String(text[..<range.lowerBound])
                    break
                }
            }
        }
        return Reminder(title: title.isEmpty ? text : title, due: due, place: place)
    }

    static func detectDate(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, range: range), let date = match.date else {
            return nil
        }
        // detector can resolve "9am" to earlier today; push to tomorrow
        if date < .now, let bumped = Calendar.current.date(byAdding: .day, value: 1, to: date) {
            return bumped
        }
        return date
    }
}
