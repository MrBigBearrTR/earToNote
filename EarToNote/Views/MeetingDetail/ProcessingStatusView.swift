import SwiftUI

struct ProcessingStatusView: View {
    let progress: ProcessingProgress?
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(progress?.stage.title ?? "İşleniyor", systemImage: "waveform.badge.magnifyingglass")
                .font(.headline)

            ProgressView(value: progress?.fraction ?? 0)

            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("İptal Et", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var hint: String {
        if !DiarizationService.modelsWereDownloaded {
            return "İlk kullanımda gerekli modeller indirilir; bunun için internet bağlantısı gerekir. Sonraki toplantılar tamamen çevrimdışı işlenir."
        }
        return "Uygulamadan çıkarsanız işlem bir süre arka planda devam eder. En hızlı sonuç için uygulamayı açık tutun."
    }
}

struct FailedStatusView: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Toplantı işlenemedi", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if canRetry {
                Button(action: onRetry) {
                    Label("Tekrar Dene", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}
