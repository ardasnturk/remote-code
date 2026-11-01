#if canImport(Darwin)
import Darwin
import Foundation
import RemoteCodeKit
import Synchronization

/// The processes of one app bundle (helpers included) or one plain process.
public struct ProcessGroup: Sendable, Hashable {
    /// The outermost `.app` bundle path, or `proc:<name>`.
    public var key: String
    public var name: String
    public var bundlePath: String?
    /// Percent of one core, like Activity Monitor (can exceed 100).
    public var cpu: Double
    public var memory: Int64
    public var pids: [pid_t]
}

/// Whole-Mac load.
public struct SystemLoad: Sendable, Hashable {
    /// 0–100, all cores.
    public var cpu: Double = 0
    public var memoryUsed: Int64 = 0
    public var memoryTotal = Int64(ProcessInfo.processInfo.physicalMemory)
    public var pressure = MemoryPressure.normal
}

/// Samples per-process CPU time and memory with libproc (D-116). Only the
/// user's own processes are readable without root, which covers every app
/// they started. CPU needs two samples; the first one reports 0.
/// Adapted from Perch's `ProcessSampler` (MIT, see NOTICE).
public final class ProcessSampler: Sendable {
    private struct State {
        var lastCPU: [pid_t: UInt64] = [:]
        var groupCache: [pid_t: (key: String, name: String, bundle: String?)] = [:]
        var lastSample: UInt64 = 0
        var lastHostTicks: (busy: UInt64, total: UInt64)?
    }

    private let state = Mutex(State())
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    public init() {}

    /// When the previous sample was taken (uptime nanoseconds), 0 before the first.
    public var lastSampleTime: UInt64 { state.withLock { $0.lastSample } }

    public func sample() -> ([ProcessGroup], SystemLoad) {
        state.withLock { state in
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = state.lastSample == 0 ? 0 : Double(now - state.lastSample)
            state.lastSample = now

            let count = proc_listallpids(nil, 0)
            var pids = [pid_t](repeating: 0, count: Int(max(count, 0)) + 64)
            let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
            var groups: [String: ProcessGroup] = [:]
            var seen = Set<pid_t>()

            for pid in pids.prefix(max(0, found)) where pid > 0 {
                var info = rusage_info_v4()
                let result = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                    }
                }
                guard result == 0 else { continue }
                seen.insert(pid)
                let cpuNanoseconds = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
                var cpu = 0.0
                if elapsed > 0, let previous = state.lastCPU[pid], cpuNanoseconds >= previous {
                    cpu = Double(cpuNanoseconds - previous) / elapsed * 100
                }
                state.lastCPU[pid] = cpuNanoseconds

                let group = state.groupCache[pid] ?? Self.group(for: pid)
                state.groupCache[pid] = group
                var entry = groups[group.key] ?? ProcessGroup(key: group.key, name: group.name, bundlePath: group.bundle, cpu: 0, memory: 0, pids: [])
                entry.cpu += cpu
                entry.memory += Int64(info.ri_phys_footprint)
                entry.pids.append(pid)
                groups[group.key] = entry
            }
            // Forget exited processes so pid reuse cannot mix up apps.
            state.lastCPU = state.lastCPU.filter { seen.contains($0.key) }
            state.groupCache = state.groupCache.filter { seen.contains($0.key) }
            return (Array(groups.values), Self.systemLoad(&state))
        }
    }

    private static func group(for pid: pid_t) -> (key: String, name: String, bundle: String?) {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? Self.string(buffer) : ""
        // The first ".app/" is the outermost bundle, so helpers (Chrome Helper, XPC services) roll up into their app.
        if let range = path.range(of: ".app/") {
            let bundle = String(path[..<range.lowerBound]) + ".app"
            let name = (FileManager.default.displayName(atPath: bundle) as NSString).deletingPathExtension
            return (bundle, name, bundle)
        }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        var name = Self.string(nameBuffer)
        if name.isEmpty { name = (path as NSString).lastPathComponent }
        if name.isEmpty { name = "pid \(pid)" }
        return ("proc:" + name, name, nil)
    }

    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func systemLoad(_ state: inout State) -> SystemLoad {
        var load = SystemLoad()

        var cpuInfo = host_cpu_load_info()
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if cpuResult == KERN_SUCCESS {
            let ticks = cpuInfo.cpu_ticks
            let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
            let total = busy + UInt64(ticks.2)
            if let last = state.lastHostTicks, total > last.total {
                load.cpu = Double(busy - last.busy) / Double(total - last.total) * 100
            }
            state.lastHostTicks = (busy, total)
        }

        var vm = vm_statistics64()
        var vmSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmSize)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmSize)
            }
        }
        if vmResult == KERN_SUCCESS {
            // vm_statistics counts kernel pages; user and kernel pages are the same size on current Macs.
            let page = Int64(sysconf(_SC_PAGESIZE))
            // Activity Monitor's "Memory Used": app + wired + compressed.
            let app = Int64(vm.internal_page_count) - Int64(vm.purgeable_count)
            load.memoryUsed = (app + Int64(vm.wire_count) + Int64(vm.compressor_page_count)) * page
        }
        load.pressure = currentPressure()
        return load
    }

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public static func currentPressure() -> MemoryPressure {
        var level: Int32 = 1
        var length = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &length, nil, 0) == 0 else { return .normal }
        switch level {
        case 4...: return .critical
        case 2...: return .warning
        default: return .normal
        }
    }
}

/// Warns once when memory is almost full (D-116): checks the kernel's pressure
/// level every minute and stays quiet until it is back to normal.
actor MemoryMonitor {
    private let notifications: NotificationService
    private let macName: @Sendable () -> String
    private let sampler = ProcessSampler()
    private var warned = false
    private var task: Task<Void, Never>?

    init(notifications: NotificationService, macName: @escaping @Sendable () -> String) {
        self.notifications = notifications
        self.macName = macName
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            // Like the storage check, the first one waits for the notification settings.
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func check() async {
        guard shouldWarn(ProcessSampler.currentPressure()) else { return }
        let (groups, _) = sampler.sample()
        let top = groups.filter { $0.bundlePath != nil }.max { $0.memory < $1.memory }
        let culprit = top.map { "\($0.name) (\(ByteCountFormatter.string(fromByteCount: $0.memory, countStyle: .memory)))" }
        await notifications.post(HostAlert(kind: .memoryPressure, sessionId: "", folderName: culprit ?? macName(), detail: macName()))
    }

    /// `true` once each time the pressure becomes critical.
    func shouldWarn(_ pressure: MemoryPressure) -> Bool {
        switch pressure {
        case .critical:
            guard !warned else { return false }
            warned = true
            return true
        case .normal:
            warned = false
            return false
        default:
            return false
        }
    }
}
#endif
