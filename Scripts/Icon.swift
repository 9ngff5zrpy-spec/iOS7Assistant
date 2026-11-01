import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
 let pixels=size*scale
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
 let context=NSGraphicsContext.current!.cgContext
 context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
 NSColor(calibratedRed:0.16,green:0.32,blue:0.68,alpha:1).setFill()
 NSBezierPath(roundedRect:NSRect(x:36,y:36,width:952,height:952),xRadius:210,yRadius:210).fill()
 NSColor.white.setStroke()
 let phone=NSBezierPath(roundedRect:NSRect(x:300,y:160,width:424,height:704),xRadius:65,yRadius:65)
 phone.lineWidth=26;phone.stroke()
 let home=NSBezierPath(ovalIn:NSRect(x:488,y:188,width:48,height:48));home.lineWidth=12;home.stroke()
 let text="7" as NSString
 let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:420,weight:.light),.foregroundColor:NSColor.white]
 let bounds=text.size(withAttributes:attributes)
 text.draw(at:NSPoint(x:512-bounds.width/2,y:295),withAttributes:attributes)
 NSGraphicsContext.restoreGraphicsState()
 let suffix=scale==2 ? "@2x" : ""
 try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
 }
}
