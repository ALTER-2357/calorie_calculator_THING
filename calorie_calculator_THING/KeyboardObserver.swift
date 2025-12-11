//
//  KeyboardObserver.swift
//  calorie_calculator_THING
//
//  Created by lewis mills on 10/12/2025.
//


import SwiftUI
import Combine

final class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    @Published var animationDuration: Double = 0.25
    @Published var animationCurveRaw: Int = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        Publishers.Merge3(willChange, willShow, willHide)
            .compactMap { $0.userInfo }
            .receive(on: RunLoop.main)
            .sink { [weak self] info in
                guard let self = self else { return }
                let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
                let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
                self.animationDuration = duration
                self.animationCurveRaw = curve

                if let frameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    // convert to local window height (we only need height)
                    let height = max(0, frameValue.height)
                    self.keyboardHeight = height
                } else {
                    self.keyboardHeight = 0
                }
            }
            .store(in: &cancellables)
    }

    // Map UIView.AnimationCurve -> SwiftUI Animation
    var swiftUIAnimation: Animation {
        let duration = max(0.01, animationDuration)
        switch animationCurveRaw {
        case 0:
            return .easeInOut(duration: duration) // fallback
        case 1:
            return .easeIn(duration: duration)
        case 2:
            return .easeOut(duration: duration)
        case 3:
            return .linear(duration: duration)
        default:
            return .easeOut(duration: duration)
        }
    }
}

struct KeyboardAdaptive: ViewModifier {
    @StateObject private var keyboard = KeyboardObserver()
    // optional bottom safe area subtraction could be done here if needed

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboard.keyboardHeight)
            .animation(keyboard.swiftUIAnimation, value: keyboard.keyboardHeight)
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        modifier(KeyboardAdaptive())
    }
}