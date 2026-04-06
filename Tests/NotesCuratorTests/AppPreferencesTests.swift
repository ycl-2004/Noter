import Foundation
import Testing
@testable import NotesCurator

struct AppPreferencesTests {
    @Test
    func legacyCustomAPIKeyMigratesIntoSelectedHostedServiceBucket() throws {
        let legacyJSON = """
        {
          "hostedService": "gemini",
          "providerKind": "customAPI",
          "modelName": "gemini-2.5-flash",
          "defaultOutputLanguage": "english",
          "defaultExportFormat": "pdf",
          "autoSave": true,
          "customBaseURL": "https://generativelanguage.googleapis.com",
          "customAPIKey": "legacy-gemini-key",
          "enableWorkflowRouting": true,
          "customChunkModelName": "gemini-2.5-flash-lite",
          "customPolishModelName": "gemini-2.5-pro",
          "customRepairModelName": "gemini-2.5-flash"
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: legacyJSON)

        #expect(preferences.hostedAPIKeysByService[HostedService.gemini.rawValue] == "legacy-gemini-key")
        #expect(preferences.resolvedAPIKey() == "legacy-gemini-key")
    }

    @Test
    func switchingHostedServiceUsesThatServicesSavedAPIKey() {
        var preferences = AppPreferences(
            providerKind: .customAPI,
            hostedService: .nvidia,
            modelName: HostedService.nvidia.recommendedMainModel,
            defaultOutputLanguage: .english,
            defaultExportFormat: .pdf,
            autoSave: true,
            customBaseURL: HostedService.nvidia.defaultBaseURL,
            customAPIKey: "",
            hostedAPIKeysByService: [
                HostedService.nvidia.rawValue: "nvidia-key",
                HostedService.gemini.rawValue: "gemini-key",
            ],
            enableWorkflowRouting: true
        )

        preferences.syncSelectedHostedServiceAPIKey()
        #expect(preferences.customAPIKey == "nvidia-key")

        preferences.hostedService = .gemini
        preferences.syncSelectedHostedServiceAPIKey()

        #expect(preferences.customAPIKey == "gemini-key")
        #expect(preferences.resolvedAPIKey() == "gemini-key")
    }
}
