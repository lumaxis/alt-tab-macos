import Cocoa
import SwiftyMarkdown
import Preferences

class AcknowledgmentsTab: NSViewController, PreferencePane {
    // going taller than this will crop the view on small screens or low scaling modes on retina displays
    static let maxTabHeight = CGFloat(450)
    let preferencePaneIdentifier = PreferencePane.Identifier("Acknowledgments")
    let preferencePaneTitle = NSLocalizedString("Acknowledgments", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.userAccountsName)!

    override func loadView() {
        let textViews: [TextField] = ["Contributors", "Acknowledgments"].map {
            let markdownFileUrl = Bundle.main.url(forResource: $0, withExtension: "md")!
            let md = SwiftyMarkdown(url: markdownFileUrl)!
            md.h1.fontSize = 16
            md.underlineLinks = false
            md.bullet = "•"
            let textView = TextField(md.attributedString())
            textView.allowsEditingTextAttributes = true
            textView.isSelectable = true
            return textView
        }
        let subGrid = GridView([textViews])
        subGrid.column(at: 1).leadingPadding = 20
        subGrid.fit()

        let scrollView = ScrollView()
        scrollView.scrollerKnobStyle = .default
        scrollView.documentView!.subviews = [subGrid]
        let totalWidth = subGrid.fittingSize.width
        let totalHeight = min(subGrid.fittingSize.height, AcknowledgmentsTab.maxTabHeight)
        scrollView.frame.size = NSSize(width: totalWidth, height: totalHeight)
        scrollView.contentView.frame.size = scrollView.frame.size
        scrollView.documentView!.frame.size = subGrid.fittingSize
        scrollView.fit(totalWidth, totalHeight)

        view = scrollView
    }
}
