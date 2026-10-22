import SwiftUI
import PDFKit

struct LicenseView: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> NSView {
        if path.lowercased().hasSuffix(".pdf") { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: URL(fileURLWithPath: path)); return v }
        let sv = NSScrollView(), tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 0))
        tv.isEditable = false; tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainer?.widthTracksTextView = true
        if let s = try? NSAttributedString(url: URL(fileURLWithPath: path), options: [:], documentAttributes: nil) { tv.textStorage?.setAttributedString(s) }
        sv.documentView = tv; sv.hasVerticalScroller = true
        return sv
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
