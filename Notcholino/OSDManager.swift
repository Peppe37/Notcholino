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
    
    func startSuppressing() {
        guard !isSuppressing else { return }
        isSuppressing = true
        
        task = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                let currentPID = self.getOSDUIHelperPID()
                
                if let pid = currentPID, pid != self.lastSuspendedPID {
                    kill(pid, SIGSTOP)
                    self.lastSuspendedPID = pid
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    continue
                }
                
                let intervalNs: UInt64
                if currentPID == nil {
                    intervalNs = 1_000_000_000 // 1s
                } else {
                    intervalNs = 500_000_000 // 500ms
                }
                
                try? await Task.sleep(nanoseconds: intervalNs)
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
