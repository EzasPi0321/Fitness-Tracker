import SwiftData
import SwiftUI

/// Prefill for the manual fallback form when a barcode isn't found or lacks nutrition data.
struct ManualPrefill: Identifiable {
    let id = UUID()
    var barcode: String?
    var name: String?
    var brand: String?
}

struct ScanFlowView: View {
    let logDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var availability: ScannerAvailability = .checking
    @State private var isScanning = true
    @State private var isLookingUp = false
    @State private var product: FoodProduct?
    @State private var manualPrefill: ManualPrefill?
    @State private var pendingManual: ManualPrefill?
    @State private var didLog = false
    @State private var errorMessage: String?
    @State private var lastCode: String?
    @State private var showTypeBarcode = false
    @State private var typedBarcode = ""

    private let service = OpenFoodFactsService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                scannerContent
                if isLookingUp {
                    ProgressView("Looking up product…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showTypeBarcode = true } label: { Label("Type Barcode", systemImage: "keyboard") }
                        Button {
                            isScanning = false
                            manualPrefill = ManualPrefill()
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .task { availability = await BarcodeScannerView.availability() }
        .sheet(item: $product, onDismiss: productSheetDismissed) { product in
            ProductDetailSheet(product: product, logDate: logDate) {
                didLog = true
            } onNeedsManualEntry: {
                pendingManual = ManualPrefill(barcode: product.barcode, name: product.name, brand: product.brand)
            }
        }
        .sheet(item: $manualPrefill, onDismiss: manualSheetDismissed) { prefill in
            NavigationStack {
                ManualEntryView(logDate: logDate,
                                barcode: prefill.barcode,
                                prefillName: prefill.name,
                                prefillBrand: prefill.brand) {
                    didLog = true
                }
            }
        }
        .alert("Lookup Failed", isPresented: errorBinding) {
            Button("Try Again") {
                if let lastCode { Task { await lookUp(lastCode) } }
            }
            Button("Enter Manually") { manualPrefill = ManualPrefill(barcode: lastCode) }
            Button("Cancel", role: .cancel) { isScanning = true }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Enter Barcode", isPresented: $showTypeBarcode) {
            TextField("e.g. 3017620422003", text: $typedBarcode)
                .keyboardType(.numberPad)
            Button("Look Up") {
                let code = typedBarcode
                typedBarcode = ""
                Task { await lookUp(code) }
            }
            Button("Cancel", role: .cancel) { typedBarcode = "" }
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch availability {
        case .checking:
            ProgressView().tint(.white)
        case .ready:
            BarcodeScannerView(isScanning: $isScanning) { code in
                Task { await lookUp(code) }
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay { ScannerReticle() }
            .overlay(alignment: .bottom) {
                Text("Point the camera at a product barcode")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        case .cameraDenied:
            ContentUnavailableView {
                Label("Camera Access Needed", systemImage: "camera.fill")
            } description: {
                Text("Allow camera access in Settings to scan barcodes, or type the number instead.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
                Button("Type Barcode") { showTypeBarcode = true }
            }
            .environment(\.colorScheme, .dark)
        case .unsupported:
            ContentUnavailableView {
                Label("Scanner Unavailable", systemImage: "barcode.viewfinder")
            } description: {
                Text("Live barcode scanning isn't supported on this device. You can type the barcode instead.")
            } actions: {
                Button("Type Barcode") { showTypeBarcode = true }
                    .buttonStyle(.borderedProminent)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func lookUp(_ code: String) async {
        guard !isLookingUp else { return }
        isScanning = false
        isLookingUp = true
        lastCode = code
        defer { isLookingUp = false }

        // 1. The user's own foods take precedence (and work offline).
        if let custom = customFood(forBarcode: code) {
            custom.markUsed()
            product = FoodProduct(customFood: custom)
            return
        }

        // 2. Open Food Facts.
        do {
            product = try await service.product(for: code)
        } catch FoodLookupError.notFound {
            manualPrefill = ManualPrefill(barcode: code.filter(\.isNumber))
        } catch FoodLookupError.invalidBarcode {
            errorMessage = FoodLookupError.invalidBarcode.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func customFood(forBarcode code: String) -> CustomFood? {
        let barcode: String? = code.filter(\.isNumber)
        var descriptor = FetchDescriptor<CustomFood>(predicate: #Predicate { $0.barcode == barcode })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func productSheetDismissed() {
        if didLog { dismiss(); return }
        if let pendingManual {
            self.pendingManual = nil
            manualPrefill = pendingManual
        } else {
            isScanning = true
        }
    }

    private func manualSheetDismissed() {
        if didLog { dismiss() } else { isScanning = true }
    }
}

private struct ScannerReticle: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [24, 12]))
            .frame(width: 280, height: 160)
            .shadow(color: .black.opacity(0.4), radius: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
