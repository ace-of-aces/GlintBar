import Darwin
import Foundation
import IOKit
import Observation

/// CPU, GPU, memory and storage usage, sampled every couple of seconds while something
/// shows it.
@MainActor
@Observable
final class SystemResources {
    static let shared = SystemResources()

    /// Each value is 0–1, or nil until known.
    struct Usage: Equatable, Sendable {
        var cpu: Double?
        var gpu: Double?
        var memory: Double?
        var storage: Double?
    }

    var usage: Usage {
        #if DEBUG
        if let debugUsage { return debugUsage }
        #endif
        return measured
    }

    private var measured = Usage()
    /// Called after every change, for observers outside SwiftUI (the Touch Bar).
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var clients: Set<AnyHashable> = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var isSampling = false

    private static let interval: TimeInterval = 2

    private init() {}

    /// Starts sampling while at least one client needs the numbers.
    func setNeeded(_ needed: Bool, by client: AnyHashable) {
        if needed { clients.insert(client) } else { clients.remove(client) }
        if clients.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            timer?.tolerance = Self.interval / 10
            sample()
        }
    }

    private func sample() {
        guard !isSampling else { return } // the last reading is still being taken
        isSampling = true
        sampler.read(cpuBaselineMaxAge: 2 * Self.interval) { [weak self] new in
            guard let self else { return }
            self.isSampling = false
            // Dropped if sampling stopped in the meantime.
            guard self.timer != nil, new != self.measured else { return }
            self.measured = new
            self.onChange?()
        }
    }

    #if DEBUG
    private var debugUsage: Usage?

    /// Shows `usage` instead of the real readings (nil goes back to them), for screenshots.
    func debugOverride(_ usage: Usage?) {
        debugUsage = usage
        onChange?()
    }
    #endif
}

/// Takes the readings on a queue of its own: asking how much storage is free (purgeable
/// space included) alone takes several milliseconds, too long for the main thread.
private final class Sampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "center.julian.glintbar.resources", qos: .utility)
    private let host = mach_host_self()
    // Only touched on `queue`.
    private var lastCPUTicks: [UInt64]?
    private var lastCPUTicksTime = DispatchTime(uptimeNanoseconds: 0)

    /// Reads everything and hands it to `deliver` on the main thread. CPU usage is the busy
    /// share since the previous reading; if that is older than `cpuBaselineMaxAge` (the
    /// first reading, or sampling was paused) it is measured over a short window instead,
    /// so the figure is current.
    func read(cpuBaselineMaxAge: TimeInterval, then deliver: @escaping @MainActor @Sendable (SystemResources.Usage) -> Void) {
        queue.async { [self] in
            let finish: @Sendable () -> Void = { [self] in
                let usage = SystemResources.Usage(cpu: cpuUsage(), gpu: Self.gpuUsage(), memory: memoryUsage(), storage: Self.storageUsage())
                DispatchQueue.main.async { MainActor.assumeIsolated { deliver(usage) } }
            }
            let baselineAge = Double(DispatchTime.now().uptimeNanoseconds - lastCPUTicksTime.uptimeNanoseconds) / 1e9
            if lastCPUTicks == nil || baselineAge > cpuBaselineMaxAge {
                _ = cpuUsage()
                queue.asyncAfter(deadline: .now() + 0.25, execute: finish)
            } else {
                finish()
            }
        }
    }

    // MARK: - Readings

    /// Busy share of all CPU time since the previous call.
    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3].map(UInt64.init)
        defer {
            lastCPUTicks = ticks
            lastCPUTicksTime = .now()
        }
        guard let last = lastCPUTicks else { return nil }
        // The counters are 32-bit and wrap; &- keeps the difference right across a wrap.
        let delta = zip(ticks, last).map { UInt64(UInt32(truncatingIfNeeded: $0) &- UInt32(truncatingIfNeeded: $1)) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total)
    }

    /// Like Activity Monitor's "Memory Used": app memory, wired and compressed.
    private func memoryUsage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(Double(usedPages) * Double(getpagesize()) / total, 1) : nil
    }

    /// The GPU's own utilisation figure, as shown in Activity Monitor's GPU History.
    private static func gpuUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busiest: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            if let percent = statistics?["Device Utilization %"] as? Int {
                busiest = max(busiest ?? 0, percent)
            }
        }
        return busiest.map { min(Double($0) / 100, 1) }
    }

    /// The startup disk, counting purgeable space as free, like Finder does.
    private static func storageUsage() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return min(max(1 - Double(available) / Double(total), 0), 1)
    }
}
