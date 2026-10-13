import Foundation
import CoreText
import CoreGraphics
let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let map=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("sf-glyph-map.json"))) as! [String:[String:String]]
let out=base.appendingPathComponent("sf-icons",isDirectory:true);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
for (key,item) in map.sorted(by:{$0.key<$1.key}) {
 let font=CTFontCreateWithName(".AppleSystemUIFont" as CFString,22,nil)
 let str=NSAttributedString(string:item["glyph"]!,attributes:[NSAttributedString.Key(kCTFontAttributeName as String):font])
 let line=CTLineCreateWithAttributedString(str)
 let path=CGMutablePath()
 for run in CTLineGetGlyphRuns(line) as! [CTRun] {
  let count=CTRunGetGlyphCount(run);var glyphs=Array(repeating:CGGlyph(0),count:count);var pos=Array(repeating:CGPoint.zero,count:count)
  CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs);CTRunGetPositions(run,CFRange(location:0,length:0),&pos)
  let attributes=CTRunGetAttributes(run) as NSDictionary;let runFont=attributes[kCTFontAttributeName] as! CTFont
  for i in 0..<count {if let gp=CTFontCreatePathForGlyph(runFont,glyphs[i],nil){var tr=CGAffineTransform(translationX:pos[i].x,y:pos[i].y);if let moved=gp.copy(using:&tr){path.addPath(moved)}}}
 }
 let box=path.boundingBoxOfPath
 guard box.width>0,box.height>0 else{print("EMPTY",key);continue}
 var commands=""
 func pt(_ p:CGPoint)->String{String(format:"%.4f %.4f",p.x,p.y)}
 path.applyWithBlock { ep in let e=ep.pointee;switch e.type{case .moveToPoint:commands += "M"+pt(e.points[0]);case .addLineToPoint:commands += "L"+pt(e.points[0]);case .addQuadCurveToPoint:commands += "Q"+pt(e.points[0])+" "+pt(e.points[1]);case .addCurveToPoint:commands += "C"+pt(e.points[0])+" "+pt(e.points[1])+" "+pt(e.points[2]);case .closeSubpath:commands += "Z";@unknown default:break}}
 let scale=min(20/box.width,20/box.height),tx=12-(box.minX+box.width/2)*scale,ty=12+(box.minY+box.height/2)*scale
 let transform=String(format:"matrix(%.6f 0 0 %.6f %.6f %.6f)",scale,-scale,tx,ty)
 let svg="<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\"><path d=\"\(commands)\" transform=\"\(transform)\" fill=\"#1F6657\"/></svg>"
 try svg.write(to:out.appendingPathComponent(key+".svg"),atomically:true,encoding:.utf8)
 print(key,item["name"]!,box.width,box.height)
}
