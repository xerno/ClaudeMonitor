import Foundation

// build.sh compiles with plain swiftc, where SPM generates no Bundle.module; the app bundle is
// the main bundle.
#if !SWIFT_PACKAGE
extension Bundle {
    static var module: Bundle { .main }
}
#endif
