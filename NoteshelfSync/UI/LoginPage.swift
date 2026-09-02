import SwiftUI

// Login screen.
//
// On success: stores both tokens in the Keychain so the next launch can skip
// this screen, and decodes the user's id out of the ID token.
//
// The username and password are hardcoded for development speed. There's no
// sign-up flow — accounts are created in the Cognito console.
struct LoginPage: View {
    @Binding var isLoggedIn: Bool
    @Binding var authToken: String
    @Binding var refreshToken: String
    @State private var username = "madhavchoudhary296@gmail.com"
    @State private var password = "Syncprototype@001"
    @Binding var userId: String

    var body: some View {
        VStack(spacing: 16) {
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(10)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(10)
            
            Button(action: {
                Task {
                    let result = await AuthManager.login(username: username, password: password)
                    if let idToken = result.idToken {
                        print("Got Token: \(idToken)")
                        authToken = idToken
                        userId = AuthManager.userId(from: idToken) ?? ""
                        refreshToken = result.refreshToken ?? ""
                        KeychainManager.save(token: idToken, key: "authToken")
                        KeychainManager.save(token: result.refreshToken ?? "", key: "refreshToken")
                        isLoggedIn = true
                    } else {
                        print("Login failed")
                        isLoggedIn = false
                    }
                }
            }) {
                Text("Login")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding(10)
                    
            }
        }
    }
}
