import Foundation

public struct Volume: Sendable {
    public let name: String
    public let mountPoint: String
    /// The folder to scan. For the boot volume that's the data volume: scanning `/` would also
    /// walk the sealed system volume and count the firmlinked folders twice.
    public let scanRoot: String
    public let total: Int64
    /// Free space like Finder shows it, including purgeable space macOS frees up when needed.
    public let available: Int64

    public var used: Int64 { max(0, total - available) }
    public var isBoot: Bool { mountPoint == "/" }
}

public enum Volumes {
    /// Macintosh HD plus any external or network volumes the user can see in Finder.
    public static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable ?? true else {
                return nil
            }
            var path = url.path(percentEncoded: false)
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            return Volume(
                name: values.volumeName ?? path, mountPoint: path,
                scanRoot: path == "/" ? "/System/Volumes/Data" : path,
                total: Int64(values.volumeTotalCapacity ?? 0), available: available)
        }
    }

    /// Bytes used by this one volume. APFS volumes share their container's space, so this is
    /// how the sealed macOS system volume gets its own line in the disk browser.
    public static func spaceUsed(_ mountPoint: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        var buffer = [UInt8](repeating: 0, count: 32)
        let status = buffer.withUnsafeMutableBytes { getattrlist(mountPoint, &request, $0.baseAddress, $0.count, 0) }
        guard status == 0 else { return nil }
        // Layout: u_int32_t length, then off_t space used.
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}
