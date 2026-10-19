// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Things Notchy can find out by itself before it answers, so it is not blind: what time it is, and the weather. They are decided
/// by plain rules on the words of the question (no AI call to decide), they use free services that need no key, and only what is
/// needed leaves the Mac: the name of a place, to Open-Meteo. The result is a few lines added to the question.
enum NotchyTools {
    private static let weatherWords = ["meteo", "weather", "forecast", "previsioni", "piove", "pioggia", "rain", "temperatura", "temperature",
                                       "che tempo", "com'è il tempo", "com'e il tempo", "how's the weather", "fa caldo", "fa freddo",
                                       "nuvol", "sole", "soleggiato", "neve", "snow", "vento", "wind", "ombrello", "umbrella", "gradi", "degrees"]

    static func asksAboutWeather(_ text: String) -> Bool {
        let t = text.lowercased()
        return weatherWords.contains { t.contains($0) }
    }

    /// Lines to add to a question: always the date and time, plus the weather when the question is about it
    static func context(for text: String) async -> String {
        let now = Date()
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        f.locale = Locale(identifier: "en_US")
        var lines = ["Now: \(f.string(from: now)) (\(TimeZone.current.identifier))."]
        if asksAboutWeather(text) { lines.append(await weather(for: text)) }
        return lines.joined(separator: "\n")
    }

    // MARK: Weather (Open-Meteo: free, no key)

    private static func weather(for text: String) async -> String {
        let place = placeName(in: text) ?? NotchySettings.shared.homeCity.trimmingCharacters(in: .whitespaces)
        guard !place.isEmpty else {
            return "Weather: the user did not say where and has no city set. Ask for a place, or tell them they can set their city in Settings → Notchy → Day & email."
        }
        do {
            guard let spot = try await geocode(place) else { return "Weather: no place called \"\(place)\" was found." }
            let report = try await forecast(spot)
            return "Weather for \(spot.name)\(spot.region.isEmpty ? "" : ", \(spot.region)") (from Open-Meteo):\n\(report)"
        } catch {
            return "Weather: could not be fetched right now (\(error.localizedDescription))."
        }
    }

    /// "che tempo fa a Palo del Colle domani" → "Palo del Colle". Looks for a place after a preposition, stopping at time words.
    static func placeName(in text: String) -> String? {
        let stops = ["oggi", "domani", "dopodomani", "stasera", "stanotte", "stamattina", "adesso", "ora", "today", "tomorrow", "tonight", "now", "this", "next", "questa", "settimana", "week"]
        let cleaned = text.replacingOccurrences(of: "[?!.,;:]", with: " ", options: .regularExpression)
        let words = cleaned.split(separator: " ").map(String.init)
        let prepositions: Set<String> = ["a", "ad", "in", "at", "for", "di", "per", "nel", "nella", "su", "near", "vicino"]
        // The last preposition that is followed by something that is not a time word
        for i in stride(from: words.count - 2, through: 0, by: -1) where prepositions.contains(words[i].lowercased()) {
            var name: [String] = []
            for w in words[(i + 1)...] {
                if stops.contains(w.lowercased()) { break }
                name.append(w)
            }
            let place = name.joined(separator: " ")
            if !place.isEmpty, !["me", "casa", "home", "qui", "here", "my", "mio"].contains(place.lowercased()) { return place }
        }
        return nil
    }

    private struct Spot { let name: String; let region: String; let lat: Double; let lon: Double }

    private static func geocode(_ place: String) async throws -> Spot? {
        // The name as said, then without its last word (a stray "domani" or "adesso" would make it fail)
        var candidates = [place]
        let parts = place.split(separator: " ")
        if parts.count > 1 { candidates.append(parts.dropLast().joined(separator: " ")) }
        for name in candidates {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1"),
                            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en")]
            let (data, _) = try await URLSession.shared.data(from: c.url!)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let r = (json["results"] as? [[String: Any]])?.first,
               let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double {
                return Spot(name: r["name"] as? String ?? name, region: (r["admin1"] as? String) ?? (r["country"] as? String) ?? "", lat: lat, lon: lon)
            }
        }
        return nil
    }

    private static func forecast(_ s: Spot) async throws -> String {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(s.lat)), URLQueryItem(name: "longitude", value: String(s.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "3"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "no data" }
        var lines: [String] = []
        if let cur = json["current"] as? [String: Any] {
            let t = (cur["temperature_2m"] as? Double).map { String(format: "%.0f°C", $0) } ?? "?"
            let feels = (cur["apparent_temperature"] as? Double).map { String(format: "%.0f°C", $0) } ?? "?"
            let wind = (cur["wind_speed_10m"] as? Double).map { String(format: "%.0f km/h", $0) } ?? "?"
            lines.append("Now: \(describe(cur["weather_code"] as? Int)), \(t) (feels \(feels)), wind \(wind).")
        }
        if let d = json["daily"] as? [String: Any], let days = d["time"] as? [String] {
            let codes = d["weather_code"] as? [Int] ?? [], hi = d["temperature_2m_max"] as? [Double] ?? [], lo = d["temperature_2m_min"] as? [Double] ?? []
            let rain = d["precipitation_probability_max"] as? [Int] ?? []
            for (i, day) in days.enumerated() where i < 3 {
                let label = ["Today", "Tomorrow", "Day after tomorrow"][i]
                lines.append("\(label) (\(day)): \(describe(i < codes.count ? codes[i] : nil)), \(i < lo.count ? String(format: "%.0f", lo[i]) : "?")–\(i < hi.count ? String(format: "%.0f", hi[i]) : "?")°C, rain chance \(i < rain.count ? "\(rain[i])%" : "?").")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// WMO weather codes in a few words
    private static func describe(_ code: Int?) -> String {
        switch code ?? -1 {
        case 0: return "clear sky"
        case 1: return "mostly clear"
        case 2: return "partly cloudy"
        case 3: return "overcast"
        case 45, 48: return "fog"
        case 51...57: return "drizzle"
        case 61...65: return "rain"
        case 66, 67: return "freezing rain"
        case 71...77: return "snow"
        case 80...82: return "rain showers"
        case 85, 86: return "snow showers"
        case 95...99: return "thunderstorm"
        default: return "unknown"
        }
    }
}
