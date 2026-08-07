import Foundation

struct AuthManager {
    
    static let clientId = "559l79m5jdakfj5d7okp40940p"
    static let region = "ap-southeast-2"
    
    static func login(username: String, password: String) async -> (idToken: String?, refreshToken: String?) {
        let url = URL(string: "https://cognito-idp.\(region).amazonaws.com/")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
        
        let authParameters: [String: Any] = [
            "USERNAME": username,
            "PASSWORD": password
        ]

        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "ClientId": clientId,
            "AuthParameters": authParameters
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw Cognito Response: \(raw)")
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let authResult = json["AuthenticationResult"] as? [String: Any],
               let idToken = authResult["IdToken"] as? String {
                let refreshToken = authResult["RefreshToken"] as? String
                return (idToken, refreshToken)
            }
        } catch {
            print("Login request failed: \(error)")
        }
        
        return (nil, nil)
    }
    
    static func refresh(refreshToken: String) async -> String? {
        let url = URL(string: "https://cognito-idp.\(region).amazonaws.com/")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
        
        let authParamters: [String: Any] = [
            "REFRESH_TOKEN": refreshToken
        ]
        
        let body: [String: Any] = [
            "AuthFlow" : "REFRESH_TOKEN_AUTH",
            "ClientId" : clientId,
            "AuthParameters" : authParamters
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let authResult = json["AuthenticationResult"] as? [String: Any],
               let idToken = authResult["IdToken"] as? String {
                return idToken
            }
        } catch {
            print("Refresh request failed: \(error)")
        }
        
        return nil
    }
}
