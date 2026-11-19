import Foundation

enum VisionProvider: String, CaseIterable, Identifiable, Sendable {
    case gemini, openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openAI: "OpenAI"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: "gemini-2.5-flash"
        case .openAI: "gpt-4o-mini"
        }
    }

    var keychainAccount: String { "apiKey.\(rawValue)" }
}

struct MealAnalysis: Codable, Hashable, Sendable {
    var items: [DetectedFood]
    var notes: String

    private enum CodingKeys: String, CodingKey { case items, notes }

    init(items: [DetectedFood], notes: String = "") {
        self.items = items
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([DetectedFood].self, forKey: .items) ?? []
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }
}

struct DetectedFood: Codable, Hashable, Sendable {
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var confidence: Double

    private enum CodingKeys: String, CodingKey {
        case name
        case grams = "estimated_grams"
        case calories
        case protein = "protein_g"
        case carbs = "carbs_g"
        case fat = "fat_g"
        case confidence
    }

    init(name: String, grams: Double, calories: Double, protein: Double, carbs: Double, fat: Double, confidence: Double) {
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        grams = c.lossyDouble(forKey: .grams) ?? 0
        calories = c.lossyDouble(forKey: .calories) ?? 0
        protein = c.lossyDouble(forKey: .protein) ?? 0
        carbs = c.lossyDouble(forKey: .carbs) ?? 0
        fat = c.lossyDouble(forKey: .fat) ?? 0
        confidence = c.lossyDouble(forKey: .confidence) ?? 0.5
    }

    var nutrients: Nutrients {
        Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

enum VisionError: LocalizedError {
    case missingAPIKey
    case imageEncodingFailed
    case http(status: Int, message: String)
    case emptyResponse
    case blocked(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an API key in Settings › AI Photo Estimates."
        case .imageEncodingFailed: "The photo couldn't be prepared for upload."
        case .http(let status, let message): "AI request failed (\(status)): \(message)"
        case .emptyResponse: "The AI service returned no result. Please try again."
        case .blocked(let reason): "The AI service declined this image (\(reason))."
        case .invalidJSON: "The AI response wasn't in the expected format. Please try again."
        }
    }
}

/// Sends a meal photo to a multimodal model and returns structured nutrition estimates.
///
/// Production note: shipping a provider API key inside an app binary is unsafe. The key is
/// stored in the Keychain and entered by the user; for App Store distribution, point
/// `endpointOverride` at your own backend proxy that holds the key server-side.
struct AIVisionService: Sendable {
    let provider: VisionProvider
    let apiKey: String
    let model: String
    var endpointOverride: URL?
    var session: URLSession = .shared

    func analyzeMeal(jpegData: Data, userHint: String? = nil) async throws -> MealAnalysis {
        guard !apiKey.isEmpty || endpointOverride != nil else { throw VisionError.missingAPIKey }
        guard !jpegData.isEmpty else { throw VisionError.imageEncodingFailed }

        let base64 = jpegData.base64EncodedString()
        var userText = "Analyse this meal photo and return the nutrition estimate."
        if let hint = userHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            userText += " Additional context from the user: \(hint)"
        }

        let raw: String
        switch provider {
        case .gemini: raw = try await requestGemini(base64: base64, userText: userText)
        case .openAI: raw = try await requestOpenAI(base64: base64, userText: userText)
        }
        return try Self.decodeAnalysis(from: raw)
    }

    // MARK: Prompt & schema

    static let instructions = """
    You are a meticulous registered dietitian analysing a photo of a meal.
    Identify every distinct food or drink item that is visible. For each item provide:
    - name: a short, specific description (e.g. "grilled chicken breast", "steamed white rice").
    - estimated_grams: the edible portion weight in grams. Use the plate, cutlery, hands and \
    packaging as scale references.
    - calories, protein_g, carbs_g, fat_g: values for that whole portion, based on standard \
    food-composition data (e.g. USDA FoodData Central). Account for visible oils, sauces and dressings.
    - confidence: 0.0–1.0 for how sure you are about the identification and portion size.
    List the components of mixed dishes separately when they are visually distinguishable.
    Ignore plates, cutlery and inedible packaging. If no food is visible, return an empty items array.
    Put a single-sentence caveat in "notes" (e.g. likely hidden ingredients), or an empty string.
    Respond with JSON only.
    """

    /// JSON schema for the response. Gemini uses an OpenAPI subset with upper-case type names;
    /// OpenAI strict mode requires `additionalProperties: false` and every key in `required`.
    static func responseSchema(for provider: VisionProvider) -> [String: Any] {
        let isGemini = provider == .gemini
        func type(_ name: String) -> String { isGemini ? name.uppercased() : name }
        func object(_ properties: [String: Any], keys: [String]) -> [String: Any] {
            var schema: [String: Any] = ["type": type("object"), "properties": properties, "required": keys]
            if isGemini {
                schema["propertyOrdering"] = keys
            } else {
                schema["additionalProperties"] = false
            }
            return schema
        }

        let string: [String: Any] = ["type": type("string")]
        let number: [String: Any] = ["type": type("number")]
        let itemKeys = ["name", "estimated_grams", "calories", "protein_g", "carbs_g", "fat_g", "confidence"]
        let itemProperties: [String: Any] = [
            "name": string,
            "estimated_grams": number,
            "calories": number,
            "protein_g": number,
            "carbs_g": number,
            "fat_g": number,
            "confidence": number,
        ]
        let items: [String: Any] = ["type": type("array"), "items": object(itemProperties, keys: itemKeys)]
        return object(["items": items, "notes": string], keys: ["items", "notes"])
    }

    // MARK: Gemini

    private func requestGemini(base64: String, userText: String) async throws -> String {
        let endpoint = endpointOverride
            ?? URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        guard let endpoint else { throw VisionError.http(status: -1, message: "Invalid model name") }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key") }

        let textPart: [String: Any] = ["text": userText]
        let imagePart: [String: Any] = ["inlineData": ["mimeType": "image/jpeg", "data": base64]]
        let content: [String: Any] = ["role": "user", "parts": [textPart, imagePart]]
        let generationConfig: [String: Any] = [
            "temperature": 0.2,
            "responseMimeType": "application/json",
            "responseSchema": Self.responseSchema(for: .gemini),
        ]
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": Self.instructions]]],
            "contents": [content],
            "generationConfig": generationConfig,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        if let reason = decoded.promptFeedback?.blockReason { throw VisionError.blocked(reason) }
        let text = decoded.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
        guard !text.isEmpty else { throw VisionError.emptyResponse }
        return text
    }

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    // MARK: OpenAI

    private func requestOpenAI(base64: String, userText: String) async throws -> String {
        let endpoint = endpointOverride ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        let system: [String: Any] = ["role": "system", "content": Self.instructions]
        let textPart: [String: Any] = ["type": "text", "text": userText]
        let imagePart: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(base64)", "detail": "high"],
        ]
        let user: [String: Any] = ["role": "user", "content": [textPart, imagePart]]
        let jsonSchema: [String: Any] = [
            "name": "meal_analysis",
            "strict": true,
            "schema": Self.responseSchema(for: .openAI),
        ]
        let responseFormat: [String: Any] = ["type": "json_schema", "json_schema": jsonSchema]
        let body: [String: Any] = [
            "model": model,
            "messages": [system, user],
            "response_format": responseFormat,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let message = decoded.choices.first?.message else { throw VisionError.emptyResponse }
        if let refusal = message.refusal, !refusal.isEmpty { throw VisionError.blocked(refusal) }
        guard let content = message.content, !content.isEmpty else { throw VisionError.emptyResponse }
        return content
    }

    private struct OpenAIResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    // MARK: Shared

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VisionError.http(status: -1, message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw VisionError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }

    /// Parses the model's JSON text, tolerating stray code fences, and drops unusable items.
    static func decodeAnalysis(from raw: String) throws -> MealAnalysis {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              var analysis = try? JSONDecoder().decode(MealAnalysis.self, from: data) else {
            throw VisionError.invalidJSON
        }
        analysis.items = analysis.items.compactMap { item in
            var item = item
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let clean = item.nutrients.sanitized
            item.calories = clean.calories
            item.protein = clean.protein
            item.carbs = clean.carbs
            item.fat = clean.fat
            item.confidence = min(max(item.confidence, 0), 1)
            guard !item.name.isEmpty, item.grams.isFinite, item.grams > 0 else { return nil }
            return item
        }
        return analysis
    }
}
