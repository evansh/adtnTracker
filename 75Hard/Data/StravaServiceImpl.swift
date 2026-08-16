import Foundation
import AuthenticationServices

actor StravaServiceImpl: StravaService {
    private let clientID = ProcessInfo.processInfo.environment["STRAVA_CLIENT_ID"] ?? ""
    private let clientSecret = ProcessInfo.processInfo.environment["STRAVA_CLIENT_SECRET"] ?? ""
    private let redirectURI = "75hard://strava-callback"
    private let tokenURL = "https://www.strava.com/oauth/token"
    private let activitiesURL = "https://www.strava.com/api/v3/athlete/activities"

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?

    func authenticate() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw StravaError.missingCredentials
        }

        if let savedToken = try? await loadTokens(), savedToken.isValid {
            accessToken = savedToken.accessToken
            refreshToken = savedToken.refreshToken
            tokenExpiry = savedToken.expiry
            return
        }

        try await performOAuthFlow()
    }

    func isAuthenticated() async -> Bool {
        guard let expiry = tokenExpiry else { return false }
        return Date() < expiry
    }

    func fetchActivities(since: Date) async throws -> [ExternalWorkout] {
        guard await isAuthenticated(), let token = accessToken else {
            throw StravaError.notAuthenticated
        }

        var components = URLComponents(string: activitiesURL)!
        components.queryItems = [
            URLQueryItem(name: "after", value: String(Int(since.timeIntervalSince1970))),
            URLQueryItem(name: "per_page", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StravaError.apiError
        }

        let activities = try JSONDecoder().decode([StravaActivity].self, from: data)
        return activities.map { mapActivity($0) }
    }

    func deauthorize() async {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        try? await saveTokens(nil)
    }

    private func performOAuthFlow() async throws {
        let authURL = "https://www.strava.com/oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=read,activity:read_all"
        guard let url = URL(string: authURL) else { throw StravaError.invalidURL }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "75hard") { callbackURL, error in
                if let error = error { continuation.resume(throwing: error) }
                else if let url = callbackURL { continuation.resume(returning: url) }
                else { continuation.resume(throwing: StravaError.oauthCancelled) }
            }
            session.presentationContextProvider = AuthPresentationProvider()
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.noAuthCode
        }

        try await exchangeCodeForToken(code)
    }

    private func exchangeCodeForToken(_ code: String) async throws {
        var components = URLComponents(string: tokenURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: "authorization_code")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        try await saveTokens(StravaToken(accessToken: tokenResponse.accessToken, refreshToken: tokenResponse.refreshToken, expiry: tokenExpiry!))
    }

    private func mapActivity(_ activity: StravaActivity) -> ExternalWorkout {
        ExternalWorkout(
            source: .strava,
            externalID: String(activity.id),
            type: activity.type.capitalized,
            startDate: activity.startDate,
            endDate: activity.startDate.addingTimeInterval(activity.elapsedTime),
            durationMinutes: Int(activity.movingTime / 60),
            distanceMeters: activity.distance,
            isOutdoor: activity.type != "Workout",
            routeCoordinates: activity.map?.polyline?.isEmpty == false ? decodePolyline(activity.map!.polyline!) : nil,
            elevationGainMeters: activity.totalElevationGain,
            sourceData: try? JSONEncoder().encode(activity)
        )
    }

    private func decodePolyline(_ encoded: String) -> [[Double]] {
        var coords: [[Double]] = []
        var index = encoded.startIndex
        var lat = 0, lng = 0

        while index < encoded.endIndex {
            var shift = 0, result = 0
            var byte: UInt8
            repeat {
                byte = UInt8(encoded[index].asciiValue!) - 63
                index = encoded.index(after: index)
                result |= Int(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            let dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dLat

            shift = 0; result = 0
            repeat {
                byte = UInt8(encoded[index].asciiValue!) - 63
                index = encoded.index(after: index)
                result |= Int(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            let dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += dLng

            coords.append([Double(lat) * 1e-5, Double(lng) * 1e-5])
        }
        return coords
    }

    private func loadTokens() async throws -> StravaToken? {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("strava_tokens.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StravaToken.self, from: data)
    }

    private func saveTokens(_ token: StravaToken?) async throws {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("strava_tokens.json")
        if let token = token {
            let data = try JSONEncoder().encode(token)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

struct StravaToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiry: Date
    var isValid: Bool { Date() < expiry }
}

struct StravaTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct StravaActivity: Codable {
    let id: Int64
    let type: String
    let startDate: Date
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let totalElevationGain: Double
    let map: StravaMap?
}

struct StravaMap: Codable {
    let polyline: String?
}

enum StravaError: Error, LocalizedError {
    case missingCredentials, invalidURL, oauthCancelled, noAuthCode, notAuthenticated, apiError
    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Strava credentials not configured"
        case .invalidURL: "Invalid authorization URL"
        case .oauthCancelled: "OAuth flow cancelled"
        case .noAuthCode: "No authorization code received"
        case .notAuthenticated: "Not authenticated with Strava"
        case .apiError: "Strava API error"
        }
    }
}

class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
}