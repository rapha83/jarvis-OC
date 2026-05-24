import AVFoundation
import Foundation
import Speech

enum SpeechAnalyzerAssetService {
    static func status(localeID: String) async -> SpeechAnalyzerAssetSummary {
        guard #available(macOS 26.0, *) else {
            return SpeechAnalyzerAssetSummary(isAvailable: false, message: "SpeechAnalyzer requer macOS 26 ou superior")
        }

#if JARVIS_DISABLE_SPEECH_ANALYZER
        return SpeechAnalyzerAssetSummary(isAvailable: false, message: "SpeechAnalyzer desativado nesta build")
#else
        let requestedLocale = Locale(identifier: localeID)
        let equivalentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        let locale = equivalentLocale ?? requestedLocale
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let installed = await SpeechTranscriber.installedLocales.map(\.identifier)
        let supportedCount = await SpeechTranscriber.supportedLocales.count
        let requested = localeID
        let selected = locale.identifier

        if assetStatus == .installed, format != nil {
            return SpeechAnalyzerAssetSummary(
                isAvailable: true,
                message: "SpeechAnalyzer OK para \(selected)"
            )
        }

        switch assetStatus {
        case .unsupported:
            let hint = supportedCount == 0
                ? "Nenhum locale SpeechAnalyzer aparece suportado nesta instalacao."
                : "\(requested) nao aparece suportado pelo SpeechAnalyzer."
            return SpeechAnalyzerAssetSummary(
                isAvailable: false,
                message: "\(hint) Status: unsupported. Instalados: \(installed.isEmpty ? "nenhum" : installed.joined(separator: ", "))"
            )
        case .supported:
            return SpeechAnalyzerAssetSummary(
                isAvailable: false,
                message: "Asset SpeechAnalyzer disponivel para \(selected), mas ainda nao instalado. Clique em Baixar assets."
            )
        case .downloading:
            return SpeechAnalyzerAssetSummary(
                isAvailable: false,
                message: "Asset SpeechAnalyzer para \(selected) esta baixando."
            )
        case .installed:
            return SpeechAnalyzerAssetSummary(
                isAvailable: false,
                message: "Asset SpeechAnalyzer instalado para \(selected), mas ainda sem formato de audio compativel. Reinicie o JARVIS ou tente Verificar assets novamente."
            )
        @unknown default:
            return SpeechAnalyzerAssetSummary(
                isAvailable: false,
                message: "Asset SpeechAnalyzer em status desconhecido para \(selected): \(assetStatus)"
            )
        }
#endif
    }

    static func install(localeID: String) async throws -> SpeechAnalyzerAssetSummary {
        guard #available(macOS 26.0, *) else {
            throw SpeechAnalyzerAssetError.unavailable
        }

#if JARVIS_DISABLE_SPEECH_ANALYZER
        throw SpeechAnalyzerAssetError.unavailable
#else
        let requestedLocale = Locale(identifier: localeID)
        let equivalentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
        let locale = equivalentLocale ?? requestedLocale
        _ = try? await AssetInventory.reserve(locale: locale)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return await status(localeID: localeID)
        }

        try await request.downloadAndInstall()

        var latest = await status(localeID: localeID)
        for _ in 0..<8 where !latest.isAvailable && latest.message.contains("ainda sem formato") {
            try? await Task.sleep(nanoseconds: 500_000_000)
            latest = await status(localeID: localeID)
        }
        return latest
#endif
    }
}

enum SpeechAnalyzerAssetError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechAnalyzer requer macOS 26 ou superior"
        }
    }
}
