import AppKit

extension String {
    /// How wide the text is in `font`, as AppKit draws it: what a table's
    /// column (`ColumnWidth`) and Settings' toolbar measure their texts by.
    func width(in font: NSFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
    }
}
