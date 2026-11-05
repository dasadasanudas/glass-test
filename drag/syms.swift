import AppKit
import Foundation

// syms: every SF Symbol name the OS ships, drawn into a PDF (one page per symbol, vector), plus a shortlist at every weight and scale.
_ = NSApplication.shared
let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let plistPath = args.count > 2 ? args[2] : ""
let short: [String] = ["chevron.left", "chevron.right", "chevron.down", "chevron.up.chevron.down", "square.grid.2x2", "list.bullet", "rectangle.split.3x1", "squares.below.rectangle", "rectangle.grid.1x2", "square.grid.3x1.below.line.grid.1x2", "rectangle.3.group", "square.grid.3x2", "rectangle.grid.3x2", "square.and.arrow.up", "tag", "ellipsis", "ellipsis.circle", "magnifyingglass", "plus", "sidebar.left", "sidebar.leading", "sidebar.squares.left", "square.on.square", "square.on.square.dashed", "folder.badge.plus", "square.and.pencil", "textformat", "textformat.alt", "checklist", "checklist.unchecked", "tablecells", "paperclip", "trash", "list.bullet.rectangle", "text.badge.plus", "list.bullet.indent", "list.bullet.badge.plus", "list.bullet.clipboard", "rectangle.stack", "rectangle.on.rectangle", "square.split.2x1", "magnifyingglass.circle", "xmark", "square.and.arrow.down", "arrow.clockwise", "lock", "shield.lefthalf.filled", "info.circle", "eye", "printer", "archivebox", "doc.on.doc", "plus.square.on.square", "pencil", "folder", "macwindow", "macwindow.badge.plus", "eject", "arrowshape.turn.up.right", "arrow.uturn.backward", "link", "gearshape", "photo", "square.grid.3x3", "line.3.horizontal.decrease", "line.3.horizontal"]
var all: [String] = []
if let d = NSDictionary(contentsOfFile: plistPath), let s = d["symbols"] as? [String: Any] { all = s.keys.sorted() }
print("names \(all.count) from \(plistPath)")
if all.isEmpty { all = short }

func render(_ names: [String], _ weights: [(String, NSFont.Weight)], _ scales: [(String, NSImage.SymbolScale)], _ pt: CGFloat, _ file: String, _ index: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(file) as CFURL
    var box = CGRect(x: 0, y: 0, width: 64, height: 64)
    guard let ctx = CGContext(url, mediaBox: &box, nil) else { print("no ctx \(file)"); return }
    var lines: [String] = []
    var page = 0
    for n in names {
        guard let base = NSImage(systemSymbolName: n, accessibilityDescription: nil) else { lines.append("0\t\(n)\tMISSING"); continue }
        for (wn, w) in weights {
            for (sn, s) in scales {
                let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: w, scale: s)
                guard let img = base.withSymbolConfiguration(cfg) else { continue }
                let sz = img.size
                var mb = CGRect(x: 0, y: 0, width: ceil(sz.width) + 8, height: ceil(sz.height) + 8)
                let data = NSData(bytes: &mb, length: MemoryLayout<CGRect>.size)
                let info = [kCGPDFContextMediaBox as String: data] as CFDictionary
                ctx.beginPDFPage(info)
                let g = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = g
                img.draw(in: NSRect(x: 4, y: 4, width: sz.width, height: sz.height))
                NSGraphicsContext.restoreGraphicsState()
                ctx.endPDFPage()
                page += 1
                let ar = img.alignmentRect
                lines.append("\(page)\t\(n)\t\(wn)\t\(sn)\t\(sz.width)\t\(sz.height)\t\(ar.origin.x)\t\(ar.origin.y)\t\(ar.size.width)\t\(ar.size.height)")
            }
        }
    }
    ctx.closePDF()
    try? lines.joined(separator: "\n").write(toFile: outDir + "/" + index, atomically: true, encoding: .utf8)
    print("\(file) pages \(page)")
}

let W9: [(String, NSFont.Weight)] = [("ultralight", .ultraLight), ("thin", .thin), ("light", .light), ("regular", .regular), ("medium", .medium), ("semibold", .semibold), ("bold", .bold), ("heavy", .heavy), ("black", .black)]
let S3: [(String, NSImage.SymbolScale)] = [("small", .small), ("medium", .medium), ("large", .large)]
render(short, W9, S3, 20, "short.pdf", "short.tsv")
render(all, [("regular", .regular)], [("medium", .medium)], 20, "all_regular.pdf", "all_regular.tsv")
print("done")
