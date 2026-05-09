import Foundation
@preconcurrency import AppKit
@preconcurrency import CoreBluetooth
import CoreText

private enum Brand {
    static let background = NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.972, alpha: 1)
    static let surface = NSColor.white
    static let surfaceMuted = NSColor(calibratedRed: 0.925, green: 0.945, blue: 0.948, alpha: 1)
    static let hero = NSColor(calibratedRed: 0.89, green: 0.977, blue: 0.987, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.075, green: 0.09, blue: 0.105, alpha: 1)
    static let inkMuted = NSColor(calibratedRed: 0.38, green: 0.43, blue: 0.47, alpha: 1)
    static let hairline = NSColor(calibratedRed: 0.83, green: 0.875, blue: 0.88, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.02, green: 0.68, blue: 0.86, alpha: 1)
    static let success = NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.42, alpha: 1)
    static let warning = NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.08, alpha: 1)
    static let error = NSColor(calibratedRed: 0.78, green: 0.14, blue: 0.17, alpha: 1)
}

private enum AppTypography {
    static func registerBundledFonts() {
        // Uses macOS system font (SF Pro). No bundled font files.
    }

    static func regular(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func light(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .light)
    }

    static func bold(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}

private enum LabelWeight {
    case regular
    case bold

    func font(_ size: CGFloat) -> NSFont {
        switch self {
        case .regular:
            AppTypography.regular(size)
        case .bold:
            AppTypography.bold(size)
        }
    }
}

private enum Layout {
    static let windowWidth: CGFloat = 360
    static let compactWindowHeight: CGFloat = 490
    static let pageInset: CGFloat = 20
    static let cardSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 14
}

private func makeLabel(
    _ text: String,
    size: CGFloat,
    weight: LabelWeight = .regular,
    color: NSColor
) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.translatesAutoresizingMaskIntoConstraints = false
    field.font = weight.font(size)
    field.textColor = color
    field.lineBreakMode = .byWordWrapping
    field.maximumNumberOfLines = 0
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return field
}

private class CardView: NSView {
    init(cornerRadius: CGFloat = 18) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Brand.surface.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderColor = Brand.hairline.withAlphaComponent(0.6).cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: 4)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class DotView: NSView {
    var color: NSColor = Brand.inkMuted {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 4
        widthAnchor.constraint(equalToConstant: 8).isActive = true
        heightAnchor.constraint(equalToConstant: 8).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 8, height: 8)
    }
}

private final class ActionButton: NSButton {
    enum Style {
        case primary
        case secondary
        case quiet
    }

    private let buttonStyle: Style

    init(title: String, style: Style) {
        self.buttonStyle = style
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        bezelStyle = .regularSquare
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: style == .quiet ? 34 : 42).isActive = true
        if style == .quiet {
            widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        }
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { refresh() }
    }

    override var isEnabled: Bool {
        didSet { refresh() }
    }

    func updateTitle(_ title: String) {
        self.title = title
        refresh()
    }

    private func refresh() {
        let titleColor: NSColor
        let backgroundColor: NSColor
        let borderColor: NSColor
        let borderWidth: CGFloat

        switch buttonStyle {
        case .primary:
            titleColor = .white
            backgroundColor = isEnabled
                ? (isHighlighted ? Brand.ink.withAlphaComponent(0.86) : Brand.ink)
                : Brand.ink.withAlphaComponent(0.32)
            borderColor = .clear
            borderWidth = 0
        case .secondary:
            titleColor = isEnabled ? Brand.ink : Brand.inkMuted.withAlphaComponent(0.6)
            backgroundColor = isHighlighted ? Brand.surfaceMuted : Brand.surface
            borderColor = Brand.hairline
            borderWidth = 1
        case .quiet:
            titleColor = isEnabled ? Brand.ink : Brand.inkMuted.withAlphaComponent(0.55)
            backgroundColor = isHighlighted
                ? Brand.surfaceMuted
                : Brand.surfaceMuted.withAlphaComponent(0.74)
            borderColor = Brand.hairline.withAlphaComponent(0.7)
            borderWidth = 1
        }

        layer?.cornerRadius = buttonStyle == .quiet ? 13 : 12
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderWidth

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: titleColor,
                .font: AppTypography.bold(buttonStyle == .quiet ? 12 : 14),
                .paragraphStyle: paragraph,
            ]
        )
    }
}

private final class TabButton: NSButton {
    var isSelectedTab = false {
        didSet { refresh() }
    }

    init(title: String, selected: Bool) {
        self.isSelectedTab = selected
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { refresh() }
    }

    private func refresh() {
        let background = isSelectedTab
            ? (isHighlighted ? Brand.ink.withAlphaComponent(0.88) : Brand.ink)
            : (isHighlighted ? Brand.surfaceMuted : NSColor.clear)
        let foreground = isSelectedTab ? NSColor.white : Brand.inkMuted

        layer?.backgroundColor = background.cgColor
        layer?.cornerRadius = 12

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: foreground,
                .font: AppTypography.bold(12),
                .paragraphStyle: paragraph,
            ]
        )
    }
}

private final class DeviceHeroView: CardView {
    private let imageView = NSImageView()

    override init(cornerRadius: CGFloat = 18) {
        super.init(cornerRadius: cornerRadius)
        layer?.backgroundColor = Brand.hero.cgColor
        layer?.borderColor = Brand.hero.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = Self.loadDeviceImage()
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)

        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func loadDeviceImage() -> NSImage? {
        if let pngURL = Bundle.main.url(forResource: "wakey_device", withExtension: "png", subdirectory: "Assets") {
            return NSImage(contentsOf: pngURL)
        }

        if let webpURL = Bundle.main.url(forResource: "wakey_device", withExtension: "webp", subdirectory: "Assets") {
            return NSImage(contentsOf: webpURL)
        }

        return nil
    }
}

private final class SoftPanelView: NSView {
    init(cornerRadius: CGFloat = 14) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Brand.surfaceMuted.withAlphaComponent(0.58).cgColor
        layer?.cornerRadius = cornerRadius
        layer?.borderColor = Brand.hairline.withAlphaComponent(0.72).cgColor
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Window Controller

private final class WakeyWindowController: NSWindowController {
    private enum Tab {
        case home
        case activity
    }

    // Primary card
    private let syncButton = ActionButton(title: "Sync current time", style: .primary)
    private let advancedButton = ActionButton(title: "Sync selected time", style: .secondary)
    private let lastSyncLabel = makeLabel("Not synced", size: 12, color: Brand.inkMuted)
    private let statusMessageLabel = makeLabel("", size: 12, color: Brand.inkMuted)

    // Blocked card (only visible when permission denied)
    private let openPrivacyButton = ActionButton(title: "Open Privacy Settings", style: .secondary)
    private let blockedTitle = makeLabel("Bluetooth access denied", size: 13.5, weight: .bold, color: Brand.ink)
    private let blockedLabel = makeLabel("", size: 12, color: Brand.inkMuted)

    // Advanced card
    private let disclosureButton = ActionButton(title: "Set time", style: .quiet)
    private let datePicker = NSDatePicker()
    private let timePicker = NSDatePicker()
    private let advancedContent = NSStackView()

    // Header
    private let headerStatusDot = DotView(color: Brand.inkMuted)
    private let headerStatusLabel = makeLabel("Ready", size: 11.5, weight: .bold, color: Brand.ink)

    // Tab bar
    private let homeTabButton = TabButton(title: "Home", selected: true)
    private let activityTabButton = TabButton(title: "Activity", selected: false)

    // Pages
    private let homeContent = NSStackView()
    private let activityContent = NSStackView()
    private let pageContainer = NSView()
    private var homeBottomConstraint: NSLayoutConstraint?
    private var activityBottomConstraint: NSLayoutConstraint?

    // Activity log
    private let logScrollView = NSScrollView()
    private let logView = NSTextView()

    // State
    private var blockedCard: NSView?
    private var isSyncing = false
    private var didBuildUI = false
    private var selectedTab = Tab.home
    private var hasError = false
    private var pendingResizeWorkItem: DispatchWorkItem?
    private var lastRequestedWindowHeight: CGFloat = 0

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.compactWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WakeySync"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Brand.background
        window.minSize = NSSize(width: Layout.windowWidth, height: 300)
        window.maxSize = NSSize(width: Layout.windowWidth, height: 900)
        self.init(window: window)
        buildWindowIfNeeded()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        buildWindowIfNeeded()
    }

    // MARK: - Setup

    private func buildWindowIfNeeded() {
        guard !didBuildUI else {
            return
        }

        didBuildUI = true
        buildUI()
        updatePermissionState()
        appendLog("WakeySync is ready.")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Brand.background.cgColor

        let inset = Layout.pageInset
        let header = makeHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(header)

        let hero = DeviceHeroView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        configurePageStack(homeContent)
        configurePageStack(activityContent)
        homeContent.addArrangedSubview(hero)

        let blockedCard = makeBlockedCard()
        let primaryCard = makePrimaryCard()
        let advancedCard = makeAdvancedCard()
        let activityCard = makeActivityCard()
        let tabBar = makeTabBar()
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        self.blockedCard = blockedCard
        homeContent.addArrangedSubview(blockedCard)
        homeContent.addArrangedSubview(primaryCard)
        homeContent.addArrangedSubview(advancedCard)
        activityContent.addArrangedSubview(activityCard)
        setupPages()

        contentView.addSubview(pageContainer)
        contentView.addSubview(tabBar)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            pageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            pageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            pageContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Layout.sectionSpacing),

            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: inset),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -inset),
            tabBar.topAnchor.constraint(equalTo: pageContainer.bottomAnchor, constant: Layout.sectionSpacing),
            tabBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            hero.widthAnchor.constraint(equalTo: homeContent.widthAnchor),
            hero.heightAnchor.constraint(equalToConstant: 110),
            primaryCard.widthAnchor.constraint(equalTo: homeContent.widthAnchor),
            advancedCard.widthAnchor.constraint(equalTo: homeContent.widthAnchor),
            blockedCard.widthAnchor.constraint(equalTo: homeContent.widthAnchor),
            activityCard.widthAnchor.constraint(equalTo: activityContent.widthAnchor),
        ])

        syncButton.target = self
        syncButton.action = #selector(syncCurrentTime)
        advancedButton.target = self
        advancedButton.action = #selector(syncSelectedTime)
        disclosureButton.target = self
        disclosureButton.action = #selector(toggleAdvanced)
        openPrivacyButton.target = self
        openPrivacyButton.action = #selector(openBluetoothPrivacy)
        homeTabButton.target = self
        homeTabButton.action = #selector(showHome)
        activityTabButton.target = self
        activityTabButton.action = #selector(showActivity)

        advancedContent.isHidden = true
    }

    private func setupPages() {
        pageContainer.addSubview(homeContent)
        pageContainer.addSubview(activityContent)

        let homeBottom = homeContent.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        let activityBottom = activityContent.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        homeBottomConstraint = homeBottom
        activityBottomConstraint = activityBottom

        NSLayoutConstraint.activate([
            homeContent.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            homeContent.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            homeContent.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            homeBottom,
            activityContent.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            activityContent.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            activityContent.topAnchor.constraint(equalTo: pageContainer.topAnchor),
        ])

        activityContent.isHidden = true
        activityBottom.isActive = false
    }

    // MARK: - Card Builders

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let text = NSStackView()
        text.orientation = .vertical
        text.spacing = 1
        text.alignment = .leading
        text.addArrangedSubview(makeLabel("soundcore", size: 10, weight: .bold, color: Brand.accent))
        text.addArrangedSubview(makeLabel("WakeySync", size: 22, weight: .bold, color: Brand.ink))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let pill = NSStackView()
        pill.orientation = .horizontal
        pill.alignment = .centerY
        pill.spacing = 5
        pill.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        pill.wantsLayer = true
        pill.layer?.backgroundColor = Brand.surface.cgColor
        pill.layer?.cornerRadius = 14
        pill.layer?.borderColor = Brand.hairline.withAlphaComponent(0.6).cgColor
        pill.layer?.borderWidth = 1
        pill.addArrangedSubview(headerStatusDot)
        pill.addArrangedSubview(headerStatusLabel)

        row.addArrangedSubview(text)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(pill)
        return row
    }

    private func makeTabBar() -> NSView {
        let card = CardView(cornerRadius: 14)
        card.layer?.backgroundColor = Brand.surface.cgColor

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 4

        row.addArrangedSubview(homeTabButton)
        row.addArrangedSubview(activityTabButton)
        card.addSubview(row)
        constrainToCard(row, card: card, inset: 5)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 46),
        ])

        return card
    }

    private func makePrimaryCard() -> NSView {
        let card = paddedCard()

        let stack = verticalStack(spacing: 12)
        card.addSubview(stack)
        constrainToCard(stack, card: card, inset: 16)

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 8
        let title = makeLabel("Soundcore Wakey", size: 15, weight: .bold, color: Brand.ink)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(spacer)
        titleRow.addArrangedSubview(lastSyncLabel)

        statusMessageLabel.isHidden = true

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(statusMessageLabel)
        stack.addArrangedSubview(syncButton)

        NSLayoutConstraint.activate([
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusMessageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            syncButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return card
    }

    private func makeBlockedCard() -> NSView {
        let card = paddedCard(cornerRadius: 14)
        card.layer?.backgroundColor = Brand.surfaceMuted.withAlphaComponent(0.72).cgColor

        let stack = verticalStack(spacing: 10)
        card.addSubview(stack)
        constrainToCard(stack, card: card, inset: 14)

        stack.addArrangedSubview(blockedTitle)
        stack.addArrangedSubview(blockedLabel)
        stack.addArrangedSubview(openPrivacyButton)

        NSLayoutConstraint.activate([
            openPrivacyButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return card
    }

    private func makeAdvancedCard() -> NSView {
        let card = paddedCard()

        let stack = verticalStack(spacing: 10)
        card.addSubview(stack)
        constrainToCard(stack, card: card, inset: 16)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let titleLabel = makeLabel("Custom time", size: 13, weight: .bold, color: Brand.ink)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(disclosureButton)

        advancedContent.orientation = .vertical
        advancedContent.alignment = .leading
        advancedContent.spacing = 12

        let pickerPanel = SoftPanelView()
        let pickerStack = verticalStack(spacing: 10)
        pickerPanel.addSubview(pickerStack)
        constrainToCard(pickerStack, card: pickerPanel, inset: 12)

        let now = Date()
        configurePicker(datePicker, elements: [.yearMonthDay], date: now)
        configurePicker(timePicker, elements: [.hourMinuteSecond], date: now)

        pickerStack.addArrangedSubview(makePickerRow(title: "Date", picker: datePicker, pickerWidth: 178))
        pickerStack.addArrangedSubview(makeHairline())
        pickerStack.addArrangedSubview(makePickerRow(title: "Time", picker: timePicker, pickerWidth: 178))

        advancedContent.addArrangedSubview(pickerPanel)
        advancedContent.addArrangedSubview(advancedButton)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(advancedContent)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pickerPanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            advancedButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return card
    }

    private func configurePicker(
        _ picker: NSDatePicker,
        elements: NSDatePicker.ElementFlags,
        date: Date
    ) {
        picker.datePickerElements = elements
        picker.datePickerStyle = .textFieldAndStepper
        picker.dateValue = date
        picker.isBordered = false
        picker.drawsBackground = false
        picker.textColor = Brand.ink
        picker.font = AppTypography.bold(13)
        picker.alignment = .left
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        picker.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func makePickerRow(title: String, picker: NSDatePicker, pickerWidth: CGFloat) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = makeLabel(title, size: 11.5, weight: .bold, color: Brand.inkMuted)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(picker)
        row.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 36),
            label.widthAnchor.constraint(equalToConstant: 42),
            picker.widthAnchor.constraint(equalToConstant: pickerWidth),
        ])

        return row
    }

    private func makeHairline() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = Brand.hairline.withAlphaComponent(0.68).cgColor
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return line
    }

    private func makeActivityCard() -> NSView {
        let card = paddedCard()

        let stack = verticalStack(spacing: 12)
        card.addSubview(stack)
        constrainToCard(stack, card: card, inset: 16)

        let title = makeLabel("Activity", size: 14, weight: .bold, color: Brand.ink)

        logScrollView.translatesAutoresizingMaskIntoConstraints = false
        logScrollView.hasVerticalScroller = true
        logScrollView.hasHorizontalScroller = false
        logScrollView.borderType = .noBorder
        logScrollView.drawsBackground = false

        logView.isEditable = false
        logView.isSelectable = true
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.font = AppTypography.regular(11)
        logView.textColor = Brand.inkMuted
        logView.backgroundColor = .clear
        logView.textContainerInset = NSSize(width: 0, height: 0)
        logView.translatesAutoresizingMaskIntoConstraints = true
        logView.frame = NSRect(x: 0, y: 0, width: Layout.windowWidth - (Layout.pageInset * 2) - 32, height: 318)
        logView.textContainer?.widthTracksTextView = true
        logView.textContainer?.containerSize = NSSize(
            width: logView.frame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        logScrollView.documentView = logView

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(logScrollView)

        NSLayoutConstraint.activate([
            logScrollView.heightAnchor.constraint(equalToConstant: 318),
            logScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return card
    }

    // MARK: - Actions

    @objc private func syncCurrentTime() {
        startSync(date: Date(), label: "current time")
    }

    @objc private func syncSelectedTime() {
        startSync(date: selectedCustomDate(), label: "selected time")
    }

    @objc private func showHome() {
        selectTab(.home)
    }

    @objc private func showActivity() {
        selectTab(.activity)
    }

    @objc private func toggleAdvanced() {
        advancedContent.isHidden.toggle()
        disclosureButton.updateTitle(advancedContent.isHidden ? "Set time" : "Hide")
        updateWindowSize()
    }

    @objc private func openBluetoothPrivacy() {
        openSettings(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"))
    }

    private func selectedCustomDate() -> Date {
        let calendar = Calendar.current
        let date = calendar.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let time = calendar.dateComponents([.hour, .minute, .second], from: timePicker.dateValue)

        var combined = DateComponents()
        combined.calendar = calendar
        combined.timeZone = .current
        combined.year = date.year
        combined.month = date.month
        combined.day = date.day
        combined.hour = time.hour
        combined.minute = time.minute
        combined.second = time.second

        return calendar.date(from: combined) ?? datePicker.dateValue
    }

    @objc private func appDidBecomeActive() {
        guard !isSyncing else {
            return
        }
        updatePermissionState()
    }

    // MARK: - Tab Navigation

    private func selectTab(_ tab: Tab) {
        selectedTab = tab
        homeContent.isHidden = tab != .home
        activityContent.isHidden = tab != .activity
        homeBottomConstraint?.isActive = tab == .home
        activityBottomConstraint?.isActive = tab == .activity
        homeTabButton.isSelectedTab = tab == .home
        activityTabButton.isSelectedTab = tab == .activity
        updateWindowSize()
    }

    // MARK: - Sync Flow

    private func startSync(date: Date, label: String) {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        hasError = false
        setButtonsEnabled(false)
        syncButton.updateTitle("Sync current time")
        showStatusMessage("Scanning for Wakey\u{2026}")
        setStatus(title: "Syncing", color: Brand.accent)
        appendLog("Starting \(label) sync.")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let result = try syncWakeyTimeOverBLE(date: date) { message in
                    DispatchQueue.main.async {
                        self?.appendLog(message)
                        if message.contains("connecting to") {
                            self?.showStatusMessage("Connecting\u{2026}")
                        } else if message.contains("send ") {
                            self?.showStatusMessage("Syncing\u{2026}")
                        }
                    }
                }

                DispatchQueue.main.async {
                    self?.finishSync(result: result, date: date)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.finishSync(error: error)
                }
            }
        }
    }

    private func finishSync(result: WakeySyncResult, date: Date) {
        isSyncing = false

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        if result.acknowledged {
            hasError = false
            hideStatusMessage()
            setStatus(title: "Synced", color: Brand.success)
            lastSyncLabel.stringValue = "Synced \(formatter.string(from: date))"
            syncButton.updateTitle("Sync current time")
            appendLog("Wakey acknowledged packet: \(Hex.string(for: result.packet))")
            Telemetry.track("sync_succeeded")
        } else {
            hasError = true
            showStatusMessage("Reached the Wakey but it didn\u{2019}t confirm the update. Try again.")
            setStatus(title: "No reply", color: Brand.warning)
            syncButton.updateTitle("Try again")
            appendLog("No acknowledgement after packet: \(Hex.string(for: result.packet))")
            Telemetry.track("sync_failed_no_ack")
        }

        setButtonsEnabled(true)
        updatePermissionState()
    }

    private func finishSync(error: Error) {
        isSyncing = false
        hasError = true

        let description = "\(error)"

        if description.contains("not authorized") || description.contains("Bluetooth is not authorized") {
            appendLog("Sync failed: Bluetooth access denied.")
            setButtonsEnabled(false)
            updatePermissionState()
            Telemetry.track("sync_failed_unauthorized")
            return
        }

        if description.contains("timed out") || description.contains("scan timed out") {
            showStatusMessage("Could not find the Wakey. Make sure it\u{2019}s powered on and nearby.")
            setStatus(title: "Not found", color: Brand.warning)
            Telemetry.track("sync_failed_timeout")
        } else if description.contains("powered off") || description.contains("Bluetooth is powered off") {
            showStatusMessage("Bluetooth is turned off. Enable it in the menu bar or System Settings.")
            setStatus(title: "BT off", color: Brand.error)
            Telemetry.track("sync_failed_bt_off")
        } else {
            showStatusMessage("Sync failed. Check Activity for details.")
            setStatus(title: "Failed", color: Brand.error)
            Telemetry.track("sync_failed_other")
        }

        syncButton.updateTitle("Try again")
        setButtonsEnabled(true)
        appendLog("Sync failed: \(error)")
    }

    // MARK: - Permission State

    private func updatePermissionState() {
        let auth = CBManager.authorization
        let isBlocked = auth == .denied || auth == .restricted

        if isBlocked {
            blockedCard?.isHidden = false
            if auth == .denied {
                blockedTitle.stringValue = "Bluetooth access denied"
                blockedLabel.stringValue = "WakeySync needs Bluetooth to reach your speaker. Open Privacy settings and allow WakeySync under Bluetooth."
            } else {
                blockedTitle.stringValue = "Bluetooth restricted"
                blockedLabel.stringValue = "Bluetooth is restricted by macOS. Check device management or parental controls."
            }
            syncButton.isEnabled = false
            advancedButton.isEnabled = false
            hideStatusMessage()
            setStatus(title: "Blocked", color: Brand.error)
        } else {
            let wasBlocked = !(blockedCard?.isHidden ?? true)
            blockedCard?.isHidden = true

            if !isSyncing {
                syncButton.isEnabled = true
                advancedButton.isEnabled = true
            }

            if wasBlocked {
                hasError = false
                hideStatusMessage()
                syncButton.updateTitle("Sync current time")
                setStatus(title: "Ready", color: Brand.success)
            } else if !hasError && !isSyncing && headerStatusLabel.stringValue != "Synced" {
                setStatus(title: "Ready", color: Brand.success)
            }
        }

        updateWindowSize()
    }

    // MARK: - UI Helpers

    private func setButtonsEnabled(_ enabled: Bool) {
        syncButton.isEnabled = enabled
        advancedButton.isEnabled = enabled
    }

    private func setStatus(title: String, color: NSColor) {
        headerStatusLabel.stringValue = title
        headerStatusDot.color = color
    }

    private func showStatusMessage(_ text: String) {
        statusMessageLabel.stringValue = text
        statusMessageLabel.isHidden = false
        updateWindowSize()
    }

    private func hideStatusMessage() {
        statusMessageLabel.stringValue = ""
        statusMessageLabel.isHidden = true
        updateWindowSize()
    }

    private func updateWindowSize(animated: Bool = true) {
        pendingResizeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performWindowSizeUpdate(animated: animated)
        }

        pendingResizeWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func performWindowSizeUpdate(animated: Bool) {
        guard let window, let contentView = window.contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        let fitting = contentView.fittingSize
        let height = max(fitting.height, 300)

        if abs(height - lastRequestedWindowHeight) < 0.5 && abs(height - window.frame.height) < 0.5 {
            return
        }

        lastRequestedWindowHeight = height

        var frame = window.frame
        let delta = height - frame.height
        frame.origin.y -= delta
        frame.size.height = height
        frame.size.width = Layout.windowWidth

        window.setFrame(frame, display: true, animate: didBuildUI && animated)
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        let current = logView.string
        logView.string = current.isEmpty ? line : "\(current)\n\(line)"
        logView.scrollToEndOfDocument(nil)
        appLog(line)
    }

    private func openSettings(_ url: URL?) {
        guard let url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func paddedCard(cornerRadius: CGFloat = 18) -> CardView {
        let card = CardView(cornerRadius: cornerRadius)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func configurePageStack(_ stack: NSStackView) {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.cardSpacing
    }

    private func constrainToCard(_ view: NSView, card: NSView, inset: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
        ])
    }

    private func verticalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

}

// MARK: - App Delegate

private final class WakeyAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WakeyWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppTypography.registerBundledFonts()
        configureMenu()

        let controller = WakeyWindowController()
        self.controller = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)

        Telemetry.bootstrap()
        if !Telemetry.hasAskedConsent {
            DispatchQueue.main.async { [weak self] in
                self?.askForAnalyticsConsent()
            }
        }
        Telemetry.track("app_launched")
    }

    private func askForAnalyticsConsent() {
        let alert = NSAlert()
        alert.messageText = "Help improve WakeySync?"
        alert.informativeText = """
        WakeySync can send anonymous usage data so we know which macOS \
        versions and Wakey firmwares are in active use, and where syncs \
        fail. No personal data, no Bluetooth addresses, no IPs. You can \
        change this any time from the app menu.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "No thanks")
        let response = alert.runModal()
        Telemetry.setEnabled(response == .alertFirstButtonReturn)
    }

    @objc func toggleAnalytics(_ sender: Any?) {
        Telemetry.setEnabled(!Telemetry.isEnabled)
        rebuildAnalyticsMenuItem()
    }

    fileprivate func rebuildAnalyticsMenuItem() {
        analyticsMenuItem?.title = Telemetry.isEnabled
            ? "Disable Anonymous Analytics"
            : "Enable Anonymous Analytics"
    }

    fileprivate var analyticsMenuItem: NSMenuItem?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let analyticsItem = NSMenuItem(
            title: Telemetry.isEnabled
                ? "Disable Anonymous Analytics"
                : "Enable Anonymous Analytics",
            action: #selector(toggleAnalytics(_:)),
            keyEquivalent: ""
        )
        analyticsItem.target = self
        analyticsMenuItem = analyticsItem
        appMenu.addItem(analyticsItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(NSMenuItem(title: "Quit WakeySync", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}

private func appLog(_ message: String) {
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/WakeySync.log")

    do {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = "\(Date()) \(message)\n".data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: logURL)
        }
    } catch {
        // Logging should never block the one-button sync flow.
    }
}

@main
private enum WakeyAppMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty {
            let app = NSApplication.shared
            let delegate = WakeyAppDelegate()
            app.delegate = delegate
            app.run()
        } else {
            do {
                exit(try runCLI(argv: args))
            } catch {
                appLog("CLI failed: \(error)")
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }
    }
}
