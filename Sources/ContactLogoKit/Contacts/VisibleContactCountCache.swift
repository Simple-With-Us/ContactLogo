import Foundation

/// One visible-count enumeration, plus whether a later caller may reuse it.
struct VisibleContactCountPass: Sendable {
    var snapshot: VisibleContactCount
    /// False when the walk was cancelled or the store threw.  Those results
    /// stay uncached so the next caller enumerates again instead of publishing
    /// a partial or empty book.
    var cacheable: Bool
}

/// Remembers one cacheable visible-count pass for the life of a provider.
///
/// `CNContactsProvider` is created for a single refresh.  Cold launch asks
/// that instance twice: `limitedAccessDiagnosis()` reads
/// `visibleContactCount()`, then the launch task reads
/// `visibleContactCountSnapshot()`.  Each of those used to walk the address
/// book.  The second call returns the first cacheable pass.
///
/// The memory is the provider instance, not the process.  The next refresh
/// builds a new provider and enumerates again, so a later scan cannot publish
/// a count from an earlier grant.
actor VisibleContactCountCache {
    private var stored: VisibleContactCount?

    func value(
        _ compute: @Sendable () async -> VisibleContactCountPass
    ) async -> VisibleContactCount {
        if let stored {
            return stored
        }
        let pass = await compute()
        // A concurrent caller may have stored a pass while `compute` ran.
        // Keep the first cacheable result.  This caller still returns the
        // pass it just computed, which is the same result it would have
        // published with no cache.
        if pass.cacheable, stored == nil {
            stored = pass.snapshot
        }
        return pass.snapshot
    }
}
