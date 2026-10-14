import Foundation
import Darwin

@_silgen_name("proc_listpids")
func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

final class OSDManager {
    static let shared = OSDManager()
    
    private var isSuppressing = false
    private var task: Task<Void, Never>?
    private var lastSuspendedPID: pid_t = -1
    
    private func getOSDUIHelperPID() -> pid_t? {
        var pids = [pid_t](repeating: 0, count: 2048)
        let byteCount = proc_listpids(1, 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return nil }
        
        var name = [CChar](repeating: 0, count: 256)
        let count = Int(byteCount) / MemoryLayout<pid_t>.size
        
        var highestPID: pid_t?
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            if proc_name(pid, &name, 256) > 0 {
                let procName = String(cString: name)
                if procName == "OSDUIHelper" {
                    if highestPID == nil || pid > highestPID! {
                        highestPID = pid
                    }
                }
            }
        }
        return highestPID
    }
    
    /// Suspends the system volume/brightness HUD helper.
    /// It only appears when a volume or brightness key is pressed, so instead of scanning every process
    /// all the time we look for it right now and then in short bursts after each key press (`suppressNow()`).
    func startSuppressing() {
        guard !isSuppressing else { return }
        isSuppressing = true
        suppressNow()
    }

    /// Looks for a new OSDUIHelper and suspends it. Call after a volume/brightness key press.
    func suppressNow() {
        guard isSuppressing else { return }
        task?.cancel()
        task = Task.detached(priority: .background) { [weak self] in
            // ~50 ms apart for ~2 s: the helper is (re)launched by the system right after the key press
            for _ in 0..<40 {
                guard let self, !Task.isCancelled else { return }
                if let pid = self.getOSDUIHelperPID(), pid != self.lastSuspendedPID {
                    kill(pid, SIGSTOP)
                    self.lastSuspendedPID = pid
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func stopSuppressing() {
        guard isSuppressing else { return }
        isSuppressing = false
        task?.cancel()
        task = nil
        
        if lastSuspendedPID > 0 {
            kill(lastSuspendedPID, SIGCONT)
            lastSuspendedPID = -1
        }
    }
}
