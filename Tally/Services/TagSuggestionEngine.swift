import Foundation

/// Matches receipt context (merchant + notes text) against the user's tag list
/// to produce a single best-guess suggestion shown in the "Tally Suggests" banner.
enum TagSuggestionEngine {

    struct Suggestion {
        let tag: TagModel
        /// Human-readable description of why we suggested this tag.
        /// e.g. "looks like a dining or food purchase"
        let reason: String
    }

    /// Returns the best matching tag for the given receipt context, or nil if no
    /// confident match is found.
    ///
    /// - Parameters:
    ///   - merchant: OCR-extracted or manually entered merchant name.
    ///   - notes: OCR-extracted or manually entered notes/description.
    ///   - tags: All `TagModel` instances available to the user.
    static func suggest(merchant: String, notes: String, tags: [TagModel]) -> Suggestion? {
        let corpus = [merchant, notes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        guard !corpus.isEmpty else { return nil }

        // Each rule maps a set of receipt keywords to candidate tag-name fragments
        // and a short human-readable reason string.
        let rules: [(keywords: [String], tagHints: [String], reason: String)] = [
            (
                ["restaurant", "cafe", "coffee", "bistro", "kitchen", "eatery",
                 "burger", "pizza", "sushi", "noodle", "curry", "bakery", "deli",
                 "diner", "breakfast", "lunch", "dinner", "brunch", "takeaway",
                 "take away", "takeout", "ubereats", "doordash", "menulog"],
                ["dining", "food", "meals", "eat", "drink", "restaurant"],
                "dining or food purchase"
            ),
            (
                ["uber", "lyft", "ola", "taxi", "cab", "bus ticket", "train",
                 "metro", "tram", "ferry", "petrol", "fuel", "gas station",
                 "parking", "toll", "transit"],
                ["transport", "travel", "transit", "commute"],
                "transport or travel expense"
            ),
            (
                ["woolworths", "coles", "aldi", "costco", "safeway",
                 "supermarket", "fresh market", "produce", "greengrocer",
                 "grocery"],
                ["groceries", "grocery", "supermarket"],
                "grocery purchase"
            ),
            (
                ["netflix", "spotify", "hulu", "disney+", "apple tv",
                 "apple one", "google play", "icloud", "subscription",
                 "monthly plan", "annual plan", "membership fee"],
                ["subscription", "subscriptions", "streaming", "software"],
                "subscription or software service"
            ),
            (
                ["pharmacy", "chemist", "medical centre", "doctor", "hospital",
                 "clinic", "health", "gym", "fitness", "wellness", "dentist",
                 "optical", "physiotherapy"],
                ["health", "medical", "wellbeing", "fitness"],
                "health or medical purchase"
            ),
            (
                ["amazon", "ebay", "shop", "store", "clothing", "apparel",
                 "fashion", "shoes", "accessories", "department store",
                 "outlet", "zara", "uniqlo"],
                ["shopping", "retail", "clothing", "fashion"],
                "shopping purchase"
            ),
            (
                ["bunnings", "home depot", "hardware", "tools", "home improvement",
                 "plumbing", "electrical", "furniture", "ikea", "kmart", "target"],
                ["home improvement", "hardware", "tools", "furniture"],
                "home or hardware purchase"
            ),
            (
                ["office", "stationery", "printer", "supplies", "equipment",
                 "work expense", "business"],
                ["work", "office", "business", "stationery"],
                "work or office purchase"
            ),
            (
                ["hotel", "airbnb", "motel", "hostel", "accommodation", "resort",
                 "flight", "airline", "airport", "booking.com", "expedia"],
                ["accommodation", "travel", "holiday", "flights"],
                "accommodation or travel booking"
            ),
            (
                ["electricity", "gas bill", "water bill", "internet",
                 "phone bill", "telstra", "optus", "vodafone", "insurance",
                 "utility", "utilities", "council rates"],
                ["utilities", "bills", "phone", "insurance"],
                "utility or bill payment"
            ),
        ]

        for rule in rules {
            for keyword in rule.keywords where corpus.contains(keyword) {
                for hint in rule.tagHints {
                    // Prefer non-system tags first so user's custom tags win
                    if let match = tags.first(where: {
                        !$0.isSystemTag && $0.name.lowercased().contains(hint)
                    }) ?? tags.first(where: {
                        $0.name.lowercased().contains(hint)
                    }) {
                        return Suggestion(tag: match, reason: rule.reason)
                    }
                }
            }
        }

        return nil
    }
}
