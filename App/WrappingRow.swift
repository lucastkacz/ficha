import SwiftUI

/// Its views side by side, leading first, each at its ideal width, as an
/// `HStack` lays them out, going on in a line below when the next doesn't fit
/// beside the others: a row of buttons, or a chart's key, that wraps rather
/// than cut a title in a language whose words run longer than English's, as
/// `CODING_STANDARDS.md` asks of a text that can't wrap. SwiftUI's `Layout`
/// is standard; this one is ours.
struct WrappingRow: Layout {
    /// The room between two views in a line, and between two lines.
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An infinite width, which asks how wide the row can grow, fits every
        // view in one line, as no width does.
        let lines = lines(of: subviews, in: proposal.width.flatMap { $0.isFinite ? $0 : nil })
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(of: subviews, in: bounds.width) {
            // From the leading side: SwiftUI mirrors a layout's places in a
            // language read right to left, as Arabic's pictures show.
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + line.height / 2), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    /// The views of each line, in their order, with the line's width and
    /// height: as many as fit in `width` side by side, one at least, or all
    /// of them in one line without a width.
    private func lines(of subviews: Subviews, in width: CGFloat?) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let width, !line.indices.isEmpty, line.width + spacing + size.width > width {
                lines.append(line)
                line = Line()
            }
            line.width += (line.indices.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty {
            lines.append(line)
        }
        return lines
    }

    /// A line of the row: the indices of its views, and its size.
    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}
