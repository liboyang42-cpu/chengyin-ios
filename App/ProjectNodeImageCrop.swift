import SwiftUI
import UIKit

/// Selected, already sanitized pixels only. Always redraws to exact integer 4:3.
@MainActor final class ProjectNodeImageCrop:ObservableObject {
    struct Draft:Identifiable { let id=UUID();let source:RetainedSelectedImage;let policy:ProjectNodeImageMediaPolicy }
    @Published private(set) var draft:Draft?
    private let current:()->Bool
    init(current:@escaping()->Bool){self.current=current}
    func stage(_ image:RetainedSelectedImage,policy:ProjectNodeImageMediaPolicy){
        guard current(),(try? TemplateImageCropRenderer.validatedImage(image)) != nil else{return};draft = .init(source:image,policy:policy)
    }
    func cancel(_ id:UUID){guard draft?.id==id else{return};draft=nil}
    func invalidate(){draft=nil}
    func confirm(_ id:UUID,horizontal:Double,vertical:Double,zoom:Double)->RetainedSelectedImage?{
        guard current(),let original=draft,original.id==id,
              let result=try? Self.render(original,horizontal:horizontal,vertical:vertical,zoom:zoom),current(),draft?.id==id else{return nil}
        draft=nil;return result
    }
    static func preview(_ draft:Draft,horizontal:Double,vertical:Double,zoom:Double)throws->UIImage{
        let source=try TemplateImageCropRenderer.validatedImage(draft.source)
        return try draw(source,draft:draft,horizontal:horizontal,vertical:vertical,zoom:zoom)
    }
    static func render(_ draft:Draft,horizontal:Double,vertical:Double,zoom:Double)throws->RetainedSelectedImage{
        let output=try preview(draft,horizontal:horizontal,vertical:vertical,zoom:zoom)
        guard let pixels=output.cgImage,pixels.width*3==pixels.height*4 else{throw RetainedImageFailure.invalid}
        for quality in [0.92,0.75,0.55]{
            if let bytes=output.jpegData(compressionQuality:quality),bytes.count<=draft.policy.maximumJPEGBytes,
               let selected=try? RetainedSelectedImage(jpeg:bytes,width:pixels.width,height:pixels.height),draft.policy.permits(selected){return selected}
        }
        throw RetainedImageFailure.invalid
    }
    private static func draw(_ image:UIImage,draft:Draft,horizontal:Double,vertical:Double,zoom:Double)throws->UIImage{
        guard horizontal.isFinite,vertical.isFinite,zoom.isFinite,(0...1).contains(horizontal),(0...1).contains(vertical),(1...4).contains(zoom)else{throw RetainedImageFailure.invalid}
        let sw=Double(draft.source.width),sh=Double(draft.source.height)
        let width=min(sw,sh*4/3)/zoom,height=width*3/4
        let units=Int(min(min(width/4,height/3),Double(draft.policy.maximumDimension)/4).rounded(.down))
        guard units>=1 else{throw RetainedImageFailure.invalid}
        let size=CGSize(width:units*4,height:units*3),x=(sw-width)*horizontal,y=(sh-height)*vertical
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        return UIGraphicsImageRenderer(size:size,format:format).image{context in
            UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:size));context.cgContext.clip(to:CGRect(origin:.zero,size:size));context.cgContext.interpolationQuality = .high
            let sx=size.width/CGFloat(width),sy=size.height/CGFloat(height)
            image.draw(in:CGRect(x:-CGFloat(x)*sx,y:-CGFloat(y)*sy,width:CGFloat(sw)*sx,height:CGFloat(sh)*sy))
        }
    }
}
@MainActor struct ProjectNodeImageCropView:View {
    let draft:ProjectNodeImageCrop.Draft
    let confirm:(UUID,Double,Double,Double)->Void,cancel:(UUID)->Void
    @State private var horizontal=0.5,vertical=0.5,zoom=1.0
    var body:some View{
        VStack(alignment:.leading){
            Text("projectNodeImage.crop",tableName:"ProjectNodeImageAuthor").font(.headline)
            if let preview=try? ProjectNodeImageCrop.preview(draft,horizontal:horizontal,vertical:vertical,zoom:zoom){
                Image(uiImage:preview).resizable().aspectRatio(4.0/3.0,contentMode:.fit).frame(maxHeight:240).accessibilityLabel("image.crop.preview")
                Slider(value:$horizontal,in:0...1).accessibilityLabel("image.crop.horizontal").accessibilityIdentifier("projectNodeImage.crop.horizontal")
                Slider(value:$vertical,in:0...1).accessibilityLabel("image.crop.vertical").accessibilityIdentifier("projectNodeImage.crop.vertical")
                Slider(value:$zoom,in:1...4).accessibilityLabel("image.crop.zoom").accessibilityIdentifier("projectNodeImage.crop.zoom")
                Button{confirm(draft.id,horizontal,vertical,zoom)}label:{Text("projectNodeImage.confirmCrop",tableName:"ProjectNodeImageAuthor")}
                    .accessibilityIdentifier("projectNodeImage.crop.confirm")
            }else{Text("image.retained.failed")}
            Button("action.cancel",role:.cancel){cancel(draft.id)}.accessibilityIdentifier("projectNodeImage.crop.cancel")
        }.buttonStyle(.borderless).onDisappear{cancel(draft.id)}
    }
}
