import MeetingCore
import SwiftData
import SwiftUI

private struct ProfileSelection: Identifiable {
    let id: UUID
}

/// All people remembered on the device, with rename, merge and delete.
struct SpeakersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpeakerProfile.number) private var profiles: [SpeakerProfile]

    @State private var renamingID: UUID?
    @State private var draftName = ""
    @State private var mergeSource: ProfileSelection?
    @State private var deletingID: UUID?

    var body: some View {
        List {
            if !profiles.isEmpty {
                Section {
                    ForEach(profiles) { profile in
                        row(for: profile)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deletingID = profile.id
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                                Button {
                                    mergeSource = ProfileSelection(id: profile.id)
                                } label: {
                                    Label("Birleştir", systemImage: "arrow.triangle.merge")
                                }
                                .tint(.indigo)
                            }
                            .contextMenu {
                                Button {
                                    beginRename(profile)
                                } label: {
                                    Label("İsmi Değiştir", systemImage: "pencil")
                                }
                                Button {
                                    mergeSource = ProfileSelection(id: profile.id)
                                } label: {
                                    Label("Başka Biriyle Birleştir", systemImage: "arrow.triangle.merge")
                                }
                                Button(role: .destructive) {
                                    deletingID = profile.id
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    Text("Kişiler ve ses imzaları yalnızca bu cihazda saklanır. Aynı kişi iki ayrı kayıt olarak görünüyorsa sola kaydırıp birleştirebilirsiniz.")
                }
            }
        }
        .overlay {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "Henüz kişi yok",
                    systemImage: "person.2",
                    description: Text("İlk toplantınız işlendiğinde konuşmacılar burada görünür.")
                )
            }
        }
        .navigationTitle("Kişiler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") {
                    dismiss()
                }
            }
        }
        .alert("İsmi Değiştir", isPresented: isRenaming) {
            TextField("İsim", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Kaydet") {
                commitRename()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yeni isim bu kişinin geçtiği tüm toplantılarda kullanılır.")
        }
        .confirmationDialog("Kişi silinsin mi?", isPresented: isDeleting, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let profile = profiles.first(where: { $0.id == deletingID }) {
                    SpeakerDirectory.delete(profile, in: modelContext)
                }
                deletingID = nil
            }
        } message: {
            Text("Ses imzası silinir; bu kişi geçmiş toplantılarda \"Bilinmeyen konuşmacı\" olarak görünür ve sonraki toplantılarda tanınmaz.")
        }
        .sheet(item: $mergeSource) { selection in
            NavigationStack {
                // The picker only receives the source's name: the source profile is deleted by the merge.
                MergeSpeakerPicker(
                    sourceName: profiles.first(where: { $0.id == selection.id })?.name ?? "",
                    candidates: profiles.filter { $0.id != selection.id }
                ) { target in
                    mergeSource = nil
                    if let source = profiles.first(where: { $0.id == selection.id }) {
                        SpeakerDirectory.merge(source, into: target, in: modelContext)
                    }
                }
            }
        }
    }

    private func row(for profile: SpeakerProfile) -> some View {
        Button {
            beginRename(profile)
        } label: {
            HStack(spacing: 12) {
                SpeakerDot(number: profile.number, size: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .foregroundStyle(.primary)
                    Text(detailText(for: profile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if profile.hasVoiceprint {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Ses imzası kayıtlı")
                }
            }
        }
    }

    private func detailText(for profile: SpeakerProfile) -> String {
        var parts = ["\(profile.meetingCount) toplantı"]
        if !profile.isNamedByUser {
            parts.append("isim verilmedi")
        }
        if !profile.hasVoiceprint {
            parts.append("ses imzası yok")
        }
        return parts.joined(separator: " · ")
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private var isDeleting: Binding<Bool> {
        Binding(
            get: { deletingID != nil },
            set: { if !$0 { deletingID = nil } }
        )
    }

    private func beginRename(_ profile: SpeakerProfile) {
        draftName = profile.isNamedByUser ? profile.name : ""
        renamingID = profile.id
    }

    private func commitRename() {
        defer { renamingID = nil }
        guard let cleaned = SpeakerNaming.cleanedName(draftName),
              let profile = profiles.first(where: { $0.id == renamingID })
        else { return }
        SpeakerDirectory.rename(profile, to: cleaned)
        try? modelContext.save()
    }
}

private struct MergeSpeakerPicker: View {
    let sourceName: String
    let candidates: [SpeakerProfile]
    let onSelect: (SpeakerProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(candidates) { target in
                    Button {
                        onSelect(target)
                    } label: {
                        HStack(spacing: 12) {
                            SpeakerDot(number: target.number, size: 14)
                            Text(target.name)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } header: {
                Text("\"\(sourceName)\" kiminle aynı kişi?")
            } footer: {
                Text("\"\(sourceName)\" kişisinin tüm toplantıları ve ses imzası seçtiğiniz kişiye aktarılır.")
            }
        }
        .navigationTitle("Birleştir")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç") {
                    dismiss()
                }
            }
        }
    }
}
