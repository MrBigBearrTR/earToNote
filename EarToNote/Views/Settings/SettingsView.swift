import SwiftData
import SwiftUI

private enum ModelDownload {
    case speech
    case diarization

    var title: String {
        switch self {
        case .speech: "Konuşma tanıma modeli indiriliyor"
        case .diarization: "Konuşmacı ayrıştırma modeli indiriliyor"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AppSettings.localeKey) private var localeIdentifier = AppSettings.defaultLocaleIdentifier
    @AppStorage(AppSettings.matchThresholdKey) private var matchThreshold = AppSettings.defaultMatchThreshold

    @State private var speechModelStatus: SpeechModelStatus?
    @State private var diarizationReady = DiarizationService.modelsWereDownloaded
    @State private var download: ModelDownload?
    @State private var speechDownloadProgress = 0.0
    @State private var errorMessage: String?
    @State private var meetingCount = 0
    @State private var profileCount = 0
    @State private var recordingsSize: Int64 = 0

    var body: some View {
        Form {
            languageSection
            recognitionSection
            modelsSection
            storageSection
            privacySection
        }
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") {
                    dismiss()
                }
            }
        }
        .task(id: localeIdentifier) {
            await refreshSpeechModelStatus()
        }
        .task {
            refreshStorage()
        }
        .alert("İndirme başarısız", isPresented: hasError) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Toplantı dili", selection: $localeIdentifier) {
                ForEach(AppSettings.languages) { language in
                    Text(language.name).tag(language.id)
                }
            }
        } header: {
            Text("Yazıya Dökme")
        } footer: {
            Text("Yeni kayıtlar bu dilde yazıya dökülür. Mevcut toplantılar kaydedildikleri dili korur.")
        }
    }

    private var recognitionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Eşleşme hassasiyeti") {
                    Text(matchThreshold, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $matchThreshold, in: AppSettings.matchThresholdRange, step: 0.01) {
                    Text("Eşleşme hassasiyeti")
                } minimumValueLabel: {
                    Text("Esnek")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("Katı")
                        .font(.caption)
                }
            }
            if abs(matchThreshold - AppSettings.defaultMatchThreshold) > 0.001 {
                Button("Varsayılana Dön") {
                    matchThreshold = AppSettings.defaultMatchThreshold
                }
            }
        } header: {
            Text("Konuşmacı Tanıma")
        } footer: {
            Text("Farklı kişiler aynı isimle eşleşiyorsa değeri artırın. Aynı kişi her toplantıda yeni bir \"Konuşmacı\" olarak geliyorsa azaltın.")
        }
    }

    private var modelsSection: some View {
        Section {
            LabeledContent("Konuşma tanıma modeli") {
                speechModelStatusText
            }
            LabeledContent("Konuşmacı ayrıştırma modeli") {
                Text(diarizationReady ? "Hazır" : "İndirilmedi")
                    .foregroundStyle(diarizationReady ? .green : .secondary)
            }
            if let download {
                VStack(alignment: .leading, spacing: 6) {
                    Text(download.title)
                        .font(.subheadline)
                    switch download {
                    case .speech:
                        ProgressView(value: speechDownloadProgress)
                    case .diarization:
                        // FluidAudio does not report download progress.
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if needsDownload {
                Button("Modelleri Şimdi İndir") {
                    Task {
                        await downloadModels()
                    }
                }
            }
        } header: {
            Text("Modeller")
        } footer: {
            Text("Modeller bir kez internetten indirilir, sonrasında tüm işlemler internet olmadan cihaz üzerinde yapılır. İndirmezseniz ilk toplantı işlenirken otomatik indirilir.")
        }
    }

    @ViewBuilder
    private var speechModelStatusText: some View {
        switch speechModelStatus {
        case .installed:
            Text("Hazır")
                .foregroundStyle(.green)
        case .notInstalled:
            Text("İndirilmedi")
                .foregroundStyle(.secondary)
        case .unsupported:
            Text("Bu dil desteklenmiyor")
                .foregroundStyle(.red)
        case nil:
            ProgressView()
        }
    }

    private var storageSection: some View {
        Section("Depolama") {
            LabeledContent("Toplantılar", value: "\(meetingCount)")
            LabeledContent("Kayıtlı kişiler", value: "\(profileCount)")
            LabeledContent("Ses kayıtları", value: ByteCountFormatter.string(fromByteCount: recordingsSize, countStyle: .file))
        }
    }

    private var privacySection: some View {
        Section("Gizlilik") {
            Label {
                Text("Ses kayıtları, metinler ve ses imzaları yalnızca bu cihazda saklanır. Hiçbir ses veya metin sunucuya gönderilmez.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.tint)
            }
        }
    }

    private var needsDownload: Bool {
        speechModelStatus == .notInstalled || !diarizationReady
    }

    private var hasError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func refreshSpeechModelStatus() async {
        speechModelStatus = nil
        speechModelStatus = await TranscriptionService().modelStatus(localeIdentifier: localeIdentifier)
    }

    private func refreshStorage() {
        meetingCount = (try? modelContext.fetchCount(FetchDescriptor<Meeting>())) ?? 0
        profileCount = (try? modelContext.fetchCount(FetchDescriptor<SpeakerProfile>())) ?? 0
        recordingsSize = RecordingStore.totalSize()
    }

    private func downloadModels() async {
        guard download == nil else { return }
        defer { download = nil }
        do {
            if speechModelStatus == .notInstalled {
                download = .speech
                speechDownloadProgress = 0
                try await TranscriptionService().installModel(localeIdentifier: localeIdentifier) { value in
                    Task { @MainActor in
                        speechDownloadProgress = value
                    }
                }
                await refreshSpeechModelStatus()
            }
            if !diarizationReady {
                download = .diarization
                try await DiarizationService.shared.prepare()
                diarizationReady = DiarizationService.modelsWereDownloaded
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
