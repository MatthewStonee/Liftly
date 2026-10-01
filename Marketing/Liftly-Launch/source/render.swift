import AppKit
import AVFoundation
import CoreGraphics
import ImageIO

// Offline renderer. Native Apple frameworks only. Coordinates use a 1080 x 1920 canvas.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Marketing/Liftly-Launch", isDirectory: true)
let previewOnly = CommandLine.arguments.contains("--preview")
let width = 1080, height = 1920, fps: Int32 = 30
let duration = 24.0
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let blue = NSColor(srgbRed: 0.06, green: 0.58, blue: 1, alpha: 1)
let pale = NSColor(srgbRed: 0.66, green: 0.79, blue: 1, alpha: 1)
let white = NSColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
let muted = NSColor(srgbRed: 0.55, green: 0.61, blue: 0.72, alpha: 1)
func image(_ name: String) -> CGImage {
    let url = root.appendingPathComponent("assets/" + name)
    guard let s = CGImageSourceCreateWithURL(url as CFURL,nil), let i = CGImageSourceCreateImageAtIndex(s,0,nil) else { fatalError("Missing asset: \(url.path)") }
    return i
}
let icon = image("liftly-icon.png")
let progress = image("progress.png")
let logging = image("log-set.png")

func clamp(_ x: Double) -> Double { min(1,max(0,x)) }
func ease(_ x: Double) -> Double { let v=clamp(x); return 1-pow(1-v,3) }
func smooth(_ x: Double) -> Double { let v=clamp(x); return v*v*(3-2*v) }
func color(_ r: Double,_ g: Double,_ b: Double,_ a: Double=1) -> CGColor { CGColor(colorSpace:cs,components:[r,g,b,a])! }
func rounded(_ c: CGContext,_ r: CGRect,_ radius: Double,_ fill: CGColor, stroke: CGColor?=nil, line: Double=1) {
    c.addPath(CGPath(roundedRect:r,cornerWidth:radius,cornerHeight:radius,transform:nil)); c.setFillColor(fill)
    if let s=stroke { c.setStrokeColor(s); c.setLineWidth(line); c.drawPath(using:.fillStroke) } else { c.fillPath() }
}
func bitmap(_ c: CGContext,_ im: CGImage,_ r: CGRect,_ alpha: Double=1) {
    c.saveGState(); c.setAlpha(alpha); c.translateBy(x:r.minX,y:r.maxY); c.scaleBy(x:1,y:-1); c.draw(im,in:CGRect(x:0,y:0,width:r.width,height:r.height)); c.restoreGState()
}
func txt(_ text: String,_ x: Double,_ y: Double,_ size: Double,_ weight: NSFont.Weight = .bold,_ col: NSColor = white, width: Double=920, align: NSTextAlignment = .left, tracking: Double = -1.5) {
    let p=NSMutableParagraphStyle(); p.alignment=align; p.lineBreakMode = .byWordWrapping; p.lineSpacing = -3
    let font=NSFont.systemFont(ofSize:size,weight:weight)
    let a:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:col,.paragraphStyle:p,.kern:tracking]
    NSAttributedString(string:text,attributes:a).draw(in:NSRect(x:x,y:y,width:width,height:size*3.8))
}
func line(_ c: CGContext,_ a: CGPoint,_ b: CGPoint,_ color: CGColor,_ w: Double) { c.setStrokeColor(color); c.setLineWidth(w); c.move(to:a); c.addLine(to:b); c.strokePath() }
func glow(_ c: CGContext,_ x: Double,_ y: Double,_ radius: Double,_ opacity: Double) {
    let colors=[color(0.04,0.32,0.9,opacity),color(0.025,0.15,0.5,0)] as CFArray
    let grad=CGGradient(colorsSpace:cs,colors:colors,locations:[0,1])!
    c.drawRadialGradient(grad,startCenter:CGPoint(x:x,y:y),startRadius:0,endCenter:CGPoint(x:x,y:y),endRadius:radius,options:[])
}
func background(_ c: CGContext,_ t: Double) {
    let grad=CGGradient(colorsSpace:cs,colors:[color(0.025,0.035,0.09),color(0.006,0.011,0.026)] as CFArray,locations:[0,1])!
    c.drawLinearGradient(grad,start:CGPoint(x:0,y:0),end:CGPoint(x:1080,y:1920),options:[])
    glow(c,850+80*sin(t*0.2),750,850,0.22)
    glow(c,60,1500+60*cos(t*0.25),700,0.15)
    // Fine registration lines, kept behind the content.
    for x in stride(from:90.0,through:990.0,by:180.0) {
        for y in stride(from:140.0,through:1820.0,by:140.0) {
            c.setFillColor(color(0.5,0.65,1,0.12)); c.fillEllipse(in:CGRect(x:x,y:y,width:2,height:2))
        }
    }
}
func header(_ c: CGContext,_ number: String,_ label: String) {
    bitmap(c,icon,CGRect(x:86,y:100,width:48,height:48))
    txt("Liftly",151,104,34,.semibold,white,width:230,tracking:-1)
    txt(number + " / " + label,550,113,20,.medium,muted,width:442,align:.right,tracking:2)
    line(c,CGPoint(x:90,y:176),CGPoint(x:990,y:176),color(0.4,0.55,0.8,0.22),1)
}
func footer(_ c: CGContext,_ current: Int,_ phase: Double,_ label: String = "ACTUAL APP · DEMO DATA") {
    for i in 0..<3 {
        rounded(c,CGRect(x:90+Double(i)*67,y:1789,width:52,height:4),2,color(0.26,0.33,0.46,0.8))
        if i<current { rounded(c,CGRect(x:90+Double(i)*67,y:1789,width:52,height:4),2,blue.cgColor) }
        if i==current { rounded(c,CGRect(x:90+Double(i)*67,y:1789,width:max(2,52*clamp(phase)),height:4),2,blue.cgColor) }
    }
    txt(label,490,1779,18,.medium,muted,width:500,align:.right,tracking:2)
}
func phone(_ c: CGContext,_ im: CGImage,x:Double,y:Double,w:Double,angle:Double=0,alpha:Double=1) {
    let h=w*Double(im.height)/Double(im.width)
    c.saveGState(); c.setAlpha(alpha); c.translateBy(x:x+w/2,y:y+h/2); c.rotate(by:angle); c.translateBy(x:-w/2,y:-h/2)
    c.saveGState(); c.setShadow(offset:CGSize(width:0,height:26),blur:60,color:color(0,0,0,0.7))
    rounded(c,CGRect(x:-12,y:-12,width:w+24,height:h+24),w*0.112,color(0.055,0.064,0.08),stroke:color(0.45,0.56,0.7,0.48),line:2)
    c.restoreGState()
    c.saveGState(); c.addPath(CGPath(roundedRect:CGRect(x:0,y:0,width:w,height:h),cornerWidth:w*0.095,cornerHeight:w*0.095,transform:nil)); c.clip()
    bitmap(c,im,CGRect(x:0,y:0,width:w,height:h)); c.restoreGState()
    rounded(c,CGRect(x:w*0.345,y:12,width:w*0.31,height:w*0.073),w*0.037,color(0.005,0.008,0.015))
    rounded(c,CGRect(x:-17,y:h*0.19,width:5,height:75),2,color(0.2,0.25,0.32))
    rounded(c,CGRect(x:w+12,y:h*0.25,width:5,height:105),2,color(0.2,0.25,0.32))
    c.restoreGState()
}
func reveal(_ c: CGContext,_ p: Double,_ body: ()->Void) {
    c.saveGState(); c.setAlpha(ease(p)); c.translateBy(x:0,y:45*(1-ease(p))); body(); c.restoreGState()
}
func intro(_ c: CGContext,_ t:Double) {
    let e=ease(t/0.8)
    txt("YOUR TRAINING. IN FOCUS.",90,180,23,.semibold,pale,width:900,align:.center,tracking:4)
    c.saveGState(); c.setAlpha(0.5*e)
    for i in 0..<3 {
        let r=290+Double(i)*66+16*sin(t*0.75)
        c.setStrokeColor(color(0.20,0.47,0.96,0.19-Double(i)*0.045)); c.setLineWidth(1.5)
        c.strokeEllipse(in:CGRect(x:540-r,y:740-r,width:r*2,height:r*2))
    }
    c.restoreGState()
    let size=420+20*e
    bitmap(c,icon,CGRect(x:540-size/2,y:510+70*(1-e)-8*sin(t),width:size,height:size),e)
    reveal(c,(t-0.35)/0.7) { txt("Make every",70,1110,111,.bold,white,width:940,align:.center); txt("set count.",70,1230,111,.bold,blue,width:940,align:.center) }
    reveal(c,(t-0.8)/0.7) { txt("PLAN. LOG. PROGRESS.",90,1445,27,.medium,pale,width:900,align:.center,tracking:4) }
    txt("Liftly",90,1705,40,.semibold,white,width:900,align:.center,tracking:-1)
}
struct IconLayer: Decodable { let x,y,width,height,rx:Double; let fill,source:String }
let layers = try! JSONDecoder().decode([IconLayer].self,from:Data(contentsOf:root.appendingPathComponent("assets/dumbbell-layers.json")))
func dumbbell(_ c:CGContext,_ t:Double) {
    c.saveGState(); c.translateBy(x:605,y:1260); c.scaleBy(x:0.43,y:0.43)
    for (i,l) in layers.enumerated() {
        let p=ease((t-0.4-Double(i)*0.06)/0.7)
        let displacement=(l.x<400 ? -1.0:1.0)*140*(1-p)
        let hex=UInt32(l.fill.dropFirst(),radix:16)!
        let rgb=color(Double((hex>>16)&255)/255,Double((hex>>8)&255)/255,Double(hex&255)/255,p)
        rounded(c,CGRect(x:l.x+displacement,y:l.y,width:l.width,height:l.height),l.rx,rgb,stroke:color(0.25,0.6,1,0.5*p),line:2)
    }
    c.restoreGState()
}
func planScene(_ c: CGContext,_ t:Double) {
    header(c,"01","PLAN")
    reveal(c,t/0.65) {
        txt("Your plan.",90,226,101,.bold); txt("Your pace.",90,337,101,.bold,blue)
        txt("Build workout days around you.",94,466,33,.regular,pale,tracking:-0.6)
    }
    let titles=["Programs","Workout days","Exercises"]
    let details=["A structure for your training.","Organize your weekly split.","Set your reps and target weight."]
    for i in 0..<3 {
        let p=ease((t-0.24-Double(i)*0.2)/0.65)
        c.saveGState(); c.setAlpha(p); c.translateBy(x:50*(1-p),y:0)
        let y=660+Double(i)*225
        txt(String(format:"%02d",i+1),94,y,62,.light,blue,width:145,tracking:-2)
        txt(titles[i],275,y,57,.semibold,white,width:710,tracking:-1.6)
        txt(details[i],279,y+87,29,.regular,pale,width:700,tracking:-0.3)
        line(c,CGPoint(x:277,y:y+165),CGPoint(x:982,y:y+165),color(0.35,0.49,0.7,0.27),1)
        c.restoreGState()
    }
    dumbbell(c,t)
    reveal(c,(t-1.1)/0.65) {
        txt("BUILT AROUND YOU.",94,1480,23,.medium,pale,width:510,tracking:3)
        txt("One workout at a time.",94,1540,31,.regular,white,width:550,tracking:-0.5)
    }
    footer(c,0,t/5,"WORKOUT PROGRAMMING")
}
func logScene(_ c: CGContext,_ t:Double) {
    header(c,"02","LOG")
    reveal(c,t/0.6) {
        txt("Log it.",90,226,101,.bold); txt("Keep moving.",90,337,101,.bold,blue)
        txt("Weight. Reps. Done.",94,466,33,.regular,pale,tracking:-0.6)
    }
    let e=ease((t-0.1)/0.85)
    phone(c,logging,x:275+25*(1-e),y:578+110*(1-e)-10*t/5,w:530,angle:0.024-0.005*t,alpha:e)
    footer(c,1,t/5)
}
func progressScene(_ c: CGContext,_ t:Double) {
    header(c,"03","PROGRESS")
    reveal(c,t/0.6) {
        txt("See your",90,226,101,.bold); txt("strength grow.",90,337,101,.bold,blue)
        txt("Charts. History. Personal records.",94,466,33,.regular,pale,tracking:-0.6)
    }
    let e=ease((t-0.1)/0.85)
    let zoom=smooth((t-2.3)/2.5)
    // Gentle push toward the genuine metric and chart content.
    phone(c,progress,x:275-zoom*20,y:578+95*(1-e)-zoom*45,w:530+zoom*40,angle:-0.02+0.005*t,alpha:e)
    footer(c,2,t/6)
}
func outro(_ c: CGContext,_ t:Double) {
    let e=ease(t/0.75)
    glow(c,540,775,720,0.22)
    bitmap(c,icon,CGRect(x:394,y:465+60*(1-e),width:292,height:292),e)
    reveal(c,(t-0.14)/0.7) { txt("Liftly",90,825,150,.bold,white,width:900,align:.center,tracking:-6) }
    reveal(c,(t-0.38)/0.75) {
        txt("Make every set count.",90,1060,56,.semibold,white,width:900,align:.center,tracking:-1.8)
        txt("Your training. Your progress.",90,1154,32,.regular,pale,width:900,align:.center,tracking:-0.5)
    }
    reveal(c,(t-0.7)/0.7) {
        line(c,CGPoint(x:445,y:1340),CGPoint(x:635,y:1340),blue.cgColor,3)
        txt("BUILT FOR IPHONE",90,1400,22,.medium,muted,width:900,align:.center,tracking:4)
    }
}
func frame(_ c: CGContext,_ time:Double) {
    c.saveGState(); c.translateBy(x:0,y:Double(height)); c.scaleBy(x:1,y:-1)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:true)
    c.interpolationQuality = .high
    background(c,time)
    let starts=[0.0,4,9,14,20]
    let index=starts.lastIndex(where:{$0<=time}) ?? 0
    let local=time-starts[index]
    // A fast optical fade prevents abrupt changes while leaving the copy readable.
    c.saveGState(); c.setAlpha(index==0 ? 1 : smooth(local/0.24))
    switch index { case 0:intro(c,local); case 1:planScene(c,local); case 2:logScene(c,local); case 3:progressScene(c,local); default:outro(c,local) }
    c.restoreGState()
    if index<4 {
        let until=starts[index+1]-time
        if until<0.18 { c.setFillColor(color(0.015,0.025,0.06,(1-until/0.18)*0.85)); c.fill(CGRect(x:0,y:0,width:1080,height:1920)) }
    }
    if time>23.65 { c.setFillColor(color(0,0,0,smooth((time-23.65)/0.35))); c.fill(CGRect(x:0,y:0,width:1080,height:1920)) }
    NSGraphicsContext.restoreGraphicsState(); c.restoreGState()
}
func png(_ t:Double,_ name:String) {
    let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    frame(c,t)
    let dest=CGImageDestinationCreateWithURL(root.appendingPathComponent("review/"+name).asCFURL, "public.png" as CFString,1,nil)!
    CGImageDestinationAddImage(dest,c.makeImage()!,nil); CGImageDestinationFinalize(dest)
}
extension URL { var asCFURL: CFURL { self as CFURL } }
for (t,n) in [(2.2,"01-intro.png"),(6.5,"02-plan.png"),(11.5,"03-log.png"),(17.0,"04-progress.png"),(22.3,"05-outro.png")] { png(t,n) }
if previewOnly { print("Preview frames ready"); exit(0) }
let output=root.appendingPathComponent("liftly-silent.mp4")
try? FileManager.default.removeItem(at:output)
let writer=try AVAssetWriter(outputURL:output,fileType:.mp4)
let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:12_000_000,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,AVVideoMaxKeyFrameIntervalKey:60],AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]])
input.expectsMediaDataInRealTime=false
let adapter=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime:.zero)
for f in 0..<Int(duration*Double(fps)) {
    autoreleasepool {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.002) }
        var optional:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil,adapter.pixelBufferPool!,&optional)
        let buffer=optional!; CVPixelBufferLockBaseAddress(buffer,[])
        let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:cs,bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
        frame(ctx,Double(f)/Double(fps)); CVPixelBufferUnlockBaseAddress(buffer,[])
        if !adapter.append(buffer,withPresentationTime:CMTime(value:Int64(f),timescale:fps)) { fatalError("Encoding failed: \(String(describing:writer.error))") }
    }
    if f%120==0 { print("Rendered \(f)/720 frames"); fflush(stdout) }
}
input.markAsFinished()
let done=DispatchSemaphore(value:0); writer.finishWriting { done.signal() }; done.wait()
guard writer.status == .completed else { fatalError("Video failed: \(String(describing:writer.error))") }
print("Silent master complete")
