import Foundation
import Combine

/// InApp Platform Swift SDK
/// Provides seamless entitlement management for iOS apps
public final class InAppSDK {

    // MARK: - Singleton

    public static let shared = InAppSDK()
    private init() {}

    // MARK: - Configuration

    private var configuration: Configuration?
    private var apiClient: APIClient?
    private var cacheManager: CacheManager?

    /// Configure the SDK with API credentials
    /// - Parameters:
    ///   - apiKey: Your API key from InApp Platform dashboard
    ///   - environment: The environment (.production or .sandbox)
    ///   - options: Optional configuration options
    public static func configure(
        apiKey: String,
        environment: Environment = .production,
        options: ConfigOptions = ConfigOptions()
    ) {
        let config = Configuration(
            apiKey: apiKey,
            environment: environment,
            options: options
        )

        shared.configuration = config
        shared.apiClient = APIClient(configuration: config)
        shared.cacheManager = CacheManager(configuration: config)

        InAppLogger.shared.log("SDK configured for \(environment)", level: .info)
    }

    // MARK: - Customer Management

    private var currentCustomer: Customer?

    /// Identify the current user
    /// - Parameter externalUserId: Your app's user identifier
    /// - Returns: The identified customer
    @discardableResult
    public static func identify(externalUserId: String) async throws -> Customer {
        try shared.ensureConfigured()

        InAppLogger.shared.log("Identifying user: \(externalUserId)", level: .debug)

        let customer = Customer(
            id: UUID().uuidString,
            externalId: externalUserId,
            email: nil,
            displayName: nil
        )

        shared.currentCustomer = customer
        shared.cacheManager?.saveCustomer(customer)

        // Fetch entitlements after identification
        try await shared.syncEntitlements()

        return customer
    }

    /// Get the currently identified customer
    /// - Returns: The current customer, or nil if not identified
    public static func getCurrentCustomer() -> Customer? {
        return shared.currentCustomer ?? shared.cacheManager?.loadCustomer()
    }

    /// Logout the current user
    public static func logout() {
        shared.currentCustomer = nil
        shared.cacheManager?.clearAll()
        shared.entitlementsSubject.send([])
        InAppLogger.shared.log("User logged out", level: .info)
    }

    // MARK: - Entitlements

    private let entitlementsSubject = CurrentValueSubject<[String], Never>([])

    /// Get all entitlements for the current user
    /// - Returns: Array of entitlement keys
    public static func getEntitlements() async throws -> [String] {
        try shared.ensureConfigured()

        guard let customer = getCurrentCustomer() else {
            throw InAppError.authenticationError(message: "No customer identified. Call identify() first.")
        }

        // Try cache first
        if let cached = shared.cacheManager?.loadEntitlements(),
           !shared.cacheManager!.isCacheExpired() {
            InAppLogger.shared.log("Entitlements loaded from cache", level: .debug)
            return cached
        }

        // Fetch from server
        return try await shared.fetchEntitlementsFromServer(customer: customer)
    }

    /// Check if user has a specific entitlement
    /// - Parameter key: The entitlement key to check
    /// - Returns: True if user has the entitlement
    public static func hasEntitlement(_ key: String) async throws -> Bool {
        let entitlements = try await getEntitlements()
        return entitlements.contains(key)
    }

    /// Observe entitlement changes in real-time
    /// - Parameter callback: Called whenever entitlements change
    /// - Returns: AnyCancellable to manage the subscription
    public static func observeEntitlements(
        _ callback: @escaping ([String]) -> Void
    ) -> AnyCancellable {
        return shared.entitlementsSubject
            .removeDuplicates()
            .sink { entitlements in
                callback(entitlements)
            }
    }

    /// Publisher for reactive programming with Combine
    public static var entitlementsPublisher: AnyPublisher<[String], Never> {
        return shared.entitlementsSubject
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Manually sync entitlements from server
    /// - Returns: Updated entitlements
    @discardableResult
    public static func syncEntitlements() async throws -> [String] {
        try shared.ensureConfigured()

        guard let customer = getCurrentCustomer() else {
            throw InAppError.authenticationError(message: "No customer identified")
        }

        return try await shared.fetchEntitlementsFromServer(customer: customer)
    }

    // MARK: - Private Methods

    private func ensureConfigured() throws {
        guard configuration != nil else {
            throw InAppError.invalidConfiguration(
                message: "SDK not configured. Call InAppSDK.configure() first."
            )
        }
    }

    private func fetchEntitlementsFromServer(customer: Customer) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw InAppError.invalidConfiguration(message: "API client not initialized")
        }

        InAppLogger.shared.log("Fetching entitlements from server", level: .debug)

        let entitlements = try await apiClient.fetchEntitlements(
            externalCustomerId: customer.externalId
        )

        // Update cache
        cacheManager?.saveEntitlements(entitlements)

        // Notify observers
        entitlementsSubject.send(entitlements)

        InAppLogger.shared.log("Entitlements updated: \(entitlements)", level: .info)

        return entitlements
    }
}

// MARK: - Models

public struct Customer: Codable {
    public let id: String
    public let externalId: String
    public let email: String?
    public let displayName: String?
}

public struct Configuration {
    let apiKey: String
    let environment: Environment
    let options: ConfigOptions
}

public struct ConfigOptions {
    public let cacheExpiration: TimeInterval
    public let automaticSync: Bool
    public let logLevel: LogLevel
    public let timeout: TimeInterval
    public let baseURL: String?

    public init(
        cacheExpiration: TimeInterval = 3600, // 1 hour
        automaticSync: Bool = true,
        logLevel: LogLevel = .info,
        timeout: TimeInterval = 30,
        baseURL: String? = nil
    ) {
        self.cacheExpiration = cacheExpiration
        self.automaticSync = automaticSync
        self.logLevel = logLevel
        self.timeout = timeout
        self.baseURL = baseURL
    }
}

public enum Environment {
    case production
    case sandbox

    var baseURL: String {
        switch self {
        case .production:
            return "https://api.inappplatform.com"
        case .sandbox:
            return "https://sandbox-api.inappplatform.com"
        }
    }
}

public enum LogLevel: Int {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5
}

// MARK: - Errors

public enum InAppError: LocalizedError {
    case networkError(message: String)
    case authenticationError(message: String)
    case invalidConfiguration(message: String)
    case serverError(statusCode: Int, message: String)
    case cacheError(message: String)
    case unknown(error: Error)

    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Client

internal class APIClient {
    private let configuration: Configuration
    private let session: URLSession

    init(configuration: Configuration) {
        self.configuration = configuration

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.options.timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    func fetchEntitlements(externalCustomerId: String) async throws -> [String] {
        let baseURL = configuration.options.baseURL ?? configuration.environment.baseURL
        let urlString = "\(baseURL)/entitlements/\(externalCustomerId)"

        guard let url = URL(string: urlString) else {
            throw InAppError.invalidConfiguration(message: "Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("InAppSDK/iOS/1.0.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InAppError.networkError(message: "Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InAppError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorMessage
            )
        }

        let apiResponse = try JSONDecoder().decode(EntitlementsResponse.self, from: data)
        return apiResponse.data.entitlements
    }

    private struct EntitlementsResponse: Codable {
        let success: Bool
        let data: EntitlementsData
    }

    private struct EntitlementsData: Codable {
        let customerId: String
        let entitlements: [String]
    }
}

// MARK: - Cache Manager

internal class CacheManager {
    private let configuration: Configuration
    private let userDefaults = UserDefaults.standard

    private enum Keys {
        static let customer = "inapp_customer"
        static let entitlements = "inapp_entitlements"
        static let lastSync = "inapp_last_sync"
    }

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func saveCustomer(_ customer: Customer) {
        if let encoded = try? JSONEncoder().encode(customer) {
            userDefaults.set(encoded, forKey: Keys.customer)
        }
    }

    func loadCustomer() -> Customer? {
        guard let data = userDefaults.data(forKey: Keys.customer) else {
            return nil
        }
        return try? JSONDecoder().decode(Customer.self, from: data)
    }

    func saveEntitlements(_ entitlements: [String]) {
        userDefaults.set(entitlements, forKey: Keys.entitlements)
        userDefaults.set(Date(), forKey: Keys.lastSync)
    }

    func loadEntitlements() -> [String]? {
        return userDefaults.stringArray(forKey: Keys.entitlements)
    }

    func isCacheExpired() -> Bool {
        guard let lastSync = userDefaults.object(forKey: Keys.lastSync) as? Date else {
            return true
        }

        let elapsed = Date().timeIntervalSince(lastSync)
        return elapsed > configuration.options.cacheExpiration
    }

    func clearAll() {
        userDefaults.removeObject(forKey: Keys.customer)
        userDefaults.removeObject(forKey: Keys.entitlements)
        userDefaults.removeObject(forKey: Keys.lastSync)
    }
}

// MARK: - Logger

internal class InAppLogger {
    static let shared = InAppLogger()
    private init() {}

    private var logLevel: LogLevel = .info

    func setLogLevel(_ level: LogLevel) {
        self.logLevel = level
    }

    func log(_ message: String, level: LogLevel) {
        guard level.rawValue >= logLevel.rawValue else { return }

        let prefix: String
        switch level {
        case .verbose: prefix = "💬"
        case .debug: prefix = "🔍"
        case .info: prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error: prefix = "❌"
        case .none: return
        }

        print("\(prefix) [InAppSDK] \(message)")
    }
}

// MARK: - SwiftUI Helpers

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 13.0, macOS 10.15, *)
extension View {
    /// Show content only if user has the specified entitlement
    public func requiresEntitlement(_ key: String) -> some View {
        modifier(EntitlementModifier(entitlementKey: key))
    }
}

@available(iOS 13.0, macOS 10.15, *)
private struct EntitlementModifier: ViewModifier {
    let entitlementKey: String
    @State private var hasEntitlement = false
    @State private var isLoading = true

    func body(content: Content) -> some View {
        Group {
            if isLoading {
                ProgressView()
            } else if hasEntitlement {
                content
            } else {
                Text("Premium feature")
                    .foregroundColor(.secondary)
            }
        }
        .task {
            await checkEntitlement()
        }
    }

    private func checkEntitlement() async {
        do {
            hasEntitlement = try await InAppSDK.hasEntitlement(entitlementKey)
        } catch {
            InAppLogger.shared.log("Error checking entitlement: \(error)", level: .error)
        }
        isLoading = false
    }
}
#endif
