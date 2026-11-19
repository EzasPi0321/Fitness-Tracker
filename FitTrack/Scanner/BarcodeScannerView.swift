import AVFoundation
import SwiftUI
import Vision
import VisionKit

enum ScannerAvailability: Equatable {
    case checking, ready, cameraDenied, unsupported
}

/// SwiftUI wrapper around VisionKit's `DataScannerViewController`, configured for retail
/// barcodes. Every iPhone that runs iOS 17 has the A12+ Neural Engine VisionKit requires,
/// so `isSupported` is only false on the Simulator and some iPads.
struct BarcodeScannerView: UIViewControllerRepresentable {
    static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128]

    @Binding var isScanning: Bool
    var onScan: (String) -> Void

    /// Requests camera access if needed and reports whether scanning can start.
    @MainActor
    static func availability() async -> ScannerAvailability {
        guard DataScannerViewController.isSupported else { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .cameraDenied }
        default:
            return .cameraDenied
        }
        return DataScannerViewController.isAvailable ? .ready : .cameraDenied
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if isScanning, !controller.isScanning {
            try? controller.startScanning()
        } else if !isScanning, controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: BarcodeScannerView
        private let haptics = UIImpactFeedbackGenerator(style: .medium)
        private var lastDelivery: (payload: String, date: Date)?

        init(parent: BarcodeScannerView) {
            self.parent = parent
            super.init()
            haptics.prepare()
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    deliver(payload)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                deliver(payload)
            }
        }

        private func deliver(_ payload: String) {
            let code = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard parent.isScanning, !code.isEmpty else { return }
            // Debounce: the delegate can fire several times for the same code before SwiftUI
            // propagates `isScanning = false`.
            if let last = lastDelivery, last.payload == code, Date.now.timeIntervalSince(last.date) < 2 { return }
            lastDelivery = (code, .now)
            haptics.impactOccurred()
            parent.onScan(code)
        }
    }
}
