import Foundation

// Everything the app can ask the backend to do.
//
// This layer only talks — it never decides what to upload. That's UploadEngine.
//
// Four calls, all needing the Cognito ID token in an Authorization header:
//   listPackages  - what notebooks does the server have for me?
//   getManifest   - what pages are in this one notebook?
//   prepare       - I want to upload these pages; give me somewhere to put them
//   commit        - I've uploaded them; publish this notebook
//
// prepare and commit both POST to the same /upload route. The "action" field
// in the body is what tells them apart.
//
// A note on the structs below: each JSON shape needs a matching Swift type.
// Where the JSON nests (a list of items inside an object), that's two types —
// one for the outer object, one for a single item.
//
// Sending the file bytes themselves is NOT here. prepare returns a temporary
// S3 link and the caller PUTs directly to it — see UploadEngine.put.
// Those requests must NOT carry the auth header; permission is inside the link.

// Wraps the reply from listPackages: {"packages": [...]}
struct PackageListResponse: Codable {
    let packages: [PackageMetadata]
}

// Reply from getManifest: the notebook's own info, plus its page list.
struct PackageManifestResponse: Codable {
    let package: PackageMetadata
    let files: [FileEntry]
}

// One page you're asking to upload. Deliberately not FileEntry — prepare
// doesn't need a path, because the server works out the real address itself
// from the id. Sending fields the server ignores just invites confusion.
struct PrepareFile: Codable {
    let id: String
    let last_mod: Int64
}

// The body sent to /upload for a prepare. Built inside prepare(); callers
// never construct this themselves.
struct PrepareRequest: Codable {
    let action: String
    let packageId: String
    let files: [PrepareFile]
}

// What the server hands back per page.
//   id          - which page this is for
//   url         - PUT the file's bytes here. Expires after 15 minutes.
//   path        - where it will end up once committed (informational)
//   stagingPath - the holding area it lands in first (informational)
struct UploadTarget: Codable {
    let id: String
    let path: String
    let stagingPath: String
    let url: String
}

// Reply from prepare. The useful part is `uploads`.
// expiresIn is 900 — those links stop working after 15 minutes.
struct PrepareResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let expiresIn: Int
    let uploads: [UploadTarget]
}

// The body sent to /upload for a commit.
//   path     - the notebook's display path, e.g. "MyNotes/Physics". Required.
//   last_mod - the NOTEBOOK's timestamp, not a page's
//   manifest - the complete page list. See the warning on commit() below.
struct CommitRequest: Codable {
    let action: String
    let packageId: String
    let path: String
    let last_mod: Int64
    let manifest: Manifest
}

// Reply from commit.
//   deleted       - files the server removed because the manifest didn't list them
//   cleanupFailed - published fine but couldn't tidy up afterwards.
//                   Still a success; treat it as one.
// Both are optional because only one of them appears.
struct CommitResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let manifestKey: String
    let fileCount: Int
    let deleted: [String]?
    let cleanupFailed: Bool?
}

struct SyncAPI {
    
    static let baseURL = "https://j21sih3zdd.execute-api.eu-north-1.amazonaws.com"
    
    // Every notebook the server holds for this user.
    // Returns nil on any failure — the server's own error is printed.
    static func listPackages(authToken: String) async -> [PackageMetadata]? {
        guard let url = URL(string: "\(baseURL)/getallpackagemetadata") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else { return nil }
            
            guard http.statusCode == 200 else {
                print("listPackages failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(PackageListResponse.self, from: data)
            return decoded.packages
            
        } catch {
            print("listPackages error: \(error)")
            return nil
        }
    }
    
    // One notebook's page list.
    //
    // Heads up: asking for a notebook the server doesn't have returns 500, not
    // 404 — an S3 permissions quirk on the backend. So nil here means either
    // "not there" or "something broke", and you can't tell which.
    static func getManifest(packageId: String, authToken: String) async -> PackageManifestResponse? {
        guard let url = URL(string: "\(baseURL)/getpackagemanifest/\(packageId)") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else { return nil }
            
            guard http.statusCode == 200 else {
                print("getManifest failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(PackageManifestResponse.self, from: data)
            return decoded
            
        } catch {
            print("getManifest error: \(error)")
            return nil
        }
    }
    
    // Step 1 of an upload: ask for somewhere to put these pages.
    //
    // Nothing is uploaded here. You get back one temporary link per page,
    // pointing at a staging area — the live notebook is untouched until commit.
    // The server builds the real address itself from the ids you send, so a
    // client can't write outside its own space.
    static func prepare(packageId: String, files: [PrepareFile], authToken: String) async -> PrepareResponse? {
        guard let url = URL(string: "\(baseURL)/upload") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = PrepareRequest(action: "prepare", packageId: packageId, files: files)
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else { return nil }
            
            guard http.statusCode == 200 else {
                print("prepare failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(PrepareResponse.self, from: data)
            return decoded
            
        } catch {
            print("prepare error: \(error)")
            return nil
        }
    }
    
    // Step 2 of an upload: publish. This is the moment the change becomes real
    // for every device — before it, the server still shows the old version.
    //
    // WARNING: the manifest you send is the complete truth. The server deletes
    // anything in that notebook's folder the manifest doesn't list. Send a
    // partial list and you delete pages you didn't mean to.
    //
    // Only call this once every page has uploaded successfully.
    static func commit(packageId: String, path: String, lastMod: Int64, manifest: Manifest, authToken: String) async -> CommitResponse? {
        guard let url = URL(string: "\(baseURL)/upload") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = CommitRequest(action: "commit", packageId: packageId, path: path, last_mod: lastMod, manifest: manifest)
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else { return nil }
            
            guard http.statusCode == 200 else {
                print("commit failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            let decoded = try JSONDecoder().decode(CommitResponse.self, from: data)
            return decoded
            
        } catch {
            print("commit error: \(error)")
            return nil
        }
    }
    
    static func put(content: Data, to urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = content
        do {
            let(_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }
    
}
