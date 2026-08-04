import Foundation
import CryptoKit

struct SyncManager {
    
    static let clientId = "559l79m5jdakfj5d7okp40940p"
    static let region = "ap-southeast-2"
    
    static func upload(notebookId: String, fileContent: String, pageName: String, authToken: String) async -> Bool {
        
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
                return httpResponse.statusCode == 200
            }
        } catch {
            print("Upload request failed: \(error)")
        }
        
        return false
    }
    
    static func fetchChanges(since: String, authToken: String) async -> [[String: Any]] {
        
        let url = URL(string: "https://mhjsrxn5i2.execute-api.ap-southeast-2.amazonaws.com/notebooks/changes?since=\(since)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let(data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let changes = json["changes"] as? [[String: Any]] {
                    return changes
                }
            }
        } catch {
            print("Fetch changes failed: \(error)")
        }
        
        return []
    }
}
