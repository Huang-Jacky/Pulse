import AppKit
import Foundation

struct UpdateRepositoryConfiguration {
    let owner: String
    let repository: String

    var isConfigured: Bool {
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var latestReleaseAPIURL: URL? {
        guard isConfigured else {
            return nil
        }
        return URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")
    }
}

@MainActor
final class UpdateViewModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(version: String, releaseURL: URL)
        case aheadOfRelease(currentVersion: String, releaseVersion: String)
        case failed(message: String)
        case unconfigured
    }

    @Published private(set) var status: Status

    private let repository: UpdateRepositoryConfiguration

    init(repository: UpdateRepositoryConfiguration = AppMetadata.updateRepository) {
        self.repository = repository
        status = repository.isConfigured ? .idle : .unconfigured
    }

    func checkForUpdates() {
        guard repository.isConfigured else {
            status = .unconfigured
            return
        }

        guard case .checking = status else {
            status = .checking

            Task {
                await performCheck()
            }
            return
        }
    }

    func openLatestReleasePage() {
        guard case let .updateAvailable(_, releaseURL) = status else {
            return
        }

        NSWorkspace.shared.open(releaseURL)
    }

    private func performCheck() async {
        guard let url = repository.latestReleaseAPIURL else {
            status = .unconfigured
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pulse/\(AppMetadata.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                status = .failed(message: AppText.localized("更新服务返回异常。", "Unexpected response from the update service."))
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    status = .failed(message: AppText.localized("还没有可用的发布版本。", "No release is available yet."))
                } else {
                    status = .failed(message: AppText.localized("检查失败（\(httpResponse.statusCode)）。", "Update check failed (\(httpResponse.statusCode))."))
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubLatestRelease.self, from: data)
            let latestVersion = Self.normalizeVersion(release.tagName)

            guard !latestVersion.isEmpty else {
                status = .failed(message: AppText.localized("未读取到有效版本号。", "No valid version number was found."))
                return
            }

            let currentVersion = AppMetadata.currentVersion
            switch Self.compareVersion(currentVersion, latestVersion) {
            case .orderedAscending:
                status = .updateAvailable(version: latestVersion, releaseURL: release.htmlURL)
            case .orderedDescending:
                status = .aheadOfRelease(currentVersion: currentVersion, releaseVersion: latestVersion)
            case .orderedSame:
                status = .upToDate(version: currentVersion)
            }
        } catch {
            status = .failed(message: AppText.localized("检查失败，请稍后重试。", "Update check failed. Please try again later."))
        }
    }

    private static func normalizeVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        return withoutPrefix.split(separator: "-", maxSplits: 1).first.map(String.init) ?? withoutPrefix
    }

    private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0 ..< count {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
