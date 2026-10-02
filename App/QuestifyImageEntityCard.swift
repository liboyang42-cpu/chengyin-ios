import SwiftUI

/// Shared merchant/club/topic composition: full-bleed source artwork, a feathered
/// bottom scrim and overlaid text. No outline, copied reference image or invented badge.
struct QuestifyImageEntityCard<Details:View>:View {
    let imageSource:String?
    let title:String
    var subtitle:String?=nil
    var fallbackTitle:LocalizedStringKey="homeFeed.untitled"
    var fallbackSymbol:String="photo"
    var minimumHeight:CGFloat=340
    private let details:()->Details
    @Environment(\.dynamicTypeSize) private var typeSize
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var scrimOpacity:Double { contrast == .increased ? 0.94 : 0.86 }

    init(imageSource:String?,title:String,subtitle:String?=nil,
         fallbackTitle:LocalizedStringKey="homeFeed.untitled",fallbackSymbol:String="photo",
         minimumHeight:CGFloat=340,@ViewBuilder details:@escaping ()->Details) {
        self.imageSource=imageSource;self.title=title;self.subtitle=subtitle
        self.fallbackTitle=fallbackTitle;self.fallbackSymbol=fallbackSymbol
        self.minimumHeight=minimumHeight;self.details=details
    }

    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            Spacer(minLength:120)
            LinearGradient(colors:[.clear,.black.opacity(scrimOpacity)],startPoint:.top,endPoint:.bottom)
                .frame(height:72).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:10) {
                if title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { Text(fallbackTitle).font(.title2.weight(.bold)) }
                else { Text(verbatim:title).font(.title2.weight(.bold)).fixedSize(horizontal:false,vertical:true) }
                if let subtitle,!subtitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Text(verbatim:subtitle).font(.subheadline)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                        .foregroundStyle(.white.opacity(0.92))
                }
                details().font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth:.infinity,alignment:.leading)
            // A strong scrim sits directly behind every text row, including large text.
            .background(LinearGradient(colors:[.black.opacity(scrimOpacity),.black.opacity(0.94)],startPoint:.top,endPoint:.bottom))
        }
        .frame(maxWidth:.infinity,minHeight:minimumHeight,alignment:.bottomLeading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment:.topTrailing) {
                    Color(red:0.16,green:0.17,blue:0.20)
                    if let url=QuestifyCardArtwork.safeURL(imageSource) {
                        AsyncImage(url:url,transaction:Transaction(animation:reduceMotion ? nil : QuestifyMotion.content)) { phase in
                            if let image=phase.image {
                                image.resizable().scaledToFill().transition(.opacity)
                            } else { placeholder }
                        }
                        .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                    } else { placeholder }
                }
                .frame(width:geometry.size.width,height:geometry.size.height)
            }.accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
        .contentShape(RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    private var placeholder:some View {
        Image(systemName:fallbackSymbol).font(.system(size:48,weight:.light))
            .foregroundStyle(.white.opacity(0.2)).padding(28)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing)
            .accessibilityHidden(true)
    }
}

/// Photo-card metadata retains a spoken label and does not depend on color for meaning.
struct QuestifyImageEntityMetadata:View {
    let label:LocalizedStringKey
    let value:String
    let systemImage:String
    var body:some View {
        Label { Text(verbatim:value).fixedSize(horizontal:false,vertical:true) } icon: { Image(systemName:systemImage).accessibilityHidden(true) }
            .foregroundStyle(.white.opacity(0.92))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(Text(label)+Text(verbatim:": "+value))
    }
}
