import Foundation
import CoreGraphics
import Testing
@testable import NookCore

@Test func shelfSitsImmediatelyBelowTheMenuBar() {
    let frame = ShelfPlacement.frame(size: CGSize(width: 340, height: 124),
        icon: CGRect(x: 900, y: 958, width: 27, height: 24),
        screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 24)
    #expect(frame.maxY == 952)
    #expect(frame.midX == 913.5)
}

@Test func shelfStaysInsideBothHorizontalDisplayEdges() {
    let screen = CGRect(x: -3440, y: -200, width: 3440, height: 1440)
    for x in [screen.minX, screen.maxX - 27] {
        let frame = ShelfPlacement.frame(size: CGSize(width: 560, height: 124),
            icon: CGRect(x: x, y: screen.maxY - 24, width: 27, height: 24), screen: screen, menuBarHeight: 24)
        #expect(frame.minX >= screen.minX + 6)
        #expect(frame.maxX <= screen.maxX - 6)
        #expect(frame.maxY == screen.maxY - 30)
    }
}

@Test func shelfRespectsANotchedDisplaysMenuBarHeight() {
    let frame = ShelfPlacement.frame(size: CGSize(width: 340, height: 124),
        icon: CGRect(x: 1300, y: 942, width: 27, height: 40),
        screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 40)
    #expect(frame.maxY == 936)
}
