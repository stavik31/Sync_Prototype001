// The shapes the server speaks in.
//
// These match the backend's JSON exactly — field names included, which is why
// they're snake_case (last_mod) rather than Swift's usual camelCase. Codable
// matches property names to JSON keys literally, so renaming them breaks decoding.
//
// Used in both directions: decoded from server responses, and encoded into
// requests we send.

// One page inside a notebook.
//   id       - the page's uuid; also its filename on the server ("<id>.rtf")
//   path     - where it sits inside the notebook, e.g. "/Pages/Page1.rtf"
//   last_mod - unix milliseconds
struct FileEntry: Codable {
    let id: String
    var path: String
    var last_mod: Int64
}

// A notebook's page list, as stored on the server (Manifest.json).
// Note there's no notebook id in here — the server keeps that as S3 object
// metadata attached to the file, not inside it. The local equivalent
// (NotebookInfo in NotebookStore) does carry an id, because a plain file
// on disk has no "attached metadata" to use.
struct Manifest: Codable {
    var files: [FileEntry]
}

// A notebook, as the server describes it.
//   id       - the notebook's uuid; the server stores it under this name
//   path     - human-readable display path, e.g. "MyNotes/Physics".
//              A label only — never used to locate anything.
//   last_mod - newest edit anywhere in the notebook
struct PackageMetadata: Codable {
    let id: String
    var path: String
    var last_mod: Int64
}
