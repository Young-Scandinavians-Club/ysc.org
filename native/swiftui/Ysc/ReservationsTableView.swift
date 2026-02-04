//
//  ReservationsTableView.swift
//  Ysc
//
//  Table component for displaying detailed reservation information

import SwiftUI
import LiveViewNative

// Data models for reservations table
struct Reservation: Codable, Identifiable {
    let id: String  // ULID as string
    let userName: String
    let roomNames: String
    let checkinDate: String  // ISO8601 date string
    let checkoutDate: String // ISO8601 date string
    let checkedIn: Bool
    let carInfo: String?  // Optional car information
    let guestsCount: Int  // Number of adults
    let childrenCount: Int  // Number of children
}

struct ReservationsData: Codable {
    let reservations: [Reservation]
}

@available(iOS 18.0, *)
@LiveElement
struct ReservationsTable<Root: RootRegistry>: View {
    let element: ElementNode

    // Parse data from element attributes
    private var reservationsData: ReservationsData? {
        guard let dataString = element.attributeValue(for: "data"), !dataString.isEmpty else {
            return nil
        }

        // Decode HTML entities (LiveView Native HTML-encodes JSON attributes)
        // Must decode in order: &amp; first, then others
        let decodedString = dataString
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        guard let data = decodedString.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ReservationsData.self, from: data)
        } catch {
            print("[ReservationsTable] Failed to decode JSON: \(error)")
            return nil
        }
    }

    var body: some View {
        Group {
            if let data = reservationsData {
                reservationsTableView(data: data)
            } else {
                VStack(spacing: 12) {
                    Text("Loading reservations...")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func reservationsTableView(data: ReservationsData) -> some View {
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
            .background(.white)

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
            // Name and check-in status
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

            // Room names
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text(reservation.roomNames)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
            }

            // Dates
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

            // Guests
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

            // Car info
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

    // Helper functions
    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") // Use PST/PDT
        
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
            if adults == 1 {
                parts.append("1 adult")
            } else {
                parts.append("\(adults) adults")
            }
        }

        if children > 0 {
            if children == 1 {
                parts.append("1 child")
            } else {
                parts.append("\(children) children")
            }
        }

        return parts.joined(separator: ", ")
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @available(iOS 18.0, *)
    @Addon
    struct ReservationsTableView<Root: RootRegistry> {
        enum TagName: String {
            case reservationsTable = "ReservationsTable"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .reservationsTable:
                ReservationsTable<Root>(element: element)
            }
        }
    }
}
