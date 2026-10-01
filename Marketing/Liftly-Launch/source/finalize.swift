import Foundation
import AVFoundation
import ImageIO

@main struct Finalize {
    static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let movie=AVURLAsset(url:root.appendingPathComponent("liftly-silent.mp4"))
        let music=AVURLAsset(url:root.appendingPathComponent("assets/original-score.wav"))
        let composition=AVMutableComposition()
        let video=try await movie.loadTracks(withMediaType:.video)[0]
        let audio=try await music.loadTracks(withMediaType:.audio)[0]
        let duration=try await movie.load(.duration)
        try composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:video,at:.zero)
        try composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:audio,at:.zero)
        let final=root.appendingPathComponent("Liftly-Marketing-Vertical.mp4")
        try? FileManager.default.removeItem(at:final)
        let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
        exporter.shouldOptimizeForNetworkUse=true
        try await exporter.export(to:final,as:.mp4)
        let result=AVURLAsset(url:final)
        let v=try await result.loadTracks(withMediaType:.video)[0]
        let a=try await result.loadTracks(withMediaType:.audio)
        let seconds=try await result.load(.duration).seconds
        let size=try await v.load(.naturalSize)
        let rate=try await v.load(.nominalFrameRate)
        let bytes=try FileManager.default.attributesOfItem(atPath:final.path)[.size] as! NSNumber
        print("Verified: \(seconds)s, \(Int(size.width)) x \(Int(size.height)), \(rate) fps, \(a.count) audio track, \(bytes) bytes")
        // Inspect decoded frames from the actual final movie, not just the renderer.
        let generator=AVAssetImageGenerator(asset:result)
        generator.appliesPreferredTrackTransform=true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        for (index,time) in [2.2,6.5,11.5,17.0,22.3].enumerated() {
            let frame=try await generator.image(at:CMTime(seconds:time,preferredTimescale:600)).image
            let url=root.appendingPathComponent("review/decoded-\(index+1).png")
            let dest=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
            CGImageDestinationAddImage(dest,frame,nil); CGImageDestinationFinalize(dest)
        }
        let report="Duration: \(seconds) seconds\nDimensions: \(Int(size.width)) x \(Int(size.height))\nFrame rate: \(rate) fps\nAudio tracks: \(a.count)\nFile size: \(bytes) bytes\nDecoded preview frames: 5\n"
        try report.write(to:root.appendingPathComponent("review/verification.txt"),atomically:true,encoding:.utf8)
    }
}
