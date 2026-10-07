import Foundation
import CoreGraphics

@_silgen_name("DisplayServicesGetLinearBrightness")
func DisplayServicesGetLinearBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

var b: Float = 0.0
DisplayServicesGetLinearBrightness(CGMainDisplayID(), &b)
print("Brightness: \(b)")
