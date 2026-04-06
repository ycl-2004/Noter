import Foundation

enum NotesCuratorBootstrap {
    @MainActor
    static func makeModel() -> NotesCuratorAppModel {
        let repository: CuratorRepository
        do {
            let supportDirectory = try applicationSupportDirectory()
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let dbURL = supportDirectory.appendingPathComponent("notes-curator.sqlite")
            repository = try SQLiteCuratorRepository(databaseURL: dbURL)
        } catch {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("notes-curator.sqlite")
            repository = (try? SQLiteCuratorRepository(databaseURL: fallbackURL)) ?? {
                fatalError("Unable to create repository: \(error.localizedDescription)")
            }()
        }

        let builder: (AppPreferences) -> DocumentProcessingPipeline = { preferences in
            DocumentProcessingPipeline(
                parser: LocalIntakeParser(),
                primaryProvider: provider(for: preferences),
                fallbackProvider: HeuristicCurationProvider(),
                chunkProvider: chunkProvider(for: preferences),
                polishProvider: polishProvider(for: preferences),
                repairProvider: repairProvider(for: preferences)
            )
        }

        return NotesCuratorAppModel(
            repository: repository,
            pipeline: builder(.default),
            pipelineBuilder: builder
        )
    }

    private static func provider(for preferences: AppPreferences) -> ProviderAdapter {
        switch preferences.providerKind {
        case .localOllama:
            return LocalOllamaProvider(modelName: preferences.modelName)
        case .customAPI:
            return customAPIProvider(for: preferences, modelName: preferences.modelName)
        case .heuristicFallback:
            return HeuristicCurationProvider()
        }
    }

    private static func chunkProvider(for preferences: AppPreferences) -> ProviderAdapter? {
        guard preferences.providerKind == .customAPI, preferences.enableWorkflowRouting else { return nil }
        return customAPIProvider(for: preferences, modelName: preferences.customChunkModelName)
    }

    private static func repairProvider(for preferences: AppPreferences) -> ProviderAdapter? {
        guard preferences.providerKind == .customAPI, preferences.enableWorkflowRouting else { return nil }
        return customAPIProvider(for: preferences, modelName: preferences.customRepairModelName)
    }

    private static func polishProvider(for preferences: AppPreferences) -> ProviderAdapter? {
        guard preferences.providerKind == .customAPI, preferences.enableWorkflowRouting else { return nil }
        return customAPIProvider(for: preferences, modelName: preferences.customPolishModelName)
    }

    private static func customAPIProvider(for preferences: AppPreferences, modelName: String) -> ProviderAdapter {
        let baseURL = URL(string: preferences.customBaseURL) ?? URL(string: preferences.hostedService.defaultBaseURL)!
        let apiKey = preferences.resolvedAPIKey()

        switch preferences.hostedService {
        case .nvidia, .openAI, .zhipu, .mistral:
            return OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey, modelName: modelName)
        case .anthropic:
            return AnthropicProvider(baseURL: baseURL, apiKey: apiKey, modelName: modelName)
        case .gemini:
            return GeminiProvider(baseURL: baseURL, apiKey: apiKey, modelName: modelName)
        }
    }

    private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("NotesCurator", isDirectory: true)
    }
}
