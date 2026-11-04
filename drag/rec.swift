// rec OUT.mov SECONDS: records the main display to H.264 with ScreenCaptureKit (60 fps, cursor shown). Prints timing lines.
import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "/tmp/rec.mov"
let secs = args.count > 2 ? (Double(args[2]) ?? 10) : 10

final class Rec: NSObject, SCStreamOutput, SCStreamDelegate {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0
    init(url: URL, w: Int, h: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let comp: [String: Any] = [AVVideoAverageBitRateKey: 8_000_000]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h, AVVideoCompressionPropertiesKey: comp])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sb), CMSampleBufferGetImageBuffer(sb) != nil else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            started = true
            print("first frame \(Date().timeIntervalSince1970)")
        }
        if input.isReadyForMoreMediaData { input.append(sb); frames += 1 }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { print("stream error \(error)") }
}

let sem = DispatchSemaphore(value: 0)
var rec: Rec? = nil
var stream: SCStream? = nil
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, err in
    guard let content = content, let d = content.displays.first else { print("no content \(String(describing: err))"); sem.signal(); return }
    let filter = SCContentFilter(display: d, excludingWindows: [])
    let cfg = SCStreamConfiguration()
    cfg.width = d.width
    cfg.height = d.height
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    cfg.showsCursor = true
    cfg.queueDepth = 8
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    do {
        let r = try Rec(url: URL(fileURLWithPath: outPath), w: d.width, h: d.height)
        let s = SCStream(filter: filter, configuration: cfg, delegate: r)
        try s.addStreamOutput(r, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
        rec = r
        stream = s
        s.startCapture { e in print("start \(String(describing: e)) \(Date().timeIntervalSince1970)"); sem.signal() }
    } catch { print("setup error \(error)"); sem.signal() }
}
sem.wait()
if let s = stream, let r = rec {
    Thread.sleep(forTimeInterval: secs)
    let s2 = DispatchSemaphore(value: 0)
    s.stopCapture { _ in s2.signal() }
    _ = s2.wait(timeout: .now() + 5)
    r.input.markAsFinished()
    let s3 = DispatchSemaphore(value: 0)
    r.writer.finishWriting { s3.signal() }
    _ = s3.wait(timeout: .now() + 15)
    print("frames \(r.frames) status \(r.writer.status.rawValue) \(String(describing: r.writer.error))")
}
