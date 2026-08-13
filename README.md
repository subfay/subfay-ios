# Subfay iOS SDK

Swift SDK for integrating Subfay into your iOS, macOS, tvOS, and watchOS apps.

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager

Add Subfay to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/subfay-ios-sdk.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter repository URL
3. Select version

### CocoaPods

```ruby
pod 'Subfay', '~> 1.0'
```

## Quick Start

### 1. Configure SDK

In your `AppDelegate` or `@main` App struct:

```swift
import Subfay

// AppDelegate
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    Subfay.configure(
        apiKey: "your_api_key_here",
        environment: .production
    )
    return true
}

// SwiftUI App
@main
struct MyApp: App {
    init() {
        Subfay.configure(
            apiKey: "your_api_key_here",
            environment: .production
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Identify User

After user logs in:

```swift
Task {
    try await Subfay.identify(externalUserId: "user_123")
}
```

### 3. Check Entitlements

```swift
// Check single entitlement
let hasPremium = try await Subfay.hasEntitlement("premium_access")

if hasPremium {
    // Show premium features
} else {
    // Show paywall
}

// Get all entitlements
let entitlements = try await Subfay.getEntitlements()
print("User has: \(entitlements)")
```

## Advanced Usage

### Observe Entitlement Changes

#### Using Combine

```swift
import Combine

var cancellables = Set<AnyCancellable>()

Subfay.entitlementsPublisher
    .sink { entitlements in
        print("Entitlements updated: \(entitlements)")
        self.updateUI()
    }
    .store(in: &cancellables)
```

#### Using Callback

```swift
let subscription = Subfay.observeEntitlements { entitlements in
    print("Entitlements: \(entitlements)")
}

// Cancel when done
subscription.cancel()
```

### SwiftUI Integration

#### Conditional View Based on Entitlement

```swift
import SwiftUI
import Subfay

struct ContentView: View {
    @State private var hasPremium = false

    var body: some View {
        VStack {
            if hasPremium {
                PremiumFeatures()
            } else {
                FreeFeatures()
                PaywallButton()
            }
        }
        .task {
            hasPremium = (try? await Subfay.hasEntitlement("premium_access")) ?? false
        }
    }
}
```

#### Using View Modifier

```swift
PremiumContent()
    .requiresEntitlement("premium_access")
```

### Configuration Options

```swift
let options = ConfigOptions(
    cacheExpiration: 3600,      // 1 hour
    automaticSync: true,         // Auto-sync on app launch
    logLevel: .debug,            // Verbose logging
    timeout: 30,                 // 30 second timeout
    baseURL: nil                 // Use default URL
)

Subfay.configure(
    apiKey: "your_api_key",
    environment: .production,
    options: options
)
```

### Manual Sync

Force refresh entitlements from server:

```swift
let entitlements = try await Subfay.syncEntitlements()
```

### Logout

Clear user data:

```swift
Subfay.logout()
```

## UIKit Example

```swift
import UIKit
import Subfay

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            await checkPremiumAccess()
        }
    }

    func checkPremiumAccess() async {
        do {
            let hasPremium = try await Subfay.hasEntitlement("premium_access")

            if hasPremium {
                showPremiumContent()
            } else {
                showPaywall()
            }
        } catch {
            print("Error checking entitlement: \(error)")
        }
    }

    func showPremiumContent() {
        // Show premium UI
    }

    func showPaywall() {
        // Show paywall
    }
}
```

## SwiftUI Example

```swift
import SwiftUI
import Subfay

@main
struct MyApp: App {
    init() {
        Subfay.configure(
            apiKey: "your_api_key",
            environment: .production
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.hasPremium {
                    PremiumView()
                } else {
                    FreeView()
                }
            }
            .navigationTitle("My App")
        }
        .task {
            await viewModel.identifyUser()
        }
    }
}

@MainActor
class ContentViewModel: ObservableObject {
    @Published var hasPremium = false
    @Published var isLoading = true

    func identifyUser() async {
        do {
            try await Subfay.identify(externalUserId: "user_123")
            hasPremium = try await Subfay.hasEntitlement("premium_access")
        } catch {
            print("Error: \(error)")
        }
        isLoading = false
    }
}
```

## Error Handling

```swift
do {
    let entitlements = try await Subfay.getEntitlements()
} catch SubfayError.networkError(let message) {
    print("Network error: \(message)")
} catch SubfayError.authenticationError(let message) {
    print("Auth error: \(message)")
} catch SubfayError.serverError(let statusCode, let message) {
    print("Server error \(statusCode): \(message)")
} catch {
    print("Unknown error: \(error)")
}
```

## Testing

### Mock SDK for Testing

```swift
#if DEBUG
// Use mock data in tests
Subfay.configure(
    apiKey: "test_key",
    environment: .sandbox
)
#endif
```

### UI Tests

```swift
import XCTest
import Subfay

class MyAppUITests: XCTestCase {
    func testPremiumFeatureAccess() async throws {
        // Identify test user
        try await Subfay.identify(externalUserId: "test_user")

        // Check entitlement
        let hasPremium = try await Subfay.hasEntitlement("premium_access")
        XCTAssertTrue(hasPremium)
    }
}
```

## Best Practices

1. **Configure Once**: Call `configure()` only once at app launch
2. **Identify After Login**: Call `identify()` after user authenticates
3. **Logout on Sign Out**: Call `logout()` when user signs out
4. **Handle Errors**: Always handle potential errors with try/catch
5. **Cache**: SDK automatically caches entitlements for 1 hour
6. **Background Sync**: SDK syncs on app launch if cache is stale
7. **Offline Support**: Cached entitlements work offline

## Migration from RevenueCat

### Before (RevenueCat)

```swift
import RevenueCat

Purchases.configure(withAPIKey: "rc_api_key")

Purchases.shared.getCustomerInfo { customerInfo, error in
    if customerInfo?.entitlements["premium"]?.isActive == true {
        // Show premium
    }
}
```

### After (Subfay)

```swift
import Subfay

Subfay.configure(apiKey: "your_api_key", environment: .production)

Task {
    try await Subfay.identify(externalUserId: "user_123")
    let hasPremium = try await Subfay.hasEntitlement("premium_access")
    // Show premium
}
```

## Troubleshooting

### SDK Not Configured Error

Make sure you call `Subfay.configure()` before using any other methods.

### Authentication Error

Call `Subfay.identify()` before checking entitlements.

### Network Errors

Check internet connectivity and API key validity.

### Cache Issues

Clear cache manually:
```swift
Subfay.logout()  // Clears all cached data
```

## Performance

- **Initial Load**: < 100ms (from cache)
- **Network Request**: < 500ms (typical)
- **Memory Usage**: < 5MB
- **Cache Size**: < 1MB

## Support

- **Documentation**: https://docs.subfay.com
- **API Reference**: https://docs.subfay.com/ios
- **GitHub Issues**: https://github.com/yourusername/subfay-ios-sdk/issues
- **Email**: support@subfay.com

## License

MIT License - see LICENSE file for details

---

**Version**: 1.0.0
**Last Updated**: January 2026
