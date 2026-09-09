import Foundation

// Talks to AWS Cognito directly — no AWS SDK, just hand-built requests.
//
// Cognito uses its own protocol rather than plain REST: the operation goes in
// an X-Amz-Target header, and the content type is x-amz-json-1.1.
//
// Three things:
//   login   - username + password -> an ID token (good for 1 hour) and a
//             refresh token (long-lived)
//   refresh - trade the refresh token for a fresh ID token
//   userId  - pull the user's id out of a token without asking the server
//
// The ID token is what every backend call sends as "Bearer <token>".
struct AuthManager {
    
    static let clientId = "388s6r4q4n7e40gv66m0qea6v8"
    static let region = "eu-north-1"
    
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
    
    // Trades a refresh token for a new ID token, without the user logging in again.
    //
    // Called from SyncAPI.send() whenever a request comes back 401 mid-sync —
    // this is what lets an upload survive an access token expiring partway
    // through, without the user seeing the login screen again.
    //
    // Known weakness: on failure this returns a bare nil and throws away
    // Cognito's explanation, so "your login was revoked" and "the response was
    // malformed" look identical. Worth fixing before anything depends on
    // telling those two apart.
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
    
    // Pulls the user's Cognito id ("sub") out of an ID token.
    //
    // A token is three chunks joined by dots: header.payload.signature.
    // The middle chunk is base64-encoded JSON holding the claims. This decodes
    // it and reads "sub" — no network call needed, it's already in the token.
    //
    // Two fiddly bits: tokens use a URL-safe base64 variant (- and _ instead of
    // + and /), and drop the trailing "=" padding. Both are put back before
    // Swift's decoder will accept it.
    //
    // The signature isn't verified. That's fine here — it's our own token that
    // Cognito just issued us, not something accepted from elsewhere.
    static func userId(from idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count == 3 else {return nil}
        
        var payload = String(parts[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        
        while payload.count % 4 != 0 {
            payload += "="
        }
        
        guard let data = Data(base64Encoded: payload) else {return nil}
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {return nil}
        
        return sub
    }
}
