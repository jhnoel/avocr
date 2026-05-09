import Foundation

struct FileEnumerator {
    static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "heic", "heif", "webp"
    ]
    static let supportedPDFExtensions: Set<String> = ["pdf"]

    static func enumerateFiles(
        paths: [String],
        includeHidden: Bool,
        fileSystem: FileSystemProtocol = RealFileSystem(),
        logger: Logger = NullLogger()
    ) -> Result<[URL], CLIError> {
        var results: [URL] = []

        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false

            guard fileSystem.fileExists(atPath: path, isDirectory: &isDirectory) else {
                return .failure(.fileNotFound(path))
            }

            if isDirectory.boolValue {
                // Recursively enumerate directory
                let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                guard let enumerator = fileSystem.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .isDirectoryKey],
                    options: options
                ) else {
                    return .failure(.other("Cannot enumerate directory: \(path)"))
                }

                for case let fileURL as URL in enumerator {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .isDirectoryKey])
                        if !includeHidden,
                           let isHidden = resourceValues.isHidden,
                           isHidden,
                           let isDirectory = resourceValues.isDirectory,
                           isDirectory {
                            enumerator.skipDescendants()
                            continue
                        }

                        guard let isRegularFile = resourceValues.isRegularFile, isRegularFile else {
                            continue
                        }

                        if !includeHidden, let isHidden = resourceValues.isHidden, isHidden {
                            continue
                        }

                        if isSupportedFile(fileURL) {
                            results.append(fileURL)
                        }
                    } catch {
                        logger.warn("Cannot read attributes of \(fileURL.path): \(error)")
                    }
                }
            } else {
                // Single file
                if isSupportedFile(url) {
                    results.append(url)
                } else {
                    return .failure(.other("Unsupported file type: \(path)"))
                }
            }
        }

        if results.isEmpty {
            return .failure(.noSupportedFiles)
        }

        // Sort for deterministic ordering
        results.sort { $0.path < $1.path }

        return .success(results)
    }

    static func isSupportedFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedImageExtensions.contains(ext) || supportedPDFExtensions.contains(ext)
    }

    static func isImage(_ url: URL) -> Bool {
        supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isPDF(_ url: URL) -> Bool {
        supportedPDFExtensions.contains(url.pathExtension.lowercased())
    }
}
