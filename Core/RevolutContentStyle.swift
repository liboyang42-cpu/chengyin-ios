/// 内容层唯一视觉契约。以后各页只引用本文件，不另写颜色、圆角或字号阶梯。
/// 大数字或标题、安静的次级说明、内嵌分组行、单一强调色、均匀留白、系统字号。
/// 导航栏与 sheet 仍交给系统。不画玻璃、渐变、发光、表情图标或自定义控件。
#if canImport(SwiftUI)
import SwiftUI

public enum RevolutContentStyle {
    /// 全内容层共用的均匀留白。
    public static let spacing: CGFloat = 16

    public static let figure: Font = .largeTitle
    public static let title: Font = .title
    public static let quiet: Font = .subheadline
    public static let row: Font = .body

    public static let primary: Color = .primary
    public static let secondary: Color = .secondary
    /// 唯一强调色。沿用系统 accentColor，不在页面里另写色值。
    public static let accent: Color = .accentColor
}

/// 大数字配一行安静的次级说明。只排文字和间距。标题用同一套字号常量。
public struct RevolutAmountView: View {
    public let figure: String
    public let label: String

    public init(figure: String, label: String) {
        self.figure = figure
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RevolutContentStyle.spacing) {
            Text(verbatim: figure)
                .font(RevolutContentStyle.figure)
                .foregroundColor(RevolutContentStyle.primary)
            Text(verbatim: label)
                .font(RevolutContentStyle.quiet)
                .foregroundColor(RevolutContentStyle.secondary)
        }
    }
}

/// 内嵌分组行：左侧标题、右侧说明，间距与左右留白同一数值。不画底色或圆角。
public struct RevolutInsetRow: View {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RevolutContentStyle.spacing) {
            Text(verbatim: title)
                .font(RevolutContentStyle.row)
                .foregroundColor(RevolutContentStyle.primary)
            Spacer(minLength: RevolutContentStyle.spacing)
            Text(verbatim: value)
                .font(RevolutContentStyle.quiet)
                .foregroundColor(RevolutContentStyle.secondary)
        }
        .padding(RevolutContentStyle.spacing)
    }
}
#endif
