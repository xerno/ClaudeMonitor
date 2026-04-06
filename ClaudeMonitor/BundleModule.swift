import Foundation

// When compiled directly with swiftc (build.sh), SPM does not generate
// resource_bundle_accessor.swift, so Bundle.module is undefined.
// In that context the app bundle IS the main bundle, so we alias them.
// In SPM builds, SWIFT_PACKAGE is defined and this block is skipped;
// SPM's generated resource_bundle_accessor.swift takes over instead.
#if !SWIFT_PACKAGE
extension Bundle {
    static var module: Bundle { .main }
}
#endif
