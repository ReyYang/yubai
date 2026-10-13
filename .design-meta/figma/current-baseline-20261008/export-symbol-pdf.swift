import AppKit
import Foundation
final class SymbolView:NSView {
 let symbol:String
 init(_ s:String){symbol=s;super.init(frame:NSRect(x:0,y:0,width:24,height:24))}
 required init?(coder:NSCoder){fatalError()}
 override func draw(_ dirtyRect:NSRect){
  guard let image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:20,weight:.regular)) else{return}
  let w=image.size.width,h=image.size.height,scale=min(20/w,20/h)
  image.draw(in:NSRect(x:(24-w*scale)/2,y:(24-h*scale)/2,width:w*scale,height:h*scale))
 }
}
let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let map=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("sf-glyph-map.json"))) as! [String:[String:String]]
let out=base.appendingPathComponent("sf-native-pdf",isDirectory:true);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
for (key,item) in map {let v=SymbolView(item["name"]!);let data=v.dataWithPDF(inside:v.bounds);try data.write(to:out.appendingPathComponent(key+".pdf"));print(key,data.count)}
