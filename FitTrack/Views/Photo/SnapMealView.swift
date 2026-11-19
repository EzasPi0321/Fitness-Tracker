import PhotosUI
import SwiftUI

/// One analysed photo, handed to the review screen.
struct MealReview: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let analysis: MealAnalysis
}

struct SnapMealView: View {
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.visionProvider) private var providerRaw = VisionProvider.gemini.rawValue
    @AppStorage(SettingsKey.visionModel) private var model = VisionProvider.gemini.defaultModel

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var hint = ""
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var review: MealReview?
    @State private var showKeySetup = false

    private var provider: VisionProvider { VisionProvider(rawValue: providerRaw) ?? .gemini }

    var body: some View {
        NavigationStack {
            Form {
                Section { photoPreview }
                    .listRowInsets(EdgeInsets())

                Section {
                    if CameraPicker.isAvailable {
                        Button { showCamera = true } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                    }
                }

                Section {
                    TextField("Optional details, e.g. “cooked in butter”, “half eaten”", text: $hint, axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text("Photos are sent to \(provider.displayName) for analysis. Estimates are approximate — you'll review every item before it's logged.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Snap Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze") { Task { await analyze() } }
                        .disabled(image == nil || isAnalyzing)
                }
            }
            .overlay {
                if isAnalyzing {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Estimating calories…").font(.subheadline.weight(.medium))
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .navigationDestination(item: $review) { review in
                AIReviewView(review: review, logDate: logDate) { dismiss() }
            }
        }
        .interactiveDismissDisabled(isAnalyzing)
        .onChange(of: pickerItem) { _, item in
            Task { await loadPhoto(from: item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $image)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showKeySetup) {
            NavigationStack {
                Form { AIProviderSettingsSection() }
                    .navigationTitle("AI Provider")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showKeySetup = false } }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityLabel("Selected meal photo")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "camera.macro")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("Take a top-down photo of your meal in good light")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self), let loaded = UIImage(data: data) {
                image = loaded
                errorMessage = nil
            } else {
                errorMessage = "That photo couldn't be loaded."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func analyze() async {
        guard let image else { return }
        guard let apiKey = KeychainStore.string(for: provider.keychainAccount), !apiKey.isEmpty else {
            showKeySetup = true
            return
        }

        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        // Resize/compress off the main thread.
        let jpeg = await Task.detached(priority: .userInitiated) { image.preparedForUpload() }.value
        guard let jpeg else {
            errorMessage = VisionError.imageEncodingFailed.localizedDescription
            return
        }

        let service = AIVisionService(provider: provider,
                                      apiKey: apiKey,
                                      model: model.nilIfBlank ?? provider.defaultModel)
        do {
            let analysis = try await service.analyzeMeal(jpegData: jpeg, userHint: hint)
            guard !analysis.items.isEmpty else {
                errorMessage = "No food was recognised. Try a clearer, closer photo."
                return
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            review = MealReview(image: image, analysis: analysis)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
