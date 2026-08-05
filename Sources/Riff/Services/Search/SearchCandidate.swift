import Foundation

/// A precomputed, indexable description of one application. Every field is
/// derived deterministically from the app itself; curated aliases only fill
/// the small gap where a brand name shares no letters with any derived form.
struct SearchCandidate: Sendable {
    let application: ApplicationRecord
    let components: [String]      // cleanshot, x
    let initials: String          // csx
    let localizedNames: [String]  // from the bundle's InfoPlist.strings
    let pinyinVariants: [String]  // wei xin, weixin, wx
    let aliases: [String]         // curated brand aliases
}
