import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreText

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
let cyan = CGColor(red: 0.23, green: 0.87, blue: 0.96, alpha: 1)
let orange = CGColor(red: 1, green: 0.49, blue: 0.18, alpha: 1)
let space = CGColorSpaceCreateDeviceRGB()
let brandDirectory = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil
let variants: [(String, Int)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
for (name, size) in variants + (brandDirectory == nil ? [] : [("brand-mark", 1024)]) {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot create icon") }
    ctx.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    if name != "brand-mark" {
    let bounds = CGRect(x: 72, y: 72, width: 880, height: 880)
    let outline = CGPath(roundedRect: bounds, cornerWidth: 196, cornerHeight: 196, transform: nil)
    ctx.addPath(outline); ctx.setFillColor(CGColor(red: 0.025, green: 0.045, blue: 0.07, alpha: 1)); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(outline); ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.03, green: 0.26, blue: 0.32, alpha: 0.7), CGColor(red: 0.02, green: 0.04, blue: 0.06, alpha: 0)] as CFArray, locations: [0,1])!
    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 512,y: 512), startRadius: 0, endCenter: CGPoint(x: 512,y: 512), endRadius: 440, options: [])
    ctx.restoreGState()
    ctx.addPath(outline); ctx.setStrokeColor(cyan.copy(alpha: 0.24)!); ctx.setLineWidth(3); ctx.strokePath()
    }
    for i in 0..<48 {
        let a = Double(i) * .pi / 24
        let r: CGFloat = i % 4 == 0 ? 324 : 335
        ctx.move(to: CGPoint(x: 512+cos(a)*r,y: 512+sin(a)*r))
        ctx.addLine(to: CGPoint(x: 512+cos(a)*349,y: 512+sin(a)*349))
    }
    ctx.setStrokeColor(cyan.copy(alpha: 0.6)!); ctx.setLineWidth(5); ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 22, color: cyan.copy(alpha: 0.65))
    ctx.setLineWidth(15); ctx.setStrokeColor(cyan)
    ctx.addArc(center: CGPoint(x: 512,y: 512), radius: 291, startAngle: .pi * 0.10, endAngle: .pi * 1.32, clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(orange); ctx.setShadow(offset: .zero, blur: 22, color: orange.copy(alpha: 0.5))
    ctx.addArc(center: CGPoint(x: 512,y: 512), radius: 291, startAngle: .pi * 1.43, endAngle: .pi * 1.94, clockwise: false); ctx.strokePath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setStrokeColor(cyan.copy(alpha: 0.3)!); ctx.setLineWidth(3)
    ctx.strokeEllipse(in: CGRect(x: 262,y: 262,width: 500,height: 500))
    let points: [CGPoint] = [CGPoint(x: 290,y: 506),CGPoint(x: 405,y: 506),CGPoint(x: 465,y: 625),CGPoint(x: 530,y: 382),CGPoint(x: 590,y: 506),CGPoint(x: 734,y: 506)]
    ctx.addLines(between: points); ctx.setLineJoin(.round); ctx.setLineCap(.round)
    ctx.setStrokeColor(orange); ctx.setLineWidth(28)
    ctx.setShadow(offset: .zero, blur: 25, color: orange.copy(alpha: 0.5)); ctx.strokePath()
    let image = ctx.makeImage()!
    let url: URL
    if name == "brand-mark", let brandDirectory {
        url = URL(fileURLWithPath: brandDirectory).appendingPathComponent("logo-mark.png")
    } else {
        url = URL(fileURLWithPath: destination).appendingPathComponent("icon_\(name).png")
    }
    let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output,image,nil)
    precondition(CGImageDestinationFinalize(output))
}

if let brandDirectory {
    let directory = URL(fileURLWithPath: brandDirectory)
    let icon = URL(fileURLWithPath: destination).appendingPathComponent("icon_512x512@2x.png")
    let master = directory.appendingPathComponent("app-icon-1024.png")
    if FileManager.default.fileExists(atPath: master.path) { try FileManager.default.removeItem(at: master) }
    try FileManager.default.copyItem(at: icon, to: master)
    let ctx = CGContext(data: nil, width: 1600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.025, green: 0.043, blue: 0.065, alpha: 1))
    ctx.fill(CGRect(x: 0,y: 0,width: 1600,height: 400))
    let source = CGImageSourceCreateWithURL(directory.appendingPathComponent("logo-mark.png") as CFURL,nil)!
    let mark = CGImageSourceCreateImageAtIndex(source,0,nil)!
    ctx.draw(mark,in: CGRect(x: 16,y: 16,width: 368,height: 368))
    func line(_ string: String, _ size: CGFloat, _ color: CGColor, _ y: CGFloat, bold: Bool) {
        let font = CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color, NSAttributedString.Key(kCTKernAttributeName as String): bold ? 2 : 3]
        let text = NSAttributedString(string: string, attributes: attributes)
        ctx.textPosition = CGPoint(x: 390,y: y)
        CTLineDraw(CTLineCreateWithAttributedString(text),ctx)
    }
    line("PC HEALTH REMOTE",66,CGColor(red: 0.86,green: 0.94,blue: 0.96,alpha: 1),195,bold: true)
    line("SYSTEM TELEMETRY / MAC COMPANION",22,CGColor(red: 0.48,green: 0.62,blue: 0.69,alpha: 1),146,bold: false)
    let output = CGImageDestinationCreateWithURL(directory.appendingPathComponent("logo-lockup.png") as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(output,ctx.makeImage()!,nil)
    precondition(CGImageDestinationFinalize(output))
}
