import CoreGraphics
import Foundation

let a = CommandLine.arguments
func die(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(1)
}
guard a.count >= 2 else { die("usage: input <click|drag|scroll> ...") }

let src = CGEventSource(stateID: .hidSystemState)

func mouse(_ t: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: src, mouseType: t,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

switch a[1] {

case "click":
    guard a.count >= 4, let x = Double(a[2]), let y = Double(a[3]) else { die("click <x> <y>") }
    let p = CGPoint(x: x, y: y)
    mouse(.mouseMoved, p);    usleep(120_000)
    mouse(.leftMouseDown, p); usleep(60_000)
    mouse(.leftMouseUp, p)

case "drag":
    guard a.count >= 6, let x1 = Double(a[2]), let y1 = Double(a[3]),
          let x2 = Double(a[4]), let y2 = Double(a[5]) else { die("drag <x1> <y1> <x2> <y2> [ms]") }
    let ms = a.count > 6 ? (Double(a[6]) ?? 400) : 400
    let steps = 25
    mouse(.mouseMoved, CGPoint(x: x1, y: y1));    usleep(120_000)
    mouse(.leftMouseDown, CGPoint(x: x1, y: y1)); usleep(60_000)
    for i in 1...steps {
        let f = Double(i) / Double(steps)
        mouse(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * f, y: y1 + (y2 - y1) * f))
        usleep(UInt32(ms * 1000 / Double(steps)))
    }
    mouse(.leftMouseUp, CGPoint(x: x2, y: y2))

case "scroll":
    guard a.count >= 5, let x = Double(a[2]), let y = Double(a[3]),
          let lines = Int(a[4]) else { die("scroll <x> <y> <lines>  (+ up, - down)") }
    mouse(.mouseMoved, CGPoint(x: x, y: y)); usleep(120_000)
    let step: Int32 = lines > 0 ? 3 : -3
    for _ in 0..<abs(lines) {
        CGEvent(scrollWheelEvent2Source: src, units: .line,
                wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(25_000)
    }

case "window":
    // Window geometry AND CGWindowID straight from the window server, so the
    // caller can use `screencapture -l<id>`, which captures the window itself
    // even when another app is stacked on top of it. A region capture (-R)
    // grabs whatever pixels are on screen and silently returns the occluding
    // window instead.
    guard a.count >= 3 else { die("window <owner name>") }
    let owner = a[2]
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else {
        die("cannot read window list")
    }
    var best: (id: Int, x: Double, y: Double, w: Double, h: Double)? = nil
    for win in list {
        guard let name = win[kCGWindowOwnerName as String] as? String, name == owner,
              let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
              let id = win[kCGWindowNumber as String] as? Int,
              let b = win[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let w = b["Width"] as? Double, let h = b["Height"] as? Double
        else { continue }
        if best == nil || w * h > best!.w * best!.h {
            best = (id, x, y, w, h)
        }
    }
    guard let f = best else { die("no on-screen window for \(owner)") }
    print("\(f.id) \(Int(f.x)) \(Int(f.y)) \(Int(f.w)) \(Int(f.h))")

default:
    die("unknown subcommand: \(a[1])")
}
