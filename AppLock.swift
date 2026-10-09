//  AppLock.swift
//  Face ID (or passcode) lock for the whole app.

import SwiftUI
import LocalAuthentication

final class LockManager: ObservableObject {
    @Published var isLocked = false { didSet { updateOverlay() } }
    /// Hides the screen while the app is in the background or the app switcher.
    @Published var isCovered = false { didSet { updateOverlay() } }
    @Published var message: String? = nil
    private var backgroundedAt: Date? = nil
    private var launched = false
    private var overlay: UIWindow? = nil

    static var methodName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return "Passcode" }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Passcode"
        }
    }

    /// Whether this iPhone has Face ID, Touch ID or a passcode that can unlock the app.
    static var canAuthenticate: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func appLaunched(enabled: Bool) {
        guard !launched else { return }
        launched = true
        if enabled {
            isLocked = true
            authenticate()
        }
    }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func didBecomeActive(enabled: Bool, afterMinutes: Int) {
        guard let since = backgroundedAt else { return }
        backgroundedAt = nil
        guard enabled else { return }
        if Date().timeIntervalSince(since) >= Double(max(0, afterMinutes) * 60) {
            isLocked = true
            authenticate()
        }
    }

    /// The lock screen and privacy cover are shown in their own window above
    /// everything, so an open sheet is covered too.
    private func updateOverlay() {
        if isLocked || isCovered {
            showOverlay()
        } else if let window = overlay {
            window.isHidden = true
            overlay = nil
        }
    }

    private func showOverlay() {
        guard overlay == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        window.rootViewController = UIHostingController(rootView: LockOverlay().environmentObject(self))
        window.isHidden = false
        overlay = window
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            message = "Set a passcode on this iPhone to use the app lock."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock RentBook") { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.isLocked = false
                    self.message = nil
                }
            }
        }
    }
}

struct LockScreen: View {
    @EnvironmentObject var lock: LockManager

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("RentBook is locked")
                    .font(.title3.weight(.semibold))
                Button {
                    lock.authenticate()
                } label: {
                    Label("Unlock with " + LockManager.methodName, systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                if let message = lock.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}

struct LockOverlay: View {
    @EnvironmentObject var lock: LockManager

    var body: some View {
        if lock.isLocked {
            LockScreen()
        } else {
            PrivacyCover()
        }
    }
}

/// Hides the screen in the app switcher when the lock is on.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            Image(systemName: "house.lodge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}
