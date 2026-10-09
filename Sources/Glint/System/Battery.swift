import Foundation
import IOKit.ps

/// The internal battery's charge and charging state, updated whenever macOS reports a
/// power source change.
@MainActor
final class Battery {
    static let shared = Battery()

    struct State: Equatable {
        /// 0–100.
        var percent: Int
        var isCharging: Bool
        /// Connected to power, whether or not it's charging (it may be full, or held
        /// back by Optimised Battery Charging).
        var isOnPower: Bool

        /// Matches when macOS itself warns about the battery.
        var isLow: Bool { !isOnPower && percent <= 10 }
    }

    /// nil on a Mac without a battery.
    var state: State? {
        #if DEBUG
        if let debugState { return debugState }
        #endif
        return measured
    }

    var onChange: (() -> Void)?
    private var measured: State?

    var isAvailable: Bool { state != nil }

    private var source: CFRunLoopSource?

    private init() {
        measured = Self.read()
    }

    func start() {
        guard source == nil else { return }
        // A C callback can't capture anything, hence going through the shared instance.
        source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { Battery.shared.update() }
        }, nil)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
        update()
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    private func update() {
        let new = Self.read()
        guard new != measured else { return }
        measured = new
        onChange?()
    }

    #if DEBUG
    private var debugState: State?

    /// Shows `state` instead of the real battery (nil goes back to it), for screenshots.
    func debugOverride(_ state: State?) {
        debugState = state
        onChange?()
    }
    #endif

    private static func read() -> State? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return State(
                percent: min(Swift.max(current * 100 / max, 0), 100),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isOnPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}
