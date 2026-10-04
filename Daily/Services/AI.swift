import Foundation
import Security
import Vision
import CoreGraphics

/// Stores the Anthropic API key in the iPhone's Keychain (never in plain settings).
enum Keychain {
    private static let service = "daily.anthropic"
    static let anthropic = "apiKey"
    static let fiveOneOne = "511Key"

    static func read(_ account: String = anthropic) -> String? {
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

    static func save(_ value: String, account: String = anthropic) {
        delete(account)
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

    static func delete(_ account: String = anthropic) {
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
                                         schema: [String: Any], as type: T.Type,
                                         images: [Data] = [],
                                         maxTokens: Int = 4096) async throws -> T {
        guard let key = Keychain.read(), !key.isEmpty else { throw AIError.noKey }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw AIError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "tools": [[
                "name": toolName,
                "description": toolDescription,
                "input_schema": schema
            ] as [String: Any]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": messageContent(prompt: prompt, images: images)]]
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

    /// Plain text, or JPEG image blocks followed by the text (images first works best).
    static func messageContent(prompt: String, images: [Data]) -> Any {
        guard !images.isEmpty else { return prompt }
        var blocks: [[String: Any]] = images.map { data in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": data.base64EncodedString()]]
        }
        blocks.append(["type": "text", "text": prompt])
        return blocks
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
    var yieldUnit: String?
    var unitsPerMeal: Double?
}

struct MacroEstimate: Decodable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var note: String?
    /// Only asked for when estimating from a photo with no name typed.
    var name: String?
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
        properties["servings"] = ["type": "number",
                                  "description": "How many the recipe makes, counted in yieldUnit (e.g. 30 for '30 nuggets', or 4 servings)"]
        properties["yieldUnit"] = ["type": "string",
                                   "description": "What servings counts: 'servings' normally, or the piece if the recipe makes pieces, e.g. 'nuggets', 'cookies', 'egg bites'"]
        properties["unitsPerMeal"] = ["type": "number",
                                      "description": "How many of yieldUnit one adult eats as a meal (1 for servings, e.g. 6 for nuggets)"]
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
        Estimate nutrition per one unit of the yield from the ingredients using standard nutrition values \
        (per serving, or per piece when the recipe makes pieces like 30 nuggets). \
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

    /// Estimate nutrition for a meal described in words, e.g. "Chipotle chicken burrito bowl with guac",
    /// and/or shown in a photo (a JPEG, already shrunk). `place` is the restaurant, if picked.
    static func estimate(meal description: String, photo: Data? = nil, place: String? = nil) async throws -> MacroEstimate {
        let prompt = mealPrompt(description: description, hasPhoto: photo != nil, place: place)
        return try await estimate(prompt: prompt, images: photo.map { [$0] } ?? [],
                                  wantsName: photo != nil && description.isEmpty)
    }

    static func mealPrompt(description: String, hasPhoto: Bool, place: String?) -> String {
        var lines: [String] = []
        if hasPhoto {
            lines.append("Estimate the calories and macros of the meal in this photo. Identify the foods and judge "
                         + "the portion from the plate, bowl, packaging or hands for scale. Count only what's shown.")
            if !description.isEmpty {
                lines.append("The person describes it as: \(description). Trust their description for what it is "
                             + "and use the photo for how much.")
            }
            if description.isEmpty {
                lines.append("Also give it a short name, e.g. \"Chicken burrito bowl\".")
            }
        } else {
            lines.append("Estimate the calories and macros of this meal as typically served (one person's portion).")
            lines.append("Meal: \(description)")
        }
        if let place, !place.isEmpty {
            lines.append("It's from \(place); use that restaurant's typical recipe and portion if you know it.")
        } else if !hasPhoto {
            lines.append("If it names a restaurant, use that restaurant's typical portion.")
        }
        if hasPhoto {
            lines.append("In the note, say in a few words what you saw and assumed about the portion.")
        }
        return lines.joined(separator: "\n")
    }

    private static func estimate(prompt: String, images: [Data] = [], wantsName: Bool = false) async throws -> MacroEstimate {
        var properties = macroProperties
        properties["note"] = ["type": "string", "description": "One short line on assumptions"]
        if wantsName {
            properties["name"] = ["type": "string", "description": "Short name for the meal"]
        }
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["calories", "protein", "carbs", "fat"]
        ]
        return try await AIClient.structured(prompt: prompt, toolName: "nutrition",
                                             toolDescription: "Report the nutrition estimate",
                                             schema: schema, as: MacroEstimate.self, images: images)
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

    /// Best-effort caption lookup: first the public embed page (full caption),
    /// then the post page's preview tags (often shortened). Returns nil if Instagram blocks both.
    static func caption(for url: URL) async -> String? {
        if let code = shortcode(in: url), let embedded = await embedCaption(code: code) {
            return embedded
        }
        return await previewCaption(for: url)
    }

    /// The post ID in links like instagram.com/reel/ABC123/ or /p/ABC123/.
    static func shortcode(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let index = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }),
              index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    private static func embedCaption(code: String) async -> String? {
        guard let url = URL(string: "https://www.instagram.com/p/\(code)/embed/captioned/"),
              let html = await fetch(url) else { return nil }
        let patterns = [
            "class=\"Caption\"[^>]*>([\\s\\S]*?)<div class=\"CaptionComments",
            "class=\"Caption\"[^>]*>([\\s\\S]*?)</div>"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: range),
                  let inner = Range(match.range(at: 1), in: html) else { continue }
            let text = plainText(fromHTML: String(html[inner]))
            if text.count > 30 { return text }
        }
        return nil
    }

    private static func plainText(fromHTML html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
        if let tags = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = tags.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        return decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fetch(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        return String(data: result.0, encoding: .utf8)
    }

    private static func previewCaption(for url: URL) async -> String? {
        guard let html = await fetch(url) else { return nil }

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

// MARK: - Reading text from screenshots (on device)

enum ScreenshotText {
    /// Reads all the text in an image with Apple's on-device text recognition.
    static func recognize(in image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}
