// 画面操作の自動テスト用（GitHub の Mac で使う。アプリには含めない）。
// 画面の部品の位置を読み取り（アクセシビリティ）、人と同じようにマウスやキーを動かす。
//   swift scripts/ui-test.swift trusted                     読み取りの許可があるか
//   swift scripts/ui-test.swift pos <bundle id> <名前>      部品の中心の位置（x y）
//   swift scripts/ui-test.swift click <x> <y>
//   swift scripts/ui-test.swift doubleclick <x> <y>
//   swift scripts/ui-test.swift drag <x1> <y1> <x2> <y2>
//   swift scripts/ui-test.swift windows <bundle id>         窓の題名の一覧
//   swift scripts/ui-test.swift move <bundle id> <x> <y> <幅> <高さ>   いちばん手前の窓の位置と大きさを変える
//   swift scripts/ui-test.swift key <キー番号> [cmd]          キーを押す（51 = delete）
//   swift scripts/ui-test.swift press <bundle id> <名前>…    ボタンやメニュー項目を押す（名前はどれか1つが合えばよい）
//   swift scripts/ui-test.swift type <文字>                  文字を打つ
//   swift scripts/ui-test.swift has <bundle id> <文字>…      窓のどこかにその文字を含む表示があるか
//   swift scripts/ui-test.swift dump <bundle id>              手前の窓の部品の一覧（調べる用）
//   swift scripts/ui-test.swift set <bundle id> <文字> <名前>…  入力欄（名前のどれか）に文字を入れる
//   swift scripts/ui-test.swift allow                       ほかのアプリの確認（ローカルネットワーク等）で「許可」を押す
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
    // メニューバーの同じ名前の項目に当たらないよう、まず窓の中を探す（手前の窓から）
    guard let a = app(args[2]) else { print("見つからない"); exit(1) }
    let wins = (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let e = wins.lazy.compactMap({ find($0, args[3]) }).first ?? find(a, args[3]), let c = center(e) else { print("見つからない"); exit(1) }
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
case "move":
    guard let a = app(args[2]), let w = (attr(a, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("窓が無い"); exit(1) }
    var p = CGPoint(x: Double(args[3])!, y: Double(args[4])!), s = CGSize(width: Double(args[5])!, height: Double(args[6])!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
case "key":
    let code = CGKeyCode(Int(args[2])!)
    let flags: CGEventFlags = args.count > 3 && args[3] == "cmd" ? .maskCommand : []
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
case "press":
    guard let a = app(args[2]) else { print("起動していない"); exit(1) }
    let wins = (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    let menubar = attr(a, kAXMenuBarAttribute).map { $0 as! AXUIElement }
    var hit: AXUIElement?
    for name in args[3...] {
        hit = wins.lazy.compactMap { find($0, name) }.first ?? menubar.flatMap { find($0, name) }
        if hit != nil { break }
    }
    guard let e = hit else { print("見つからない"); exit(1) }
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    let enabled = (attr(e, kAXEnabledAttribute) as? Bool).map { $0 ? "使える" : "使えない" } ?? "?"
    print((AXUIElementPerformAction(e, kAXPressAction as CFString) == .success ? "押した" : "押せなかった") + "（\(role)・\(enabled)）")
case "type":
    for ch in args[2].utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            var c = ch
            e?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            e?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }
case "has":
    guard let a = app(args[2]) else { print("起動していない"); exit(1) }
    func contains(_ e: AXUIElement, _ text: String, _ depth: Int = 0) -> Bool {
        if depth > 14 { return false }
        for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let s = attr(e, key) as? String, s.contains(text) { return true }
        }
        return ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).contains { contains($0, text, depth + 1) }
    }
    let wins = (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    let found = args[3...].contains { t in wins.contains { contains($0, t) } }
    print(found ? "ある" : "ない")
    exit(found ? 0 : 1)
case "set":
    guard let a = app(args[2]) else { print("起動していない"); exit(1) }
    let wins = (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    var hit: AXUIElement?
    for name in args[4...] { hit = wins.lazy.compactMap { find($0, name) }.first; if hit != nil { break } }
    guard let e = hit else { print("見つからない"); exit(1) }
    AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    let r = AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, args[3] as CFString)
    print(r == .success ? "入れた" : "入れられなかった")
case "dump":
    guard let a = app(args[2]), let w = (attr(a, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("窓が無い"); exit(1) }
    func walk(_ e: AXUIElement, _ depth: Int) {
        if depth > 12 { return }
        let role = attr(e, kAXRoleAttribute) as? String ?? "?"
        let bits = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute]
            .compactMap { k -> String? in (attr(e, k) as? String).flatMap { $0.isEmpty ? nil : "\(k)=\($0)" } }
        let en = (attr(e, kAXEnabledAttribute) as? Bool).map { $0 ? "" : " [使えない]" } ?? ""
        print(String(repeating: "  ", count: depth) + role + " " + bits.joined(separator: " ") + en)
        for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, depth + 1) }
    }
    walk(w, 0)
case "allow":
    // 試験用サーバー（python）が出させる「ローカルネットワークの許可」などの確認を閉じる
    var pressed = 0
    for running in NSWorkspace.shared.runningApplications {
        let a = AXUIElementCreateApplication(running.processIdentifier)
        for w in (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            for name in ["Allow", "許可"] {
                if let b = find(w, name) {
                    if AXUIElementPerformAction(b, kAXPressAction as CFString) == .success {
                        pressed += 1
                        print("許可を押した: \(running.localizedName ?? "?")")
                    }
                }
            }
        }
    }
    if pressed == 0 { print("確認は出ていない") }
case "windows":
    guard let a = app(args[2]) else { print("起動していない"); exit(1) }
    for w in (attr(a, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { print(attr(w, kAXTitleAttribute) as? String ?? "(題名なし)") }
default:
    print("使い方は先頭のコメントを参照"); exit(2)
}
