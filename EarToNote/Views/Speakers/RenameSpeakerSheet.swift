import MeetingCore
import SwiftData
import SwiftUI

/// Names a voice of a meeting, or corrects which saved person it belongs to.
struct RenameSpeakerSheet: View {
    let participant: MeetingParticipant

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SpeakerProfile.name) private var profiles: [SpeakerProfile]

    @State private var name = ""
    @State private var duplicateProfileID: UUID?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField(participant.displayName, text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            } header: {
                Text("Bu kişinin adı")
            } footer: {
                Text("İsim bu kişinin geçtiği tüm toplantılarda değişir. Kişi sonraki toplantılarda sesinden tanındığında da bu isimle yazılır.")
            }

            if let similarity = participant.matchSimilarity {
                Section {
                    LabeledContent("Ses benzerliği", value: similarity.formatted(.percent.precision(.fractionLength(0))))
                } footer: {
                    Text("Bu ses, kayıtlı kişiyle otomatik olarak eşleştirildi.")
                }
            }

            let otherProfiles = profiles.filter { $0.id != participant.speaker?.id }
            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            SpeakerDirectory.reassign(participant, to: profile, in: modelContext)
                            dismiss()
                        } label: {
                            HStack {
                                SpeakerDot(number: profile.number)
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(profile.meetingCount) toplantı")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Bu ses aslında başka biri mi?")
                } footer: {
                    Text("Seçtiğiniz kişiye aktarılır ve ses imzaları buna göre düzeltilir.")
                }
            }

            if participant.speaker != nil {
                Section {
                    Button("Yeni Kişi Olarak Ayır") {
                        SpeakerDirectory.splitIntoNewProfile(participant, name: SpeakerNaming.cleanedName(name), in: modelContext)
                        dismiss()
                    }
                } footer: {
                    Text("Bu ses yanlışlıkla başka biriyle eşleştiyse yeni bir kişi olarak kaydedin.")
                }
            }
        }
        .navigationTitle(participant.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet", action: save)
                    .disabled(SpeakerNaming.cleanedName(name) == nil)
            }
        }
        .confirmationDialog(duplicateTitle, isPresented: isShowingDuplicateDialog, titleVisibility: .visible) {
            if let duplicate = profiles.first(where: { $0.id == duplicateProfileID }) {
                Button("Evet, Aynı Kişi") {
                    SpeakerDirectory.reassign(participant, to: duplicate, in: modelContext)
                    dismiss()
                }
                Button("Hayır, Farklı Biri") {
                    applyName(SpeakerNaming.cleanedName(name) ?? duplicate.name)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu ses o kişiye aitse, bu toplantıdaki konuşmalar o kişiye aktarılır.")
        }
        .onAppear {
            if let speaker = participant.speaker, speaker.isNamedByUser {
                name = speaker.name
            }
            isNameFocused = true
        }
    }

    private var duplicateTitle: String {
        "\"\(SpeakerNaming.cleanedName(name) ?? "")\" adında bir kişi zaten var. Bu ses o kişiye mi ait?"
    }

    private var isShowingDuplicateDialog: Binding<Bool> {
        Binding(
            get: { duplicateProfileID != nil },
            set: { if !$0 { duplicateProfileID = nil } }
        )
    }

    private func save() {
        guard let cleaned = SpeakerNaming.cleanedName(name) else { return }
        let duplicate = profiles.first { profile in
            profile.id != participant.speaker?.id
                && profile.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR")) == .orderedSame
        }
        if let duplicate {
            duplicateProfileID = duplicate.id
            return
        }
        applyName(cleaned)
    }

    private func applyName(_ cleaned: String) {
        if let profile = participant.speaker {
            SpeakerDirectory.rename(profile, to: cleaned)
            try? modelContext.save()
        } else {
            SpeakerDirectory.splitIntoNewProfile(participant, name: cleaned, in: modelContext)
        }
        dismiss()
    }
}
