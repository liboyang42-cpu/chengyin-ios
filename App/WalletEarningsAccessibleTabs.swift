import SwiftUI
import UIKit

/// A native segmented control with real 44pt segment bounds, not only outer SwiftUI padding.
@MainActor struct WalletEarningsAccessibleTabs: UIViewRepresentable {
    let tab: WalletEarningsTabHold.Tab
    let select: (WalletEarningsTabHold.Tab) -> Void
    @Environment(\.locale) private var locale

    func makeUIView(context: Context) -> WalletEarningsSegmentedControl {
        WalletEarningsSegmentedControl(items: ["", ""])
    }
    func updateUIView(_ control: WalletEarningsSegmentedControl, context: Context) {
        control.setTitle(String(localized: LocalizedStringResource("wallet.earnings.tab.income", table: "WalletEarningsOverview", locale: locale)), forSegmentAt: 0)
        control.setTitle(String(localized: LocalizedStringResource("wallet.earnings.tab.organizer", table: "WalletEarningsOverview", locale: locale)), forSegmentAt: 1)
        control.selectedSegmentIndex = tab == .income ? 0 : 1
        control.onSelect = { select($0 == 0 ? .income : .organizer) }
        control.refreshAccessibility()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WalletEarningsSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 44)
    }
}

@MainActor final class WalletEarningsSegmentedControl: UISegmentedControl {
    var onSelect: ((Int) -> Void)?
    private var segments: [WalletEarningsSegmentAccessibility] = []
    override init(items: [Any]?) {
        super.init(items: items)
        isAccessibilityElement = false
        self.accessibilityIdentifier = "wallet.earnings.tabs"
        addTarget(self, action: #selector(changed), for: .valueChanged)
        segments = (0..<2).map { WalletEarningsSegmentAccessibility(control: self, index: $0) }
        accessibilityElements = segments
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(44, size.height))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        refreshAccessibility()
    }
    @objc private func changed() {
        refreshAccessibility()
        onSelect?(selectedSegmentIndex)
    }
    func activateSegment(_ index: Int) -> Bool {
        guard isEnabled, isEnabledForSegment(at: index) else { return false }
        selectedSegmentIndex = index
        sendActions(for: .valueChanged)
        return true
    }
    func refreshAccessibility() {
        for (index, element) in segments.enumerated() {
            element.accessibilityLabel = titleForSegment(at: index)
            if index == 0 { element.accessibilityIdentifier = "wallet.earnings.tab.income" }
            else { element.accessibilityIdentifier = "wallet.earnings.tab.organizer" }
            element.accessibilityTraits = selectedSegmentIndex == index ? [.button, .selected] : [.button]
            if !isEnabled || !isEnabledForSegment(at: index) { element.accessibilityTraits.insert(.notEnabled) }
            let visualIndex = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 1 - index : index
            element.accessibilityFrameInContainerSpace = CGRect(x: CGFloat(visualIndex) * bounds.width / 2, y: 0,
                                                                 width: bounds.width / 2, height: bounds.height)
        }
    }
}

@MainActor private final class WalletEarningsSegmentAccessibility: UIAccessibilityElement {
    private weak var control: WalletEarningsSegmentedControl?
    private let index: Int
    init(control: WalletEarningsSegmentedControl, index: Int) {
        self.control = control
        self.index = index
        super.init(accessibilityContainer: control)
    }
    override func accessibilityActivate() -> Bool { control?.activateSegment(index) ?? false }
}
