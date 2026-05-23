import AppKit
import EventKit

// MARK: - CalendarPopoverView

class CalendarPopoverView: NSView {
    var characterColor: NSColor?
    var themeOverride: PopoverTheme?
    var theme: PopoverTheme {
        var t = themeOverride ?? PopoverTheme.current
        if let color = characterColor { t = t.withCharacterColor(color) }
        t = t.withCustomFont()
        return t
    }

    var onRefreshRequested: (() -> Void)?
    var onOpenCalendarRequested: (() -> Void)?

    private let scrollView = NSScrollView()
    private var eventStack: NSView?
    private var statusLabel: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    // MARK: - Layout

    private func setupViews() {
        let t = theme

        wantsLayer = true
        layer?.backgroundColor = t.popoverBg.cgColor

        scrollView.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let docView = NSView(frame: scrollView.contentView.bounds)
        docView.autoresizingMask = [.width]
        scrollView.documentView = docView

        addSubview(scrollView)

        showLoading()
    }

    // MARK: - Content States

    func showLoading() {
        clearContent()
        let t = theme
        let label = makeLabel("Fetching events…", color: t.textDim, font: t.font)
        label.frame = NSRect(x: 0, y: frame.height / 2 - 10, width: frame.width, height: 20)
        label.alignment = .center
        scrollView.documentView?.addSubview(label)
        statusLabel = label
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    func showPermissionDenied() {
        clearContent()
        let t = theme

        let container = NSView(frame: NSRect(x: 20, y: 40, width: frame.width - 40, height: frame.height - 80))
        container.autoresizingMask = [.width]

        let icon = makeLabel("🔒", color: t.textPrimary, font: NSFont.systemFont(ofSize: 32))
        icon.alignment = .center
        icon.frame = NSRect(x: 0, y: container.frame.height - 50, width: container.frame.width, height: 40)
        container.addSubview(icon)

        let title = makeLabel("Calendar Access Needed", color: t.textPrimary, font: t.fontBold)
        title.alignment = .center
        title.frame = NSRect(x: 0, y: container.frame.height - 90, width: container.frame.width, height: 24)
        container.addSubview(title)

        let desc = makeLabel("lil agents needs access to your calendar to show upcoming events.", color: t.textDim, font: t.font)
        desc.alignment = .center
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 3
        desc.frame = NSRect(x: 0, y: container.frame.height - 140, width: container.frame.width, height: 44)
        container.addSubview(desc)

        let btn = makeButton("Open Privacy Settings", action: #selector(openPrivacySettings))
        btn.frame = NSRect(x: (container.frame.width - 180) / 2, y: container.frame.height - 190, width: 180, height: 28)
        container.addSubview(btn)

        scrollView.documentView?.addSubview(container)
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    func showEvents(_ events: [CalendarEvent]) {
        clearContent()
        let t = theme

        if events.isEmpty {
            let container = NSView(frame: NSRect(x: 20, y: 60, width: frame.width - 40, height: frame.height - 120))
            let emoji = makeLabel("🎉", color: t.textPrimary, font: NSFont.systemFont(ofSize: 28))
            emoji.alignment = .center
            emoji.frame = NSRect(x: 0, y: container.frame.height - 50, width: container.frame.width, height: 36)
            container.addSubview(emoji)

            let label = makeLabel("you're free!", color: t.textPrimary, font: t.fontBold)
            label.alignment = .center
            label.frame = NSRect(x: 0, y: container.frame.height - 82, width: container.frame.width, height: 24)
            container.addSubview(label)

            let sub = makeLabel("No upcoming events in the next 24 hours.", color: t.textDim, font: t.font)
            sub.alignment = .center
            sub.frame = NSRect(x: 0, y: container.frame.height - 108, width: container.frame.width, height: 20)
            container.addSubview(sub)

            scrollView.documentView?.addSubview(container)
            scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
            return
        }

        // Group events by day
        var grouped: [(String, [CalendarEvent])] = []
        var currentDay = ""
        var currentGroup: [CalendarEvent] = []

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"

        for event in events {
            let day: String
            if Calendar.current.isDateInToday(event.startDate) {
                day = "Today"
            } else if Calendar.current.isDateInTomorrow(event.startDate) {
                day = "Tomorrow"
            } else {
                day = dayFormatter.string(from: event.startDate)
            }

            if day != currentDay {
                if !currentGroup.isEmpty {
                    grouped.append((currentDay, currentGroup))
                }
                currentDay = day
                currentGroup = [event]
            } else {
                currentGroup.append(event)
            }
        }
        if !currentGroup.isEmpty {
            grouped.append((currentDay, currentGroup))
        }

        // Build event rows
        let rowHeight: CGFloat = 60
        let sectionHeaderH: CGFloat = 24
        let padding: CGFloat = 12

        var totalHeight: CGFloat = padding

        // Calculate total height first
        for (_, dayEvents) in grouped {
            totalHeight += sectionHeaderH + 6
            totalHeight += CGFloat(dayEvents.count) * (rowHeight + 6)
            totalHeight += 8
        }
        totalHeight += padding

        let contentHeight = max(totalHeight, frame.height)
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: contentHeight))
        docView.autoresizingMask = [.width]

        var y = contentHeight - padding

        for (dayLabel, dayEvents) in grouped {
            // Section header
            y -= sectionHeaderH
            let headerLabel = makeLabel(dayLabel.uppercased(), color: t.textDim,
                                        font: NSFont.systemFont(ofSize: t.font.pointSize - 1.5, weight: .semibold))
            headerLabel.frame = NSRect(x: padding, y: y, width: frame.width - padding * 2, height: sectionHeaderH)
            docView.addSubview(headerLabel)
            y -= 6

            for event in dayEvents {
                y -= rowHeight
                let row = buildEventRow(event: event, width: frame.width, height: rowHeight, padding: padding)
                row.frame.origin.y = y
                docView.addSubview(row)
                y -= 6
            }
            y -= 8
        }

        scrollView.documentView = docView
        // Scroll to top
        docView.scroll(NSPoint(x: 0, y: docView.frame.height))
    }

    // MARK: - Event Row Builder

    private func buildEventRow(event: CalendarEvent, width: CGFloat, height: CGFloat, padding: CGFloat) -> NSView {
        let t = theme
        let isUpcoming = event.minutesUntilStart >= 0 && event.minutesUntilStart <= 5
        let isOngoing = event.minutesUntilStart < 0

        // Row container
        let row = HoverableRowView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.normalBg = isUpcoming
            ? t.accentColor.withAlphaComponent(0.12)
            : .clear
        row.hoverBg = t.accentColor.withAlphaComponent(0.10)
        row.cornerRadius = 8
        row.margin = padding
        row.wantsLayer = true

        // Calendar color dot
        let dotSize: CGFloat = 9
        let dotView = NSView(frame: NSRect(x: padding + 2, y: height / 2 - dotSize / 2, width: dotSize, height: dotSize))
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = event.calendarColor.cgColor
        dotView.layer?.cornerRadius = dotSize / 2
        row.addSubview(dotView)

        let textX = padding + dotSize + 10
        let textWidth = width - textX - padding - 70

        // Event title
        let titleFont = isUpcoming ? t.fontBold : t.font
        let titleColor = isOngoing ? t.textDim : t.textPrimary
        let titleLabel = makeLabel(event.title, color: titleColor, font: titleFont)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: textX, y: height / 2 + 2, width: textWidth, height: 18)
        row.addSubview(titleLabel)

        // Location or time range
        let subText: String
        if let loc = event.location {
            subText = loc
        } else {
            subText = "\(event.formattedStartTime) – \(event.formattedEndTime)"
        }
        let subLabel = makeLabel(subText, color: t.textDim, font: NSFont.systemFont(ofSize: t.font.pointSize - 1.5))
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.frame = NSRect(x: textX, y: height / 2 - 18, width: textWidth, height: 16)
        row.addSubview(subLabel)

        // Relative time badge (right side)
        let badgeText = event.relativeTime
        let badgeColor: NSColor = isUpcoming ? t.accentColor : isOngoing ? t.textDim : t.textDim
        let badgeLabel = makeLabel(badgeText, color: badgeColor,
                                   font: NSFont.systemFont(ofSize: t.font.pointSize - 1.5,
                                                            weight: isUpcoming ? .semibold : .regular))
        badgeLabel.alignment = .right
        badgeLabel.frame = NSRect(x: width - padding - 66, y: height / 2 - 9, width: 66, height: 18)
        row.addSubview(badgeLabel)

        // Click to open Calendar
        let btn = NSButton(frame: row.bounds)
        btn.isTransparent = true
        btn.target = self
        btn.action = #selector(openCalendarApp)
        btn.identifier = NSUserInterfaceItemIdentifier(event.ekEventIdentifier)
        row.addSubview(btn)

        return row
    }

    // MARK: - Helpers

    private func clearContent() {
        statusLabel = nil
        eventStack = nil
        let docView = NSView(frame: scrollView.contentView.bounds)
        docView.autoresizingMask = [.width]
        scrollView.documentView = docView
    }

    private func makeLabel(_ text: String, color: NSColor, font: NSFont) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.textColor = color
        f.font = font
        f.isSelectable = false
        f.lineBreakMode = .byTruncatingTail
        f.maximumNumberOfLines = 1
        return f
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let t = theme
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.font = t.font
        btn.contentTintColor = t.accentColor
        return btn
    }

    // MARK: - Actions

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openCalendarApp() {
        if let url = URL(string: "calshow://") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - HoverableRowView

/// A plain NSView that highlights on mouse hover.
class HoverableRowView: NSView {
    var normalBg: NSColor = .clear
    var hoverBg: NSColor = .clear
    var cornerRadius: CGFloat = 8
    var margin: CGFloat = 8
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isHovered ? hoverBg : normalBg
        if bg != .clear {
            let inset = NSRect(x: margin, y: 2, width: bounds.width - margin * 2, height: bounds.height - 4)
            let path = NSBezierPath(roundedRect: inset, xRadius: cornerRadius, yRadius: cornerRadius)
            bg.setFill()
            path.fill()
        }
    }
}
