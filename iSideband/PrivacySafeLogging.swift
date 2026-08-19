import Foundation

/// Intentionally discards legacy console diagnostics.
///
/// The app previously printed packet bytes, message text, attachment paths,
/// peer identifiers, and identity hashes. User-facing status properties remain
/// available for troubleshooting without exposing private content to device
/// logs in Debug or Release builds.
func privacySafeLog(
    _ items: Any...,
    separator: String = " ",
    terminator: String = "\n"
) {
    _ = items
    _ = separator
    _ = terminator
}
