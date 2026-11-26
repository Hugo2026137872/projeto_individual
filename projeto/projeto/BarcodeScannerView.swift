import SwiftUI
import VisionKit

struct BarcodeScannerView: View {
    @Binding var scannedISBN: String?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        #if targetEnvironment(simulator)
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Câmara indisponível no Simulador iOS")
                .font(.headline)
            
            Text("Para testar o leitor de códigos de barras real, executa a app num iPhone físico.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Simular Leitura (ISBN: Clean Code)") {
                scannedISBN = "9780132350884"
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancelar") {
                dismiss()
            }
            .foregroundColor(.red)
        }
        .padding()
        #else
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(scannedISBN: $scannedISBN)
                .ignoresSafeArea()
        } else {
            VStack(spacing: 16) {
                Text("Scanner não suportado neste dispositivo.")
                    .font(.headline)
                Button("Fechar") { dismiss() }
            }
        }
        #endif
    }
}

#if !targetEnvironment(simulator)
struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var scannedISBN: String?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: DataScannerRepresentable
        
        init(_ parent: DataScannerRepresentable) {
            self.parent = parent
        }
        
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                parent.scannedISBN = value
                parent.dismiss()
            }
        }
    }
}
#endif
