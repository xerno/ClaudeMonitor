import AppKit

struct AccountSegment: Equatable, Sendable {
    let id: String
    let label: String
    let toolTip: String
}

@MainActor
struct HeaderAccountSwitcher {
    let segments: [AccountSegment]
    let activeIndex: Int
    let onSelect: (String) -> Void
}

@MainActor
final class AccountToggleView: NSView {
    private let segmented = NSSegmentedControl()
    private var onSelect: ((String) -> Void)?
    private(set) var currentSegments: [AccountSegment] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        segmented.controlSize = .small
        segmented.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        segmented.segmentDistribution = .fit
        segmented.trackingMode = .selectOne
        segmented.target = self
        segmented.action = #selector(segmentChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmented)
        NSLayoutConstraint.activate([
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: trailingAnchor),
            segmented.topAnchor.constraint(equalTo: topAnchor),
            segmented.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with switcher: HeaderAccountSwitcher) {
        if currentSegments != switcher.segments {
            segmented.segmentCount = switcher.segments.count
            for (index, segment) in switcher.segments.enumerated() {
                segmented.setLabel(segment.label, forSegment: index)
                segmented.setToolTip(segment.toolTip, forSegment: index)
            }
            currentSegments = switcher.segments
        }
        if currentSegments.indices.contains(switcher.activeIndex) {
            segmented.selectedSegment = switcher.activeIndex
        }
        onSelect = switcher.onSelect
    }

    @objc private func segmentChanged() {
        let index = segmented.selectedSegment
        guard currentSegments.indices.contains(index) else { return }
        onSelect?(currentSegments[index].id)
    }
}
