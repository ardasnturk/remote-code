import SwiftUI

/// The real people of a storyboard: the downloaded photo and Codex's edit, to pick one or have Codex edit it again.
struct PromoStudioPeopleSection: View {
    let store: PromoStudioStore
    let post: PromoStudioPost
    var onError: (String) -> Void
    @State private var instructions: [String: String] = [:]

    var body: some View {
        let people = post.directed?.storyboard.people ?? []
        let canEdit = store.state?.settings.editPhotos == true
        VStack(alignment: .leading, spacing: 12) {
            Text("People").font(.headline)
            ForEach(people, id: \.name) { person in
                let photos = post.media.people?.first { $0.name == person.name }
                let usingEdit = person.useOriginal != true && photos?.edited != nil
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.name).font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        thumbnail(photos?.original, label: Text("Original"), selected: !usingEdit && photos?.original != nil) {
                            run("setPersonPhoto", ["postId": post.id, "name": person.name, "useOriginal": true])
                        }
                        if canEdit || photos?.edited != nil {
                            thumbnail(photos?.edited, label: Text("Edited"), selected: usingEdit) {
                                run("setPersonPhoto", ["postId": post.id, "name": person.name, "useOriginal": false])
                            }
                        }
                    }
                    if photos?.original == nil {
                        Text("No photo found; the video shows the name instead.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = person.editError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    if canEdit, photos?.original != nil {
                        TextField("How Codex should change the photo", text: Binding(
                            get: { instructions[person.name] ?? person.edit ?? "" },
                            set: { instructions[person.name] = $0 }
                        ), axis: .vertical)
                        .lineLimit(2...4)
                        .font(.footnote)
                        .textFieldStyle(.roundedBorder)
                        Button(photos?.edited == nil ? "Edit with Codex" : "Edit Again") {
                            var body: [String: Any] = ["postId": post.id, "name": person.name]
                            if let text = instructions[person.name] { body["instruction"] = text }
                            run("editPersonPhoto", body)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(store.job(post.id) != nil || (instructions[person.name] ?? person.edit ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            if post.usesEditedPhotos {
                Label("Photos edited with AI: label the post as AI-made on Instagram, and don’t present the edit as a real moment.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func thumbnail(_ path: String?, label: Text, selected: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            VStack(spacing: 4) {
                PromoStudioImage(store: store, path: path)
                    .frame(width: 84, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                label.font(.caption2).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(path == nil || store.job(post.id) != nil)
    }

    private func run(_ action: String, _ body: [String: Any]) {
        Task {
            do { try await store.action(action, body) } catch { onError(error.localizedDescription) }
        }
    }
}

extension PromoStudioPost {
    /// The video shows people in photos Codex edited (Instagram asks for AI-made content to be labeled)
    var usesEditedPhotos: Bool {
        (directed?.storyboard.people ?? []).contains { person in
            person.useOriginal != true && media.people?.first { $0.name == person.name }?.edited != nil
        }
    }
}
