//
//  ShareSheet.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 09/12/2025.
//


import SwiftUI

#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
import UIKit

/// A UIViewControllerRepresentable wrapper for UIActivityViewController (share sheet).
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        vc.excludedActivityTypes = excludedActivityTypes
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

/// A small NSViewRepresentable that presents an `NSSharingServicePicker` for the provided items.
/// It presents the picker as soon as it's added to the view hierarchy.
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            // Create a temporary button to anchor the share picker
            let btn = NSButton(title: "", target: nil, action: nil)
            v.addSubview(btn)
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}
#endif