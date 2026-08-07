import Foundation
import CryptoKit

enum UploadResult {
    case success
    case unauthorized
    case failure
}

struct SyncManager {
    
    static let clientId = "559l79m5jdakfj5d7okp40940p"
    static let region = "ap-southeast-2"
    
    static func upload(notebookId: String, fileContent: String, pageName: String, authToken: String) async -> UploadResult {
        
        let checksum = Insecure.MD5.hash(data: Data(fileContent.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        
        let url = URL(string: "https://mhjsrxn5i2.execute-api.ap-southeast-2.amazonaws.com/notebooks/\(notebookId)/upload")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "fileContent": fileContent,
            "localChecksum": checksum,
            "page_name": pageName
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return .success
                } else if httpResponse.statusCode == 401 {
                    return .unauthorized
                }
            }
        } catch {
            print("Upload request failed: \(error)")
        }
        
        return .failure
    }
    
    static func fetchChanges(since: String, authToken: String) async -> (result: UploadResult, changes: [[String: Any]]) {
        
        let url = URL(string: "https://mhjsrxn5i2.execute-api.ap-southeast-2.amazonaws.com/notebooks/changes?since=\(since)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let changes = json["changes"] as? [[String: Any]] {
                        return (.success, changes)
                    }
                } else if httpResponse.statusCode == 401 {
                    return (.unauthorized, [])
                }
            }
        } catch {
            print("Fetch changes failed: \(error)")
        }

        return (.failure, [])
    }
}
