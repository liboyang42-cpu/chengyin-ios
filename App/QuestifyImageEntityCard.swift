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
    var progressiveBlur:ProgressiveBlurParameters?=nil
    var artworkIdentity:QuestifyProgressiveBlurIdentity?=nil
    private let details:()->Details
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var scrimOpacity:Double { contrast == .increased ? 0.94 : 0.86 }

    init(imageSource:String?,title:String,subtitle:String?=nil,
         fallbackTitle:LocalizedStringKey="homeFeed.untitled",fallbackSymbol:String="photo",
         minimumHeight:CGFloat=340,progressiveBlur:ProgressiveBlurParameters?=nil,
         artworkIdentity:QuestifyProgressiveBlurIdentity?=nil,@ViewBuilder details:@escaping ()->Details) {
        self.imageSource=imageSource;self.title=title;self.subtitle=subtitle
        self.fallbackTitle=fallbackTitle;self.fallbackSymbol=fallbackSymbol
        self.minimumHeight=minimumHeight;self.details=details
        self.progressiveBlur=progressiveBlur;self.artworkIdentity=artworkIdentity
    }

    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            Spacer(minLength:120)
            LinearGradient(colors:[.clear,.black.opacity(scrimOpacity)],startPoint:.top,endPoint:.bottom)
                .frame(height:72).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:10) {
                if title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { Text(fallbackTitle).font(.title2.weight(.bold)).lineLimit(nil).fixedSize(horizontal:false,vertical:true) }
                else { Text(verbatim:title).font(.title2.weight(.bold)).lineLimit(nil).fixedSize(horizontal:false,vertical:true) }
                if let subtitle,!subtitle.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    Text(verbatim:subtitle).font(.subheadline).lineLimit(nil)
                        .fixedSize(horizontal:false,vertical:true)
                        .foregroundStyle(.white)
                }
                details().font(.subheadline).lineLimit(nil).fixedSize(horizontal:false,vertical:true)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth:.infinity,alignment:.leading)
            // Opaque backing keeps text contrast independent of artwork and compositing.
            .background(.black)
            .environment(\.colorScheme,.dark)
        }
        .frame(maxWidth:.infinity,minHeight:minimumHeight,alignment:.bottomLeading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment:.topTrailing) {
                    Color(red:0.16,green:0.17,blue:0.20)
                    if let url=QuestifyCardArtwork.safeURL(imageSource) {
                        if let progressiveBlur {
                            if let artworkIdentity, let origin=ObjectCardMediaPolicy.origin(url.absoluteString) {
                                // One load replaces this card's AsyncImage load. The existing safe source
                                // is the sole approved origin; the bounded loader does not follow redirects.
                                QuestifyProgressiveBlurArtwork(url:url,identity:artworkIdentity,
                                    reader:ObjectCardBoundedImageLoader(policy:.init(approvedOrigins:[origin])),
                                    parameters:progressiveBlur,placeholder:{ placeholder })
                                    .frame(width:geometry.size.width,height:geometry.size.height)
                            } else { placeholder }
                        } else {
                            AsyncImage(url:url,transaction:Transaction(animation:reduceMotion ? nil : QuestifyMotion.content)) { phase in
                                if let image=phase.image {
                                    image.resizable().scaledToFill().transition(.opacity)
                                } else { placeholder }
                            }
                            .frame(width:geometry.size.width,height:geometry.size.height).clipped()
                        }
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
            .foregroundStyle(.white)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(Text(label)+Text(verbatim:": "+value))
    }
}

/// Feed-card text shared by home, route and activity lists (mini-program `v2-status`).
/// Missing values return nil so the card leaves them out instead of printing a placeholder.
enum QuestifyCardText {
    /// Like the mini-program, a time without a zone reads as written; an explicit offset shows in local time.
    static func date(_ raw: String?, sourceTimeZone: TimeZone? = nil, locale: Locale, displayTimeZone: TimeZone) -> String? {
        let utc = TimeZone(secondsFromGMT: 0)!
        let zone: TimeZone
        let date: Date
        if let absolute = HomeFeedDate.parse(raw, sourceTimeZone: sourceTimeZone) {
            date = absolute; zone = displayTimeZone
        } else if let wallClock = HomeFeedDate.parse(raw, sourceTimeZone: utc) {
            date = wallClock; zone = utc
        } else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute().locale(locale)
        if calendar.component(.year, from: date) != calendar.component(.year, from: Date()) {
            style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale)
        }
        style.timeZone = zone
        return date.formatted(style)
    }
    static func amount(_ value: Decimal?, locale: Locale) -> String? {
        guard let value, value >= 0 else { return nil }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
    static func metaLine(date: String?, place: String?) -> String? {
        let parts = [date, place?.trimmingCharacters(in: .whitespacesAndNewlines)].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One date · place line and the starting price. `onArtwork` is for text over a cover scrim.
struct QuestifyCardSummary: View {
    let meta: String?
    let price: String?
    var onArtwork = false
    var body: some View {
        if let meta {
            Text(verbatim: meta).font(.subheadline)
                .foregroundStyle(onArtwork ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        if let price {
            Text("playx.finishRoute.priceFrom \(price)").font(.headline).monospacedDigit()
        }
    }
}
