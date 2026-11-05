// icons OUTDIR LIST [SIZE]: renders each "name<TAB>path" icon (NSWorkspace icon for a file, or @NSImageName) to an sRGB PNG.
import AppKit
let a = CommandLine.arguments
let out = a[1], list = a[2], S = Int(a.count > 3 ? a[3] : "256") ?? 256
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let text = (try? String(contentsOfFile: list, encoding: .utf8)) ?? ""
for line in text.split(separator: "\n") {
  let p = line.split(separator: "\t", maxSplits: 1).map(String.init); if p.count < 2 { continue }
  var img: NSImage? = nil
  if p[1].hasPrefix("@") { img = NSImage(named: NSImage.Name(String(p[1].dropFirst()))) }
  else if FileManager.default.fileExists(atPath: p[1]) { img = NSWorkspace.shared.icon(forFile: p[1]) }
  guard let im = img else { print("missing \(p[0])"); continue }
  guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  im.draw(in: NSRect(x: 0, y: 0, width: S, height: S), from: .zero, operation: .copy, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  guard let cg = ctx.makeImage() else { continue }
  if let d = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) { try? d.write(to: URL(fileURLWithPath: out + "/" + p[0] + ".png")); print("ok \(p[0])") }
}
