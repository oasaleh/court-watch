//
//  FacilitySearch.swift
//  CourtWatch
//
//  Matching a typed query against a facility name.
//
//  This exists because the obvious one-liner is wrong in a way that is
//  invisible on a developer's machine. `localizedStandardContains` is the API
//  Apple recommends for user-facing search, and it returns **false** when the
//  query contains U+2019 RIGHT SINGLE QUOTATION MARK and the name contains
//  U+0027 APOSTROPHE. iOS smart punctuation inserts U+2019 whenever anyone
//  types `'` on the software keyboard, and every name in the data uses U+0027.
//  So a user searching for "Harper's" is shown an empty list for a place one
//  scroll away — no error, nothing to indicate the app is not simply missing
//  it. A Mac keyboard sends U+0027 and never reproduces this.
//
//  The fix is one fold applied to both sides. That it is a single named
//  function is the point, not an accident of tidiness: the realistic mistake
//  here is not the fold but an **asymmetric** fold — normalizing the query and
//  not the name — which yields a search that is correct for 25 of the 27
//  places and looks right in review. Passing both arguments through the same
//  function makes that mistake unwritable.
//
//  There are 27 names in a list the user can already see. Substring matching
//  is the correct amount of machinery; ranking or fuzzy matching would add a
//  second unpinned rule beside the name derivation this app is already
//  careful about.
//

import Foundation

nonisolated enum FacilitySearch {

    /// Apostrophes as keyboards, autocorrect and paste buffers produce them.
    ///
    /// U+2019 is the one that matters — it is what iOS substitutes by default.
    /// The rest cost nothing to accept and each is something a real input
    /// method or a copied web page can deliver.
    private static let apostropheVariants: [String] = [
        "\u{2019}",  // RIGHT SINGLE QUOTATION MARK — iOS smart punctuation
        "\u{2018}",  // LEFT SINGLE QUOTATION MARK
        "\u{02BC}",  // MODIFIER LETTER APOSTROPHE
        "\u{FF07}",  // FULLWIDTH APOSTROPHE
        "\u{0060}",  // GRAVE ACCENT, produced by some keyboard layouts
    ]

    /// The form a name is compared in.
    ///
    /// Apostrophes are normalized and then *dropped*. Normalizing alone would
    /// fix the smart-quote case and still fail "harpers", which is how people
    /// actually type. Dropping was checked against the real data: the 27 names
    /// produce 27 distinct keys, so nothing is merged.
    ///
    /// Case and diacritics are deliberately left alone — `localizedStandardContains`
    /// folds both, and doing it twice would gain nothing while adding a second
    /// place for the two sides to disagree.
    static func key(_ text: String) -> String {
        var normalized = text

        for variant in apostropheVariants {
            normalized = normalized.replacingOccurrences(of: variant, with: "\u{0027}")
        }

        return normalized.replacingOccurrences(of: "\u{0027}", with: "")
    }

    /// Whether a facility name should be shown for a typed query.
    ///
    /// Both arguments go through `key`. An empty or whitespace-only query
    /// matches everything, so clearing the search field shows all 27 rather
    /// than none.
    static func matches(facility: String, query: String) -> Bool {
        let needle = key(query).trimmingCharacters(in: .whitespacesAndNewlines)

        guard needle.isEmpty == false else { return true }

        return key(facility).localizedStandardContains(needle)
    }
}
