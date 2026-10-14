import Foundation

/// The value without surrounding spaces or line breaks, or nil when nothing is left.
func nonBlank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}
