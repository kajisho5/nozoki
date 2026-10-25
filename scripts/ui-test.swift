// 画面操作の自動テスト用（GitHub の Mac で使う。アプリには含めない）。
// 画面の部品の位置を読み取り（アクセシビリティ）、人と同じようにマウスやキーを動かす。
//   swift scripts/ui-test.swift trusted                     読み取りの許可があるか
//   swift scripts/ui-test.swift pos <bundle id> <名前>      部品の中心の位置（x y）
//   swift scripts/ui-test.swift click <x> <y>
//   swift scripts/ui-test.swift doubleclick <x> <y>
//   swift scripts/ui-test.swift drag <x1> <y1> <x2> <y2>
//   swift scripts/ui-test.swift windows <bundle id>         窓の題名の一覧
import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func center(_ e: AXUIElement) -> CGPoint? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
}

func find(_ e: AXUIElement, _ name: String, depth: Int = 0) -> AXUIElement? {
    if depth > 14 { return nil }
    for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, "AXFilename"] {
        if let s = attr(e, key) as? String, s == name || s == (name as NSString).deletingPathExtension { return e }
    }
    for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        if let hit = find(child, name, depth: depth + 1) { return hit }
    }
    return nil
}

func app(_ bundleID: String) -> AXUIElement? {
    guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
    return AXUIElementCreateApplication(a.processIdentifier)
}

func mouse(_ type: CGEventType, _ p: CGPoint, clicks: Int64 = 1) {
    let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
    e?.setIntegerValueField(.mouseEventClickState, value: clicks)
    e?.post(tap: .cghidEventTap)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "trusted":
    print(AXIsProcessTrusted() ? "読み取りの許可あり" : "読み取りの許可なし")
case "pos":
    guard let a = app(args[2]), let e = find(a, args[3]), let c = center(e) else { print("見つからない"); exit(1) }
    print(Int(c.x), Int(c.y))
case "click":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    mouse(.mouseMoved, p); usleep(200_000)
    mouse(.leftMouseDown, p); mouse(.leftMouseUp, p)
case "doubleclick":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    mouse(.mouseMoved, p); usleep(200_000)
    mouse(.leftMouseDown, p, clicks: 1); mouse(.leftMouseUp, p, clicks: 1); usleep(80_000)
    mouse(.leftMouseDown, p, clicks: 2); mouse(.leftMouseUp, p, clicks: 2)
case "drag":
    let a = CGPoint(x: Double(args[2])!, y: Double(args[3])!), b = CGPoint(x: Double(args[4])!, y: Double(args[5])!)
    mouse(.mouseMoved, a); usleep(200_000)
    mouse(.leftMouseDown, a); usleep(300_000)
    for i in 1...40 {
        let t = Double(i) / 40
        mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)); usleep(25_000)
    }
    usleep(800_000)  // Dock のアイコンの上で少し止まる
    mouse(.leftMouseUp, b)
case "windows":
    guard let a = app(args[2]) else { print("起動していない"); exit(1) }
    for w in (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { print(attr(w, kAXTitleAttribute) as? String ?? "(題名なし)") }
default:
    print("使い方は先頭のコメントを参照"); exit(2)
}
