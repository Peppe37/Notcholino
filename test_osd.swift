import Foundation

@_silgen_name("proc_listpids")
func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
func proc_name(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

func getOSDUIHelperPID() -> Int32? {
    var pids = [Int32](repeating: 0, count: 2048)
    let byteCount = proc_listpids(1, 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
    guard byteCount > 0 else { return nil }
    
    var name = [CChar](repeating: 0, count: 256)
    let count = Int(byteCount) / MemoryLayout<Int32>.size
    
    var highestPID: Int32?
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

if let pid = getOSDUIHelperPID() {
    print("FOUND OSDUIHelper: \(pid)")
} else {
    print("NOT FOUND")
}
