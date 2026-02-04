//
//  CabinRulesView.swift
//  Ysc
//
//  Split-view sidebar component for displaying Tahoe cabin rules

import SwiftUI
import LiveViewNative

// Data models
struct RuleCategory: Codable, Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct RuleItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String

    // Custom decoding to generate ID if not present in JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        // Generate ID since it's not in the JSON
        id = UUID()
    }

    enum CodingKeys: String, CodingKey {
        case title
        case content
    }
}

struct RulesData: Codable {
    let categories: [RuleCategory]
    let rules: [String: [RuleItem]]
}

@LiveElement
struct CabinRules<Root: RootRegistry>: View {
    let element: ElementNode
    @Event("select_category", type: "click") private var selectCategory

    @State private var selectedCategory: String?

    // Parse data from element attributes
    private var rulesData: RulesData? {
        guard let dataString = element.attributeValue(for: "data") as? String else {
            return nil
        }

        // Decode HTML entities
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
            return try JSONDecoder().decode(RulesData.self, from: data)
        } catch {
            print("[CabinRules] JSON decode error: \(error)")
            return nil
        }
    }

    var body: some View {
        if let data = rulesData {
            splitView(data: data)
        } else {
            VStack(spacing: 12) {
                Text("Loading rules...")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func splitView(data: RulesData) -> some View {
        let categoryId = selectedCategory ?? data.categories.first?.id ?? ""
        HStack(alignment: .top, spacing: 0) {
            sidebarView(data: data)
            Divider()
            contentView(data: data, categoryId: categoryId)
        }
        .onAppear {
            updateSelectedCategory(from: data)
        }
        .onChange(of: element.attributeValue(for: "selectedCategory")) { _ in
            updateSelectedCategory(from: data)
        }
    }

    @ViewBuilder
    private func sidebarView(data: RulesData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cabin Guide")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(data.categories) { category in
                        categoryButton(category: category)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 300)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private func categoryButton(category: RuleCategory) -> some View {
        let isSelected = selectedCategory == category.id
        Button(action: {
            // Notify inactivity timer of user interaction
            NotificationCenter.default.post(name: NSNotification.Name("UserInteraction"), object: nil)
            selectedCategory = category.id
            selectCategory(value: ["category": category.id])
        }) {
            HStack(spacing: 16) {
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 32)

                Text(category.title)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(minHeight: 60)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.15))
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentView(data: RulesData, categoryId: String) -> some View {
        if let rules = data.rules[categoryId] {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    categoryHeader(data: data, categoryId: categoryId)
                    rulesList(rules: rules)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Text("Select a category")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func categoryHeader(data: RulesData, categoryId: String) -> some View {
        if let category = data.categories.first(where: { $0.id == categoryId }) {
            HStack(spacing: 16) {
                Image(systemName: category.icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)

                Text(category.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func rulesList(rules: [RuleItem]) -> some View {
        ForEach(rules) { rule in
            VStack(alignment: .leading, spacing: 12) {
                // Special styling for TL;DR sections
                if rule.title.uppercased() == "TL;DR" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        Text(rule.content)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if rule.title == "Checklist" {
                    checklistView(rule: rule)
                } else {
                    // Regular rule item
                    VStack(alignment: .leading, spacing: 12) {
                        Text(rule.title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(rule.content)
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func updateSelectedCategory(from data: RulesData) {
        if let categoryId = element.attributeValue(for: "selectedCategory") as? String, !categoryId.isEmpty {
            selectedCategory = categoryId
        } else if selectedCategory == nil, let firstCategory = data.categories.first {
            selectedCategory = firstCategory.id
        }
    }

    @ViewBuilder
    private func checklistView(rule: RuleItem) -> some View {
        let checklistItems = rule.content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: 12) {
            Text(rule.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.bottom, 4)

            ForEach(Array(checklistItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .padding(.top, 2)

                    Text(item.replacingOccurrences(of: "□", with: "").trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 17))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct CabinRulesView<Root: RootRegistry> {
        enum TagName: String {
            case cabinRules = "CabinRulesView"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .cabinRules:
                CabinRules<Root>(element: element)
            }
        }
    }
}
