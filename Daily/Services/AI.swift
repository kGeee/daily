import Foundation
import Security

/// Stores the Anthropic API key in the iPhone's Keychain (never in plain settings).
enum Keychain {
    private static let service = "daily.anthropic"
    private static let account = "apiKey"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String) {
        delete()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasKey: Bool { !(read() ?? "").isEmpty }
}

enum AIError: LocalizedError {
    case noKey
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Anthropic API key in Settings to use this."
        case .server(let message): return message
        case .badResponse: return "Couldn't read the response. Try again."
        }
    }
}

/// Calls the Claude API and forces a structured (tool) answer that decodes into `T`.
enum AIClient {
    static let model = "claude-haiku-4-5-20251001"

    static func structured<T: Decodable>(prompt: String, toolName: String, toolDescription: String,
                                         schema: [String: Any], as type: T.Type) async throws -> T {
        guard let key = Keychain.read(), !key.isEmpty else { throw AIError.noKey }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AIError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "tools": [[
                "name": toolName,
                "description": toolDescription,
                "input_schema": schema
            ] as [String: Any]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw AIError.server(message ?? "The request failed (\(http.statusCode)).")
        }

        guard let content = json?["content"] as? [[String: Any]],
              let toolUse = content.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = toolUse["input"] else { throw AIError.badResponse }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        return try JSONDecoder().decode(T.self, from: inputData)
    }
}

// MARK: - Recipe and nutrition helpers

struct ParsedRecipe: Decodable {
    var name: String
    var servings: Double?
    var ingredients: [String]
    var steps: [String]
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var note: String?
}

struct MacroEstimate: Decodable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var note: String?
}

enum RecipeAI {
    private static let macroProperties: [String: Any] = [
        "calories": ["type": "number", "description": "kcal per serving"],
        "protein": ["type": "number", "description": "grams of protein per serving"],
        "carbs": ["type": "number", "description": "grams of carbohydrate per serving"],
        "fat": ["type": "number", "description": "grams of fat per serving"]
    ]

    /// Pull a full recipe (and per-serving nutrition) out of a caption or pasted text.
    static func parseRecipe(from text: String) async throws -> ParsedRecipe {
        var properties = macroProperties
        properties["name"] = ["type": "string", "description": "Short recipe name"]
        properties["servings"] = ["type": "number", "description": "Number of servings the recipe makes"]
        properties["ingredients"] = ["type": "array", "items": ["type": "string"],
                                     "description": "One ingredient per item with quantity first, e.g. '2 lb chicken thighs'"] as [String: Any]
        properties["steps"] = ["type": "array", "items": ["type": "string"],
                               "description": "Clear cooking steps in order, one action each, with times and temperatures"] as [String: Any]
        properties["note"] = ["type": "string", "description": "Short tip, e.g. 'Reheats well' or 'Best fresh'"]

        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["name", "servings", "ingredients", "steps", "calories", "protein", "carbs", "fat"]
        ]

        let prompt = """
        Below is the text of a recipe post (for example an Instagram reel caption), which may include hashtags, \
        emojis and chatter. Extract the recipe. If quantities or steps are missing, infer reasonable ones from the dish. \
        Estimate nutrition per serving from the ingredients using standard nutrition values. \
        Also say in the note whether it reheats well for meal prep.

        Post text:
        \(text)
        """
        return try await AIClient.structured(prompt: prompt, toolName: "save_recipe",
                                             toolDescription: "Save the extracted recipe",
                                             schema: schema, as: ParsedRecipe.self)
    }

    /// Estimate per-serving nutrition for a recipe you already have.
    static func estimate(recipe name: String, servings: Int, ingredients: [String]) async throws -> MacroEstimate {
        let prompt = """
        Estimate nutrition per serving for this recipe using standard nutrition values.
        Recipe: \(name)
        Makes \(servings) servings.
        Ingredients:
        \(ingredients.joined(separator: "\n"))
        """
        return try await estimate(prompt: prompt)
    }

    /// Estimate nutrition for a meal described in words, e.g. "Chipotle chicken burrito bowl with guac".
    static func estimate(meal description: String) async throws -> MacroEstimate {
        let prompt = """
        Estimate the calories and macros of this meal as typically served (one person's portion). \
        If it names a restaurant, use that restaurant's typical portion.
        Meal: \(description)
        """
        return try await estimate(prompt: prompt)
    }

    private static func estimate(prompt: String) async throws -> MacroEstimate {
        var properties = macroProperties
        properties["note"] = ["type": "string", "description": "One short line on assumptions"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["calories", "protein", "carbs", "fat"]
        ]
        return try await AIClient.structured(prompt: prompt, toolName: "nutrition",
                                             toolDescription: "Report the nutrition estimate",
                                             schema: schema, as: MacroEstimate.self)
    }
}

// MARK: - Instagram

enum InstagramFetcher {
    /// Finds the first link in some text (e.g. a pasted share message).
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    /// Best-effort: reads the post's public caption from the page's preview tags.
    /// Instagram often hides this behind a login, so the caller should fall back to pasted text.
    static func caption(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              let html = String(data: result.0, encoding: .utf8) else { return nil }

        for property in ["og:description", "description", "twitter:description"] {
            if let value = metaContent(in: html, key: property), value.count > 40 {
                return decodeEntities(value)
            }
        }
        return nil
    }

    private static func metaContent(in html: String, key: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "<meta[^>]+(?:property|name)=\"\(escaped)\"[^>]+content=\"([^\"]*)\"",
            "<meta[^>]+content=\"([^\"]*)\"[^>]+(?:property|name)=\"\(escaped)\""
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: html) {
                return String(html[valueRange])
            }
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#10;", with: "\n")
        // Numeric entities like &#x1f525; or &#128293;
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = result as NSString
            var output = ""
            var last = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let isHex = ns.substring(with: match.range(at: 1)) == "x"
                let digits = ns.substring(with: match.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    output.append(Character(scalar))
                }
                last = match.range.location + match.range.length
            }
            output += ns.substring(from: last)
            result = output
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
