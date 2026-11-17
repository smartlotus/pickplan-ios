import Foundation

/// Built-in OpenAI-compatible provider preset matching PickPlan Android presets.
public struct AIProviderPreset: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let baseUrl: String
    public let defaultModel: String
    public let requiresApiKey: Bool

    public init(
        id: String,
        name: String,
        baseUrl: String,
        defaultModel: String,
        requiresApiKey: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.defaultModel = defaultModel
        self.requiresApiKey = requiresApiKey
    }

    public static let presets: [AIProviderPreset] = [
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            baseUrl: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat"
        ),
        AIProviderPreset(
            id: "kimi",
            name: "Kimi (Moonshot)",
            baseUrl: "https://api.moonshot.cn/v1",
            defaultModel: "moonshot-v1-8k"
        ),
        AIProviderPreset(
            id: "qwen",
            name: "Tongyi Qwen",
            baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus"
        ),
        AIProviderPreset(
            id: "glm",
            name: "GLM",
            baseUrl: "https://open.bigmodel.cn/api/paas/v4",
            defaultModel: "glm-4-flash"
        ),
        AIProviderPreset(
            id: "siliconflow",
            name: "SiliconFlow",
            baseUrl: "https://api.siliconflow.cn/v1",
            defaultModel: "Qwen/Qwen2.5-7B-Instruct"
        ),
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            baseUrl: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini"
        ),
        AIProviderPreset(
            id: "custom",
            name: "Custom",
            baseUrl: "",
            defaultModel: "",
            requiresApiKey: false
        )
    ]

    public static func preset(named name: String) -> AIProviderPreset? {
        presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// Errors surfaced by `AIService`.
public enum AIServiceError: Error, LocalizedError, Sendable, Equatable {
    case missingConfiguration(String)
    case invalidURL(String)
    case httpError(statusCode: Int, message: String)
    case emptyResponse
    case invalidResponseFormat(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let detail):
            return detail
        case .invalidURL(let raw):
            return "Invalid AI endpoint URL: \(raw)"
        case .httpError(let statusCode, let message):
            return "AI API error (\(statusCode)): \(message)"
        case .emptyResponse:
            return "AI provider returned an empty response."
        case .invalidResponseFormat(let detail):
            return "Could not parse AI output as todos: \(detail)"
        }
    }
}

/// Async OpenAI-compatible client for parsing natural language into `TodoItem` arrays.
public final class AIService: Sendable {
    private let session: URLSession

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        let error: Detail?
        let message: String?
    }

    private struct TodosWrapper: Decodable {
        let todos: [TodoItem]?
        let tasks: [TodoItem]?
    }

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Sends a minimal ping prompt to verify endpoint, model, and API key validity.
    public func testConnection(settings: AISettingsRecord) async throws -> String {
        let content = try await performChatCompletion(
            systemPrompt: "Reply with OK only.",
            userPrompt: "ping",
            settings: settings,
            temperature: 0.0
        )
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "OK" : trimmed
    }

    /// Extracts one or more structured `TodoItem`s from freeform text using an OpenAI-compatible endpoint.
    public func parseTodosFromText(
        _ input: String,
        settings: AISettingsRecord,
        language: AppLanguage = .zh,
        referenceDate: Date = Date()
    ) async throws -> [TodoItem] {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return [] }

        let nowIso = PickPlanDateCodec.formatISO8601(referenceDate)
        let localDisplay = PickPlanDateCodec.formatDisplayDateTime(referenceDate)
        let tzName = TimeZone.current.identifier

        let systemPrompt = """
        You are PickPlan AI, a precise personal task parser.
        Current UTC time: \(nowIso)
        Current local time: \(localDisplay) (\(tzName))
        Preferred response language for titles/notes: \(language == .zh ? "Chinese (Simplified)" : "English")

        Convert the user's message into a JSON array of todo objects (or {"todos": [...]}).
        Return ONLY valid JSON with no prose outside JSON.
        Each todo object supports keys:
        - "title": string (concise, actionable)
        - "notes": string (optional)
        - "tag": one of "work", "life", "study", "idea", "none"
        - "priority": one of "low", "normal", "high"
        - "reminder_time": ISO8601 string with timezone offset or Z (optional, when scheduled/reminded)
        - "deadline": ISO8601 string with timezone offset or Z (optional, when due by)
        - "subtasks": array of {"title": string, "isCompleted": false} (optional)
        """

        let rawContent = try await performChatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: trimmedInput,
            settings: settings,
            temperature: 0.1
        )

        return try Self.parseAIResponseContent(rawContent, referenceDate: referenceDate)
    }

    /// Extracts JSON array or `{"todos": [...]}` from an LLM response (including fenced ```json blocks).
    public static func parseAIResponseContent(
        _ content: String,
        referenceDate: Date = Date()
    ) throws -> [TodoItem] {
        let cleanedJSON = stripMarkdownCodeFences(from: content)
        guard let data = cleanedJSON.data(using: .utf8), !data.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { nested in
            try PickPlanDateCodec.decodeDate(from: nested)
        }

        if let items = try? decoder.decode([TodoItem].self, from: data) {
            return normalizeParsedItems(items, referenceDate: referenceDate)
        }
        if let wrapper = try? decoder.decode(TodosWrapper.self, from: data) {
            let items = wrapper.todos ?? wrapper.tasks ?? []
            return normalizeParsedItems(items, referenceDate: referenceDate)
        }
        if let single = try? decoder.decode(TodoItem.self, from: data) {
            return normalizeParsedItems([single], referenceDate: referenceDate)
        }

        // Fallback: extract outermost JSON array/object slice if surrounding prose leaked in
        if let extracted = extractJSONSubstring(from: cleanedJSON),
           let sliceData = extracted.data(using: .utf8) {
            if let items = try? decoder.decode([TodoItem].self, from: sliceData) {
                return normalizeParsedItems(items, referenceDate: referenceDate)
            }
            if let wrapper = try? decoder.decode(TodosWrapper.self, from: sliceData) {
                let items = wrapper.todos ?? wrapper.tasks ?? []
                return normalizeParsedItems(items, referenceDate: referenceDate)
            }
        }

        throw AIServiceError.invalidResponseFormat(String(cleanedJSON.prefix(160)))
    }

    // MARK: - Networking & Parsing Internals

    private func performChatCompletion(
        systemPrompt: String,
        userPrompt: String,
        settings: AISettingsRecord,
        temperature: Double
    ) async throws -> String {
        let baseUrlTrimmed = settings.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseUrlTrimmed.isEmpty else {
            throw AIServiceError.missingConfiguration("AI base URL is empty.")
        }

        let modelTrimmed = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelTrimmed.isEmpty else {
            throw AIServiceError.missingConfiguration("AI model name is empty.")
        }

        let apiKeyTrimmed = settings.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requiresKey = AIProviderPreset.preset(named: settings.providerName)?.requiresApiKey ?? false
        if requiresKey && apiKeyTrimmed.isEmpty {
            throw AIServiceError.missingConfiguration("API key is required for \(settings.providerName).")
        }

        let endpointURL = try Self.buildChatCompletionsURL(from: baseUrlTrimmed)
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKeyTrimmed.isEmpty {
            request.setValue("Bearer \(apiKeyTrimmed)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatCompletionRequest(
            model: modelTrimmed,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponseFormat("Non-HTTP response received.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiErr = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))
            let message = apiErr?.error?.message ?? apiErr?.message ?? String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIServiceError.emptyResponse
        }
        return content
    }

    public static func buildChatCompletionsURL(from rawBaseUrl: String) throws -> URL {
        var trimmed = rawBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        let endpointString: String
        if trimmed.hasSuffix("/chat/completions") {
            endpointString = trimmed
        } else {
            endpointString = "\(trimmed)/chat/completions"
        }
        guard let url = URL(string: endpointString), url.scheme != nil, url.host != nil else {
            throw AIServiceError.invalidURL(rawBaseUrl)
        }
        return url
    }

    private static func normalizeParsedItems(_ items: [TodoItem], referenceDate: Date) -> [TodoItem] {
        items.compactMap { item in
            let cleanTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { return nil }
            var normalized = item
            normalized.title = cleanTitle
            normalized.id = UUID().uuidString
            normalized.createdAt = referenceDate
            normalized.updatedAt = referenceDate
            return normalized
        }
    }

    private static func stripMarkdownCodeFences(from raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let closingRange = trimmed.range(of: "```", options: .backwards) {
                trimmed = String(trimmed[..<closingRange.lowerBound])
            }
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONSubstring(from text: String) -> String? {
        let startIdx = text.firstIndex(where: { $0 == "[" || $0 == "{" })
        guard let startIdx else { return nil }
        let closingChar: Character = text[startIdx] == "[" ? "]" : "}"
        guard let endIdx = text.lastIndex(of: closingChar), endIdx >= startIdx else { return nil }
        return String(text[startIdx...endIdx])
    }
}
