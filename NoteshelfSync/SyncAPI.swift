import Foundation

struct PackageListResponse: Codable {
    let packages: [PackageMetadata]
}

struct PackageManifestResponse: Codable {
    let package: PackageMetadata
    let files: [FileEntry]
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
    
}
