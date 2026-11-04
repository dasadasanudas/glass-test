// AnimRef: AppKit and SwiftUI controls at fixed places for the animation capture (drag/anim.sh drives the mouse).
// Writes <out>/frames.txt: "name x y w h" in global top-left points, plus slider knob rects and the window number.
import AppKit
import SwiftUI

let outDir: String = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()

final class Flipped: NSView { override var isFlipped: Bool { return true } }

struct SegPick: View {
    @State private var sel: Int = 0
    var body: some View {
        Picker("Mode", selection: $sel) {
            Text("Light").tag(0)
            Text("Dark").tag(1)
            Text("Auto").tag(2)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct SlidePick: View {
    @State private var v: Double = 30
    var body: some View {
        Slider(value: $v, in: 0...100)
            .labelsHidden()
            .frame(width: 240)
    }
}

struct TogPick: View {
    @State private var on: Bool = false
    var body: some View {
        Toggle("Switch", isOn: $on)
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize()
    }
}

struct MenuPick: View {
    @State private var sel: Int = 0
    var body: some View {
        Picker("Delay", selection: $sel) {
            Text("Never").tag(0)
            Text("For 1 minute").tag(1)
            Text("For 5 minutes").tag(2)
            Text("For 15 minutes").tag(3)
            Text("For 1 hour").tag(4)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

final class TBDelegate: NSObject, NSToolbarDelegate {
    let segID = NSToolbarItem.Identifier("viewseg")
    var seg: NSSegmentedControl? = nil
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { return [segID] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { return [segID] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let it = NSToolbarItem(itemIdentifier: itemIdentifier)
        let s = NSSegmentedControl(labels: ["Icons", "List", "Columns"], trackingMode: .selectOne, target: nil, action: nil)
        s.selectedSegment = 0
        it.view = s
        it.label = "View"
        seg = s
        return it
    }
}

final class AppDel: NSObject, NSApplicationDelegate {
    var win: NSWindow? = nil
    let tb = TBDelegate()
    var named: [(String, NSView)] = []
    var sliders: [(String, NSSlider)] = []

    func addCtl(_ c: NSControl, _ name: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ cv: NSView) {
        c.sizeToFit()
        var f = c.frame
        if w > 0 { f.size.width = w }
        f.origin = NSPoint(x: x, y: y)
        c.frame = f
        cv.addSubview(c)
        named.append((name, c))
    }

    func addHost<V: View>(_ v: V, _ name: String, _ x: CGFloat, _ y: CGFloat, _ cv: NSView) {
        let h = NSHostingView(rootView: v)
        let s = h.fittingSize
        h.frame = NSRect(x: x, y: y, width: max(s.width, 20), height: max(s.height, 16))
        cv.addSubview(h)
        named.append((name, h))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scr = NSScreen.screens[0].frame
        let W: CGFloat = 760
        let H: CGFloat = 420
        let w = NSWindow(contentRect: NSRect(x: 60, y: scr.height - 110 - H, width: W, height: H),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "AnimRef"
        let toolbar = NSToolbar(identifier: "animref")
        toolbar.delegate = tb
        toolbar.displayMode = .iconOnly
        w.toolbar = toolbar
        w.toolbarStyle = .unified
        let cv = Flipped(frame: NSRect(x: 0, y: 0, width: W, height: H))
        w.contentView = cv

        let s1 = NSSegmentedControl(labels: ["Light", "Dark", "Auto"], trackingMode: .selectOne, target: nil, action: nil)
        s1.selectedSegment = 0
        addCtl(s1, "seg1", 40, 30, 0, cv)
        let s2 = NSSegmentedControl(labels: ["Light", "Dark", "Auto"], trackingMode: .selectOne, target: nil, action: nil)
        s2.segmentStyle = .capsule
        s2.selectedSegment = 0
        addCtl(s2, "seg2", 300, 30, 0, cv)
        addHost(SegPick(), "suiseg", 540, 30, cv)

        let sl1 = NSSlider(value: 30, minValue: 0, maxValue: 100, target: nil, action: nil)
        addCtl(sl1, "slider1", 40, 110, 240, cv)
        let sl2 = NSSlider(value: 25, minValue: 0, maxValue: 100, target: nil, action: nil)
        sl2.numberOfTickMarks = 5
        sl2.allowsTickMarkValuesOnly = true
        addCtl(sl2, "slider2", 340, 110, 240, cv)
        sliders = [("knob1", sl1), ("knob2", sl2)]
        addHost(SlidePick(), "suislider", 40, 170, cv)

        let sw = NSSwitch()
        sw.state = .off
        addCtl(sw, "switch1", 40, 240, 0, cv)
        addHost(TogPick(), "suitoggle", 160, 240, cv)

        let p1 = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24), pullsDown: false)
        p1.addItems(withTitles: ["Never", "For 1 minute", "For 5 minutes", "For 15 minutes", "For 1 hour"])
        p1.selectItem(at: 0)
        addCtl(p1, "pop1", 40, 310, 0, cv)
        let p2 = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 24), pullsDown: true)
        p2.addItems(withTitles: ["Actions", "New Folder", "Get Info", "Rename", "Duplicate", "Move to Trash"])
        addCtl(p2, "pull1", 280, 310, 0, cv)
        addHost(MenuPick(), "suimenu", 520, 310, cv)

        win = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.dump() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { self.dump() }
    }

    func dump() {
        guard let w = win else { return }
        let scrH = NSScreen.screens[0].frame.height
        var out = ""
        func line(_ n: String, _ r: NSRect) {
            let x = Int(r.origin.x.rounded())
            let y = Int((scrH - r.origin.y - r.height).rounded())
            out += "\(n) \(x) \(y) \(Int(r.width.rounded())) \(Int(r.height.rounded()))\n"
        }
        for (n, v) in named {
            if let vw = v.window { line(n, vw.convertToScreen(v.convert(v.bounds, to: nil))) }
        }
        if let s = tb.seg, let sw = s.window { line("tbseg", sw.convertToScreen(s.convert(s.bounds, to: nil))) }
        for (n, sl) in sliders {
            if let c = sl.cell as? NSSliderCell, let sw = sl.window {
                let kr = c.knobRect(flipped: sl.isFlipped)
                line(n, sw.convertToScreen(sl.convert(kr, to: nil)))
            }
        }
        line("window", w.frame)
        out += "winid \(w.windowNumber) 0 0 0\n"
        try? out.write(toFile: outDir + "/frames.txt", atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
let del = AppDel()
app.delegate = del
app.setActivationPolicy(.regular)
app.run()
