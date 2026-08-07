import SwiftUI

struct LoginPage: View {
    @Binding var isLoggedIn: Bool
    @Binding var authToken: String
    @Binding var refreshToken: String
    @State private var username = "testuser@example.com"
    @State private var password = "RealPass456!"

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
