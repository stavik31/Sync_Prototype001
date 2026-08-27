import Foundation

struct PackageListResponse: Codable {
    let packages: [PackageMetadata]
}

struct PackageManifestResponse: Codable {
    let package: PackageMetadata
    let files: [FileEntry]
}

struct PrepareFile: Codable {
    let id: String
    let last_mod: Int64
}

struct PrepareRequest: Codable {
    let action: String
    let packageId: String
    let files: [PrepareFile]
}

struct UploadTarget: Codable {
    let id: String
    let path: String
    let stagingPath: String
    let url: String
}

struct PrepareResponse: Codable {
    let ok: Bool
    let action: String
    let packageId: String
    let expiresIn: Int
    let uploads: [UploadTarget]
}

struct CommitRequest: Codable {
    let action: String
    let packageId: String
    let path: String
    let last_mod: Int64
    let manifest: Manifest
}

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
    
}
