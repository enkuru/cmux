#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and catches any Objective-C exception it raises, returning the
/// caught exception (or `nil` if it ran cleanly).
///
/// This exists to firewall the macOS 26 AppKit over-budget "Update Constraints
/// in Window" `NSException`. That exception is raised synchronously from inside
/// a libdispatch main-queue block (`scheduleSizeUpdate` -> `updateSize` ->
/// `setPreferredContentSize`). libdispatch's `_dispatch_client_callout` calls
/// `std::terminate` on any exception that propagates through it, so neither
/// AppKit's run-loop handler nor `NSApplicationCrashOnExceptions = NO` can save
/// the app — only an explicit `@try/@catch` around the throwing call can.
/// Swift cannot catch `NSException`, so this thin Objective-C shim provides it.
NSException * _Nullable cmux_runCatchingNSException(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
