struct FileEntry: Codable {
    let id: String
    var path: String
    var last_mod: Int64
}

struct Manifest: Codable {
    var files: [FileEntry]
}

struct PackageMetadata: Codable {
    let id: String
    var path: String
    var last_mod: Int64
}
