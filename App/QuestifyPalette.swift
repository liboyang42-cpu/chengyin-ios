import SwiftUI
import UIKit

/// Brand tint with separate light/dark values; keeps native control semantics and shapes.
enum QuestifyPalette {
    static let accent=Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red:196.0/255,green:181.0/255,blue:253.0/255,alpha:1)
        }
        return UIColor(red:109.0/255,green:40.0/255,blue:217.0/255,alpha:1)
    })
}
