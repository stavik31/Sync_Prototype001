import SwiftUI

struct LoginPage: View {
    @Binding var isLoggedIn: Bool
    @Binding var authToken: String
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
                    if let token = await AuthManager.login(username: username, password: password){
                        print("Got Token: \(token)")
                        authToken = token
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
