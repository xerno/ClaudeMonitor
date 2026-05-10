import AppKit

@MainActor
struct UsageCache {
    var labels: [(tag: Int, label: String, window: UsageWindow?)] = []
    var style: NSParagraphStyle = NSParagraphStyle()
    var prefixes: [Int: NSAttributedString] = [:]
}

@MainActor @objc protocol MenuActions {
    func didSelectRefresh()
    func openIncident(_ sender: NSMenuItem)
    func didSelectPreferences()
    func didSelectAbout()
    func didSelectUsageWindow(_ sender: NSMenuItem)
    func didSelectSentinel()
}

@MainActor
enum MenuBuilder {
    // Usage items
    static let usageSectionTag = 10
    static let usageBaseTag = 100
    static let usagePlaceholderTag = 199

    // Services items
    static let servicesSectionTag = 20
    static let serviceBaseTag = 300
    static let servicesPlaceholderTag = 310

    // Incidents items
    static let incidentsSectionTag = 30
    static let incidentBaseTag = 400

    // Controls items
    static let updatedTag = 200
    static let refreshTag = 601
    static let preferencesTag = 602
    static let aboutTag = 603
    static let quitTag = 604

    // Graph view
    static let usageGraphTag = 700

    // Connectivity banner
    static let connectivityBannerTag = 50
    // Separators
    static let separatorAfterUsageTag = 501
    static let separatorAfterServicesTag = 502
    static let separatorIncidentsTag = 503
    static let separatorControlsTag = 504
    static let separatorQuitTag = 505
    static let separatorAfterConnectivityTag = 506

    // MARK: - Public API

    @discardableResult
    static func build(state: MonitorState, target: any MenuActions) -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu, state: state, target: target)
        return menu
    }
}
