//
//  ScannerError.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


//
//  BarcodeScannerView.swift
//  calorie_calculator_THING
//
//  Minimal barcode scanner using AVFoundation metadata capture
//  Supports EAN-13, EAN-8, UPCE, CODE128 and QR by default.
//
//  Usage: present as a sheet and provide a completion handler that returns .success(code) or .failure(ScannerError)
//
 
import SwiftUI
import AVFoundation
 
enum ScannerError: Error {
    case permissionDenied
    case badInput
    case noData
    case other
}
 
struct BarcodeScannerView: UIViewControllerRepresentable {
    typealias Completion = (Result<String, ScannerError>) -> Void
 
    var supportedCodes: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .qr
    ]
    var completion: Completion
 
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
 
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.supportedCodes = supportedCodes
        vc.delegate = context.coordinator
        return vc
    }
 
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        // no-op
    }
 
    class Coordinator: NSObject, ScannerViewControllerDelegate {
        var parent: BarcodeScannerView
 
        init(_ parent: BarcodeScannerView) {
            self.parent = parent
        }
 
        func scanner(_ controller: ScannerViewController, didFindCode code: String) {
            parent.completion(.success(code))
        }
 
        func scanner(_ controller: ScannerViewController, didFailWith error: ScannerError) {
            parent.completion(.failure(error))
        }
    }
}
 
// MARK: - UIKit Scanner VC
protocol ScannerViewControllerDelegate: AnyObject {
    func scanner(_ controller: ScannerViewController, didFindCode code: String)
    func scanner(_ controller: ScannerViewController, didFailWith error: ScannerError)
}
 
final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var supportedCodes: [AVMetadataObject.ObjectType] = []
    weak var delegate: ScannerViewControllerDelegate?
 
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var isScanning = false
 
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndSetup()
    }
 
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
 
    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupSession()
                    } else {
                        self.delegate?.scanner(self, didFailWith: .permissionDenied)
                    }
                }
            }
        default:
            delegate?.scanner(self, didFailWith: .permissionDenied)
        }
    }
 
    private func setupSession() {
        guard !isConfigured else { startRunning(); return }
 
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.scanner(self, didFailWith: .badInput)
            return
        }
 
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
 
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = supportedCodes
            } else {
                delegate?.scanner(self, didFailWith: .badInput)
                return
            }
 
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            if let pl = previewLayer {
                pl.frame = view.bounds
                view.layer.addSublayer(pl)
            }
 
            // Add a simple visual overlay (center rectangle)
            let overlay = UIView()
            overlay.layer.borderColor = UIColor.systemGreen.cgColor
            overlay.layer.borderWidth = 2
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                overlay.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
                overlay.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
                overlay.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.25)
            ])
 
            // Bring overlay above preview
            view.bringSubviewToFront(overlay)
 
            isConfigured = true
            startRunning()
        } catch {
            delegate?.scanner(self, didFailWith: .other)
        }
    }
 
    private func startRunning() {
        guard !isScanning else { return }
        session.startRunning()
        isScanning = true
    }
 
    private func stopRunning() {
        guard isScanning else { return }
        session.stopRunning()
        isScanning = false
    }
 
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopRunning()
    }
 
    deinit {
        stopRunning()
    }
 
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !metadataObjects.isEmpty else { return }
        for metadata in metadataObjects {
            if let readable = metadata as? AVMetadataMachineReadableCodeObject,
               let string = readable.stringValue {
                // Found first valid code; stop scanning and notify
                stopRunning()
                delegate?.scanner(self, didFindCode: string)
                return
            }
        }
    }
}
