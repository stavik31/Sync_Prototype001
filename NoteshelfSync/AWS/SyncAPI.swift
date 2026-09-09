import Foundation

// Everything the app can ask the backend to do.
//
// This layer only talks — it never decides what to upload. That's UploadEngine.
//
// Nine calls need the Cognito ID token in an Authorization header:
//   listPackages      - what notebooks does the server have for me?
//   getManifest       - what pages are in this one notebook?
//   prepare           - I want to upload these pages; give me somewhere to put them
//   commit            - I've uploaded them; publish this notebook
//   acquireLock,
//   heartbeatLock,
//   releaseLock       - the exclusive per-notebook lock an upload holds, so two
//                       devices can't publish conflicting versions at once
//   startMultipart,
//   completeMultipart - the chunked-upload path for a single file too big for
//                       one PUT (see AWSSyncRemoteStore.chunkSize)
//
// prepare/commit share one route (POST /upload), and so do the three lock
// calls (POST /locks) and the two multipart calls (POST /upload again) — the
// "action" field in each body is what tells the server which one you mean.
//
// Each of these takes the current authToken as a parameter — this layer never
// reads storage directly. The one exception is a 401 mid-request: send()'s
// refresh path goes through the loadRefreshToken/onTokenRefreshed/onRefreshFailed
// hooks below instead, since the caller can't hand in a token it doesn't have yet.
//
// A note on the structs below: each JSON shape needs a matching Swift type.
// Where the JSON nests (a list of items inside an object), that's two types —
// one for the outer object, one for a single item.
//
// prepare/commit never carry file bytes — they only exchange metadata and
// presigned S3 URLs. The actual bytes go out via put/putPart, further down in
// this same file, straight to S3. Those PUTs must NOT carry the auth header;
// permission is baked into the presigned URL itself.

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

struct PartTarget: Codable {
    let partNumber: Int
    let url: String
}

struct StartMultipartRequest: Codable {
    let action: String
    let packageId: String
    let id: String
    let last_mod: Int64
    let size: Int
}

struct MultipartResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let id: String
    let uploadId: String
    let parts: [PartTarget]
}

struct CompletedPart: Codable {
    let partNumber: Int
    let eTag: String
}

struct CompleteMultipartRequest: Codable {
    let action: String
    let packageId: String
    let id: String
    let uploadId: String
    let parts: [CompletedPart]
}

struct CompleteMultipartResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let id: String
}

struct AcquireLockRequest: Codable {
    let action: String
    let packageId: String
}

struct AcquireLockResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let acquired: Bool
    let etag: String?
}

struct HeartbeatLockRequest: Codable {
    let action: String
    let packageId: String
    let etag: String
}

struct HeartbeatLockResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let renewed: Bool
    let etag: String?
}

struct ReleaseLockRequest: Codable {
    let action: String
    let packageId: String
    let etag: String
}

struct ReleaseLockResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let released: Bool
}

struct SyncAPI {

    static let baseURL = "https://j21sih3zdd.execute-api.eu-north-1.amazonaws.com"
    static var loadRefreshToken: (() -> String?)?
    static var onTokenRefreshed: ((String) -> Void)?
    static var onRefreshFailed: (() -> Void)?

    private static func send(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        do{
            let(data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            guard http.statusCode == 401 else {
                return (data, http)
            }

            print("SyncAPI: 401, trying to refresh token")

            guard let refreshToken = loadRefreshToken?(),
                  let newToken = await AuthManager.refresh(refreshToken: refreshToken) else {
                print("SyncAPI: refresh failed, clearing session")
                onRefreshFailed?()
                return nil
            }

            onTokenRefreshed?(newToken)
            print("SyncAPI: refresh succeeded, retrying request")

            var retryRequest = request
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")

            guard let(retryData, retryResponse) = try? await URLSession.shared.data(for: retryRequest),
                  let retryHTTP = retryResponse as? HTTPURLResponse else { return nil }

            if retryHTTP.statusCode == 200 {
                print("SyncAPI: retry succeeded")
            }
            return (retryData, retryHTTP)

        } catch {
            print("SyncAPI: request error: \(error)")
            return nil
        }
    }

    // Every notebook the server holds for this user.
    // Returns nil on any failure — the server's own error is printed.
    static func listPackages(authToken: String) async -> [PackageMetadata]? {
        guard let url = URL(string: "\(baseURL)/getallpackagemetadata") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            guard let (data, http) = await send(request) else { return nil }

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
            guard let (data, http) = await send(request) else { return nil }

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
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData

            guard let (data, http) = await send(request) else { return nil }

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
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData

            guard let (data, http) = await send(request) else { return nil }

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

    // Uploads one file's bytes straight to S3, using a presigned URL prepare
    // handed out earlier. No Authorization header — the permission to write is
    // baked into the URL itself, and it expires 15 minutes after prepare issued it.
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

    // Uploads one chunk of a file that's being sent via the multipart path
    // (see startMultipart). Returns the ETag S3 assigns that chunk — the
    // caller has to hang onto it, since completeMultipart needs every part's
    // ETag to stitch them back into one object.
    static func putPart(content: Data, to urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = content
        do {
            let(_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else { return nil }
            return http.value(forHTTPHeaderField: "ETag")
        } catch {
            return nil
        }
    }

    // Step 1 of uploading a single file too big for one plain PUT. Returns one
    // presigned URL per chunk — the caller uploads each chunk via putPart,
    // then calls completeMultipart once every chunk succeeds.
    static func startMultipart(packageId: String, fileId: String, lastMod: Int64, size: Int, authToken: String) async -> MultipartResponse? {
        guard let url = URL(string: "\(baseURL)/upload") else { return nil }

        var request = URLRequest(url:url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = StartMultipartRequest(action: "start_multipart", packageId: packageId, id: fileId, last_mod: lastMod, size: size)

        do {
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData

            guard let (data, http) = await send(request) else { return nil }

            guard http.statusCode == 200 else {
                print("startMultipart failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }

            let decoded = try JSONDecoder().decode(MultipartResponse.self, from: data)
            return decoded

        } catch {
            print("startMultipart error: \(error)")
            return nil
        }
    }

    // Step 2: tells S3 every chunk is in, and which ETag belongs to which part
    // number, so it can assemble them into one final object. Only call this
    // once every putPart in the batch has actually succeeded.
    static func completeMultipart(packageId: String, fileId: String, uploadId: String, parts: [CompletedPart], authToken: String) async -> CompleteMultipartResponse? {
        guard let url = URL(string: "\(baseURL)/upload") else { return nil }

        var request = URLRequest(url:url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CompleteMultipartRequest(action: "complete_multipart", packageId: packageId, id: fileId, uploadId: uploadId, parts: parts)

        do {
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData

            guard let (data, http) = await send(request) else { return nil }

            guard http.statusCode == 200 else {
                print("completeMultipart failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }

            let decoded = try JSONDecoder().decode(CompleteMultipartResponse.self, from: data)
            return decoded

        } catch {
            print("completeMultipart error: \(error)")
            return nil
        }
    }
    
    // Takes the exclusive lock on this notebook before an upload starts, so a
    // second device can't publish a conflicting version at the same time.
    // Returns an etag that must be passed to heartbeatLock/releaseLock —
    // whoever holds the current etag is treated as the lock's rightful owner.
    static func acquireLock(packageId: String, authToken: String) async -> AcquireLockResponse? {
        guard let url = URL(string: "\(baseURL)/locks") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = AcquireLockRequest(action: "acquire_lock", packageId: packageId)
        
        do {
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData
            
            guard let (data, http) = await send(request) else { return nil }
            
            guard http.statusCode == 200 else {
                print("acquireLock failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(AcquireLockResponse.self, from: data)
            return decoded
            
        } catch {
            print("acquireLock error: \(error)")
            return nil
        }
    }
    
    // Renews a held lock so it doesn't expire mid-upload — must be called
    // periodically with the etag from the last acquire/heartbeat
    // (AWSSyncRemoteStore does this every 5 minutes during uploadNotebook).
    // renewed == false means someone else may have taken the lock over.
    static func heartbeatLock(packageId: String, etag: String, authToken: String) async -> HeartbeatLockResponse? {
        guard let url = URL(string: "\(baseURL)/locks") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = HeartbeatLockRequest(action: "heartbeat_lock", packageId: packageId, etag: etag)
        
        do {
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData
            
            guard let (data, http) = await send(request) else { return nil }
            
            guard http.statusCode == 200 else {
                print("heartbeatLock failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(HeartbeatLockResponse.self, from: data)
            return decoded
            
        } catch {
            print("heartbeatLock error: \(error)")
            return nil
        }
    }
    
    // Frees a held lock once an upload finishes, success or failure — callers
    // are expected to call this on every exit path so a lock never leaks and
    // blocks other devices indefinitely.
    static func releaseLock(packageId: String, etag: String, authToken: String) async -> ReleaseLockResponse? {
        guard let url = URL(string: "\(baseURL)/locks") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = ReleaseLockRequest(action: "release_lock", packageId: packageId, etag: etag)
        
        do {
            guard let bodyData = try? JSONEncoder().encode(body) else { return nil }
            request.httpBody = bodyData
            
            guard let (data, http) = await send(request) else { return nil }
            
            guard http.statusCode == 200 else {
                print("releaseLock failed: \(http.statusCode) - \(String(data: data, encoding: .utf8) ?? "")")
                return nil
            }
            
            let decoded = try JSONDecoder().decode(ReleaseLockResponse.self, from: data)
            return decoded
            
        } catch {
            print("releaseLock error: \(error)")
            return nil
        }
    }
    
    

}
