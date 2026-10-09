//  UIComponents.swift
//  Small pieces shared by many screens.

import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

// parseAmount, parseDecimal and amountString live in CoreModels.swift so they can be tested.

// MARK: - Colours and badges

func statusColor(_ status: PayStatus) -> Color {
    switch status {
    case .paid: return .green
    case .partial: return .orange
    case .unpaid: return .blue
    case .overdue: return .red
    case .noDues: return .gray
    }
}

struct StatusBadge: View {
    let status: PayStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }
}

struct TagLabel: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A two-column grid of tiles.
struct TileGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            content()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Inputs

struct MoneyField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("₹").foregroundStyle(.secondary)
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 150)
        }
    }
}

/// A switch that turns an optional date on or off, with a date picker when on.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { on in date = on ? (date ?? Date()) : nil }
        ))
        if let current = date {
            DatePicker("Date", selection: Binding(get: { current }, set: { date = $0 }), displayedComponents: .date)
        }
    }
}

extension View {
    /// Adds a Done button above the number keyboard.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Sharing

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Images

enum ImageTools {
    /// Converts any photo to a reasonably sized JPEG.
    static func jpeg(from raw: Data, maxSide: CGFloat = 2000) -> Data? {
        guard let image = UIImage(data: raw) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        if scale >= 1 {
            return image.jpegData(compressionQuality: 0.75)
        }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    static func thumbnail(_ url: URL, side: CGFloat = 88) -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: side, height: side)) ?? image
    }
}

// MARK: - Attachments

struct AttachmentRow: View {
    let meta: AttachmentMeta
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            if meta.kind == .photo, let image = ImageTools.thumbnail(url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.originalName.isEmpty ? meta.category : meta.originalName)
                    .lineLimit(1)
                Text(meta.category + " · " + Fmt.date(meta.addedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// What attachment rows ask for. The file picker, preview, share sheet and delete
/// question are attached to the whole screen (see `attachmentHost()`), not to a list
/// row that may be off screen when it is needed.
final class AttachmentPresenter: ObservableObject {
    @Published var previewURL: URL? = nil
    @Published var share: ShareItem? = nil
    @Published var pendingDelete: UUID? = nil
    @Published var importing = false
    var importCategory = ""
    var onImport: ((UUID) -> Void)? = nil

    func startImport(category: String, onAdd: @escaping (UUID) -> Void) {
        importCategory = category
        onImport = onAdd
        importing = true
    }
}

struct AttachmentHost: ViewModifier {
    @EnvironmentObject var store: Store
    @StateObject private var presenter = AttachmentPresenter()

    private var deleteBinding: Binding<Bool> {
        Binding(get: { presenter.pendingDelete != nil }, set: { if !$0 { presenter.pendingDelete = nil } })
    }

    func body(content: Content) -> some View {
        content
            .environmentObject(presenter)
            .fileImporter(isPresented: $presenter.importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                importFiles(result)
            }
            .quickLookPreview($presenter.previewURL)
            .sheet(item: $presenter.share) { item in
                ShareSheet(items: [item.url])
            }
            .confirmationDialog("Delete this file?", isPresented: deleteBinding, titleVisibility: .visible) {
                Button("Delete file", role: .destructive) {
                    if let id = presenter.pendingDelete {
                        store.deleteAttachment(id)
                    }
                    presenter.pendingDelete = nil
                }
            } message: {
                Text("It is removed from this iPhone. A copy already in your backup folder stays there.")
            }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            if let id = store.importAttachment(from: url, category: presenter.importCategory) {
                presenter.onImport?(id)
            }
        }
    }
}

extension View {
    /// Needed once on every screen that shows an AttachmentsSection.
    func attachmentHost() -> some View {
        modifier(AttachmentHost())
    }
}

/// A list section of photos and documents with add, view, share and delete.
struct AttachmentsSection: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var presenter: AttachmentPresenter
    let title: String
    let ids: [UUID]
    let category: String
    var allowPhotos = true
    let onAdd: (UUID) -> Void

    @State private var photoItem: PhotosPickerItem? = nil

    var body: some View {
        Section {
            ForEach(ids, id: \.self) { id in
                if let meta = store.attachment(id) {
                    Button {
                        presenter.previewURL = store.fileURL(meta)
                    } label: {
                        AttachmentRow(meta: meta, url: store.fileURL(meta))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            presenter.pendingDelete = id
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        Button {
                            presenter.share = ShareItem(url: store.fileURL(meta))
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
            if allowPhotos {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Add photo", systemImage: "photo.on.rectangle")
                }
                .onChange(of: photoItem) { item in
                    loadPhoto(item)
                }
            }
            Button {
                presenter.startImport(category: category, onAdd: onAdd)
            } label: {
                Label("Add PDF or file", systemImage: "doc.badge.plus")
            }
        } header: {
            Text(title)
        } footer: {
            Text(ids.isEmpty ? "Nothing added yet. Tap a file to view it, swipe left to share or delete." : "Tap to view. Swipe left to share or delete.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        Task {
            let raw = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let raw = raw {
                    let jpeg = ImageTools.jpeg(from: raw) ?? raw
                    if let id = store.addAttachment(jpeg, ext: "jpg", name: category + " photo", kind: .photo, category: category) {
                        onAdd(id)
                    }
                }
                photoItem = nil
            }
        }
    }
}
