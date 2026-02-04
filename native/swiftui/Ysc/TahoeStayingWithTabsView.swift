//
//  TahoeStayingWithTabsView.swift
//  Ysc
//
//  Tabbed view component for switching between calendar and reservations table

import SwiftUI
import LiveViewNative

@available(iOS 18.0, *)
@LiveElement
struct TahoeStayingWithTabs<Root: RootRegistry>: View {
    let element: ElementNode
    @State private var selectedTab: Int = 0 // 0 = Calendar, 1 = Reservations

    // Parse data from element attributes
    private var calendarDataJson: String? {
        element.attributeValue(for: "calendar_data")
    }

    private var reservationsDataJson: String? {
        element.attributeValue(for: "reservations_data")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control for tab selection
            Picker("View", selection: $selectedTab) {
                Text("Calendar").tag(0)
                Text("Reservations").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.regularMaterial)

            // Content based on selected tab
            Group {
                if selectedTab == 0 {
                    // Calendar tab
                    if let calendarData = calendarDataJson {
                        RoomCalendarWrapper(data: calendarData)
                    } else {
                        VStack(spacing: 12) {
                            Text("Loading calendar...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                } else {
                    // Reservations tab
                    if let reservationsData = reservationsDataJson {
                        ReservationsTableWrapper(data: reservationsData)
                    } else {
                        VStack(spacing: 12) {
                            Text("Loading reservations...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Wrapper views to reuse existing components
@available(iOS 18.0, *)
private struct RoomCalendarWrapper: View {
    let data: String

    var body: some View {
        // Create a temporary element node to pass to RoomCalendar
        // We'll use a workaround by creating a simple wrapper
        GeometryReader { geometry in
            RoomCalendarContent(data: data)
        }
    }
}

@available(iOS 18.0, *)
private struct RoomCalendarContent: View {
    let data: String
    
    // Parse calendar data
    private var calendarData: CalendarData? {
        // Decode HTML entities
        let decodedString = data
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        guard let jsonData = decodedString.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(CalendarData.self, from: jsonData)
        } catch {
            print("[TahoeStayingWithTabs] Failed to decode calendar JSON: \(error)")
            return nil
        }
    }

    var body: some View {
        if let data = calendarData {
            // Reuse the calendar view logic from RoomCalendarView
            CalendarContentView(data: data)
        } else {
            VStack(spacing: 12) {
                Text("Loading calendar...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// Extract the calendar view content from RoomCalendar
@available(iOS 18.0, *)
private struct CalendarContentView: View {
    let data: CalendarData
    @State private var verticalScrollOffset: CGFloat = 0
    @State private var lastSyncedRoomIndex: Int = -1
    @State private var userIsScrollingCalendar: Bool = false

    private let dayWidth: CGFloat = 80
    private let rowHeight: CGFloat = 80
    private let headerHeight: CGFloat = 60
    private let roomColumnWidth: CGFloat = 140

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Who Am I Staying With?")
                    .font(.system(size: 32, weight: .bold))

                Text(dateRangeText(startDate: data.calendarStartDate, endDate: data.calendarEndDate))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            // Legend
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)

                Text("Checked in")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            // Calendar Grid - reuse the synchronized scroll view logic
            HStack(alignment: VerticalAlignment.top, spacing: 0) {
                // Fixed Left Column: Room Names
                VStack(alignment: .leading, spacing: 0) {
                    ScrollViewReader { roomProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(data.rooms.enumerated()), id: \.element.id) { index, room in
                                    HStack(alignment: .center) {
                                        Text(room.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: rowHeight)
                                    .overlay(
                                        Rectangle()
                                            .frame(height: 1)
                                            .foregroundColor(Color(uiColor: .separator)),
                                        alignment: .bottom
                                    )
                                    .id("room-name-\(index)")
                                }
                            }
                        }
                        .disabled(true)
                        .onChange(of: verticalScrollOffset) { newOffset in
                            // Sync room names with calendar scroll
                            let roomIndex = Int(newOffset / rowHeight)
                            if roomIndex != lastSyncedRoomIndex && roomIndex >= 0 && roomIndex < data.rooms.count {
                                withAnimation {
                                    roomProxy.scrollTo("room-name-\(roomIndex)", anchor: .top)
                                }
                                lastSyncedRoomIndex = roomIndex
                            }
                        }
                    }
                }
                .frame(width: roomColumnWidth)
                .background(Color(uiColor: .secondarySystemBackground))

                // Calendar with bookings
                SynchronizedScrollView(
                    headerContent: {
                        HStack(alignment: .center, spacing: 0) {
                            ForEach(data.calendarDates, id: \.self) { dateStr in
                                dateHeaderCell(
                                    dateStr: dateStr,
                                    isToday: dateStr == data.today
                                )
                            }
                        }
                    },
                    bodyContent: {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(data.rooms.enumerated()), id: \.element.id) { index, room in
                                roomRow(
                                    room: room,
                                    dates: data.calendarDates,
                                    bookings: data.bookingsByRoom[room.id] ?? [],
                                    startDate: data.calendarStartDate,
                                    today: data.today
                                )
                                .id("calendar-room-\(index)")
                            }
                        }
                    },
                    verticalScrollOffset: $verticalScrollOffset,
                    userIsScrollingCalendar: $userIsScrollingCalendar
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Helper functions (reused from RoomCalendarView)
    private func dateHeaderCell(dateStr: String, isToday: Bool) -> some View {
        let date = parseDate(dateStr) ?? Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "EEE"
        let dayName = formatter.string(from: date)
        formatter.dateFormat = "MM/dd"
        let dateFormatted = formatter.string(from: date)

        return VStack(alignment: .center, spacing: 4) {
            Text(dayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isToday ? .blue : .secondary)

            Text(dateFormatted)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isToday ? .blue : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: dayWidth, height: headerHeight)
        .background(isToday ? Color.blue.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .trailing
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func roomRow(
        room: Room,
        dates: [String],
        bookings: [Booking],
        startDate: String,
        today: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Background grid cells
            HStack(alignment: .center, spacing: 0) {
                ForEach(dates, id: \.self) { dateStr in
                    let isToday = dateStr == today
                    Rectangle()
                        .fill(isToday ? Color.blue.opacity(0.08) : Color.white)
                        .frame(width: dayWidth, height: rowHeight)
                        .overlay(
                            Rectangle()
                                .frame(width: 1)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .trailing
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .bottom
                        )
                }
            }

            // Booking bars
            ForEach(bookings, id: \.id) { booking in
                bookingBar(
                    booking: booking,
                    dates: dates,
                    startDate: startDate
                )
            }
        }
        .frame(height: rowHeight)
    }

    private func bookingBar(
        booking: Booking,
        dates: [String],
        startDate: String
    ) -> some View {
        let checkinDateStr = booking.checkinDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkoutDateStr = booking.checkoutDate.trimmingCharacters(in: .whitespacesAndNewlines)

        let checkinIdx = dates.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == checkinDateStr } ?? -1
        let checkoutIdx = dates.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == checkoutDateStr } ?? -1

        if let firstDate = dates.first, checkoutDateStr == firstDate.trimmingCharacters(in: .whitespacesAndNewlines) {
            return AnyView(EmptyView())
        }

        guard checkoutIdx >= 0 else {
            return AnyView(EmptyView())
        }

        let totalDays = dates.count
        let clampedCheckinIdx: Int
        if checkinIdx < 0 {
            clampedCheckinIdx = 0
        } else {
            clampedCheckinIdx = min(checkinIdx, totalDays - 1)
        }

        let clampedCheckoutIdx = max(0, min(checkoutIdx, totalDays - 1))

        guard clampedCheckoutIdx >= clampedCheckinIdx else {
            return AnyView(EmptyView())
        }

        let startOffset = CGFloat(clampedCheckinIdx) * dayWidth + dayWidth / 2
        let endOffset = CGFloat(clampedCheckoutIdx) * dayWidth + dayWidth / 2
        let barWidth = max(dayWidth / 2, endOffset - startOffset)

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        dateFormatter.dateFormat = "MM/dd"

        let checkinStr: String
        let checkoutStr: String

        if let checkinDate = parseDate(booking.checkinDate),
           let checkoutDate = parseDate(booking.checkoutDate) {
            checkinStr = dateFormatter.string(from: checkinDate)
            checkoutStr = dateFormatter.string(from: checkoutDate)
        } else {
            checkinStr = booking.checkinDate
            checkoutStr = booking.checkoutDate
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 4) {
                    Text(booking.userName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                        .lineLimit(1)

                    if booking.checkedIn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }

                    Spacer()
                }

                let guestText = formatGuestCount(adults: booking.guestsCount, children: booking.childrenCount)
                let dateText = !guestText.isEmpty
                    ? "\(checkinStr) - \(checkoutStr) • \(guestText)"
                    : "\(checkinStr) - \(checkoutStr)"
                Text(dateText)
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.8))
                    .lineLimit(1)

                if let carInfo = booking.carInfo, !carInfo.isEmpty {
                    Text(carInfo)
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: barWidth, height: calculateBookingBarHeight(hasCarInfo: booking.carInfo != nil && !booking.carInfo!.isEmpty, hasGuests: booking.guestsCount > 0 || booking.childrenCount > 0), alignment: .leading)
            .background(Color.blue.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(x: startOffset)
        )
    }

    private func formatGuestCount(adults: Int, children: Int) -> String {
        var parts: [String] = []
        if adults > 0 {
            parts.append(adults == 1 ? "1 adult" : "\(adults) adults")
        }
        if children > 0 {
            parts.append(children == 1 ? "1 child" : "\(children) children")
        }
        return parts.joined(separator: ", ")
    }

    private func calculateBookingBarHeight(hasCarInfo: Bool, hasGuests: Bool) -> CGFloat {
        var height: CGFloat = 8
        height += 18
        height += 3
        height += 16
        if hasCarInfo {
            height += 3
            height += 14
        }
        return min(height, rowHeight - 2)
    }

    private func parseDate(_ dateStr: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.date(from: dateStr)
    }

    private func dateRangeText(startDate: String, endDate: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "MMMM dd"

        guard let start = parseDate(startDate),
              let end = parseDate(endDate) else {
            return "\(startDate) - \(endDate)"
        }

        let startStr = formatter.string(from: start)
        formatter.dateFormat = "MMMM dd, yyyy"
        let endStr = formatter.string(from: end)

        return "\(startStr) - \(endStr)"
    }
}

@available(iOS 18.0, *)
private struct ReservationsTableWrapper: View {
    let data: String

    var body: some View {
        ReservationsTableContent(data: data)
    }
}

@available(iOS 18.0, *)
private struct ReservationsTableContent: View {
    let data: String

    private var reservationsData: ReservationsData? {
        let decodedString = data
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        guard let jsonData = decodedString.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ReservationsData.self, from: jsonData)
        } catch {
            print("[TahoeStayingWithTabs] Failed to decode reservations JSON: \(error)")
            return nil
        }
    }

    var body: some View {
        if let data = reservationsData {
            ReservationsTableContentView(data: data)
        } else {
            VStack(spacing: 12) {
                Text("Loading reservations...")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// Extract the reservations table view content
@available(iOS 18.0, *)
private struct ReservationsTableContentView: View {
    let data: ReservationsData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Reservations")
                    .font(.system(size: 28, weight: .bold))
                
                Text("\(data.reservations.count) reservation\(data.reservations.count == 1 ? "" : "s")")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            // Table
            if data.reservations.isEmpty {
                VStack(spacing: 12) {
                    Text("No reservations found")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(data.reservations) { reservation in
                            reservationRow(reservation: reservation)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func reservationRow(reservation: Reservation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(reservation.userName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                if reservation.checkedIn {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text("Checked in")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(reservation.roomNames)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Check-in:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text(formatDate(reservation.checkinDate))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    HStack(spacing: 4) {
                        Text("Check-out:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text(formatDate(reservation.checkoutDate))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }

            let guestText = formatGuestCount(adults: reservation.guestsCount, children: reservation.childrenCount)
            if !guestText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(guestText)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
            }

            if let carInfo = reservation.carInfo, !carInfo.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(carInfo)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .bottom
        )
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        
        guard let date = formatter.date(from: dateStr) else {
            return dateStr
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        displayFormatter.dateFormat = "MMMM dd, yyyy"
        
        return displayFormatter.string(from: date)
    }

    private func formatGuestCount(adults: Int, children: Int) -> String {
        var parts: [String] = []
        if adults > 0 {
            parts.append(adults == 1 ? "1 adult" : "\(adults) adults")
        }
        if children > 0 {
            parts.append(children == 1 ? "1 child" : "\(children) children")
        }
        return parts.joined(separator: ", ")
    }
}

// Reuse data models from existing components
private struct Room: Codable {
    let id: String
    let name: String
}

private struct Booking: Codable {
    let id: String
    let userName: String
    let checkinDate: String
    let checkoutDate: String
    let checkedIn: Bool
    let carInfo: String?
    let guestsCount: Int
    let childrenCount: Int
}

private struct CalendarData: Codable {
    let rooms: [Room]
    let calendarDates: [String]
    let bookingsByRoom: [String: [Booking]]
    let today: String
    let calendarStartDate: String
    let calendarEndDate: String
}

private struct Reservation: Codable, Identifiable {
    let id: String
    let userName: String
    let roomNames: String
    let checkinDate: String
    let checkoutDate: String
    let checkedIn: Bool
    let carInfo: String?
    let guestsCount: Int
    let childrenCount: Int
}

private struct ReservationsData: Codable {
    let reservations: [Reservation]
}

// Reuse SynchronizedScrollView from RoomCalendarView
@available(iOS 18.0, *)
private struct SynchronizedScrollView<HeaderContent: View, BodyContent: View>: View {
    let headerContent: () -> HeaderContent
    let bodyContent: () -> BodyContent
    @Binding var verticalScrollOffset: CGFloat
    @Binding var userIsScrollingCalendar: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerContent()
                ScrollView(.vertical, showsIndicators: true) {
                    bodyContent()
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    userIsScrollingCalendar = (newPhase != .idle)
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                    geometry.contentOffset.y
                }, action: { oldValue, newValue in
                    if userIsScrollingCalendar {
                        verticalScrollOffset = newValue
                    }
                })
            }
        }
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @available(iOS 18.0, *)
    @Addon
    struct TahoeStayingWithTabsView<Root: RootRegistry> {
        enum TagName: String {
            case tahoeStayingWithTabs = "TahoeStayingWithTabs"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .tahoeStayingWithTabs:
                TahoeStayingWithTabs<Root>(element: element)
            }
        }
    }
}
