import SwiftUI

// MARK: - Auth Flow Coordinator
struct AuthFlowView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                if authManager.userProfile == nil {
                    OnboardingCoordinator(authManager: authManager)
                } else {
                    HomeRootView()
                }
            } else {
                AuthView()
            }
        }
        // environmentObject provided at App root
    }
}

// MARK: - Auth Landing View
struct AuthView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                SAIFColors.background.ignoresSafeArea()
                VStack(spacing: SAIFSpacing.xl) {
                    Spacer()
                    VStack(spacing: SAIFSpacing.lg) {
                        Text("SAIF")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(SAIFColors.primary)
                            .kerning(2.0)
                        Text("Stronger. Smarter. Simpler.")
                            .font(.system(size: 18))
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                    Spacer()
                    VStack(spacing: SAIFSpacing.md) {
                        NavigationLink(destination: SignUpView()) {
                            Text("Create Account")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SAIFSpacing.lg)
                                .foregroundStyle(.white)
                                .background(SAIFColors.primary)
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
                        }
                        NavigationLink(destination: SignInView()) {
                            Text("Sign In")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SAIFSpacing.lg)
                                .foregroundStyle(SAIFColors.text)
                                .background(Color.clear)
                                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.xl).stroke(SAIFColors.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, SAIFSpacing.xl)
                    .padding(.bottom, SAIFSpacing.xxl)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Sign Up View
struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showError = false

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                        Text("Create Account").font(.system(size: 32, weight: .bold)).foregroundStyle(SAIFColors.text)
                        Text("Start your fitness journey with SAIF").font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
                    }
                    VStack(spacing: SAIFSpacing.lg) {
                        CustomTextField(icon: "envelope", placeholder: "Email", text: $email, keyboardType: .emailAddress, autocapitalization: .never)
                        CustomTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                        CustomTextField(icon: "lock", placeholder: "Confirm Password", text: $confirmPassword, isSecure: true)
                    }
                    if let error = authManager.error {
                        Text(error).font(.system(size: 14)).foregroundStyle(.red).padding(.horizontal, SAIFSpacing.md)
                    }
                    VStack(spacing: SAIFSpacing.md) {
                        Button(action: handleSignUp) {
                            if authManager.isLoading {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg)
                            } else {
                                Text("Create Account").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg).foregroundStyle(.white)
                            }
                        }
                        .background(SAIFColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
                        .disabled(authManager.isLoading || !isValid)
                        .opacity(isValid ? 1.0 : 0.6)
                        HStack {
                            Text("Already have an account?").foregroundStyle(SAIFColors.mutedText)
                            Button("Sign In") { dismiss() }.foregroundStyle(SAIFColors.primary)
                        }.font(.system(size: 14))
                    }.padding(.top, SAIFSpacing.lg)
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Password Mismatch", isPresented: $showError) { Button("OK", role: .cancel) {} } message: { Text("Passwords do not match") }
    }

    private var isValid: Bool { !email.isEmpty && !password.isEmpty && password.count >= 6 && password == confirmPassword }
    private func handleSignUp() { guard isValid else { showError = true; return }; Task { await authManager.signUp(email: email, password: password) } }
}

// MARK: - Sign In View
struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                        Text("Welcome Back").font(.system(size: 32, weight: .bold)).foregroundStyle(SAIFColors.text)
                        Text("Sign in to continue your journey").font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
                    }
                    VStack(spacing: SAIFSpacing.lg) {
                        CustomTextField(icon: "envelope", placeholder: "Email", text: $email, keyboardType: .emailAddress, autocapitalization: .never)
                        CustomTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                    }
                    if let error = authManager.error { Text(error).font(.system(size: 14)).foregroundStyle(.red).padding(.horizontal, SAIFSpacing.md) }
                    VStack(spacing: SAIFSpacing.md) {
                        Button(action: handleSignIn) {
                            if authManager.isLoading { ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg) }
                            else { Text("Sign In").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg).foregroundStyle(.white) }
                        }
                        .background(SAIFColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
                        .disabled(authManager.isLoading || !isValid)
                        .opacity(isValid ? 1.0 : 0.6)
                        HStack { Text("Don't have an account?").foregroundStyle(SAIFColors.mutedText); Button("Sign Up") { dismiss() }.foregroundStyle(SAIFColors.primary) }.font(.system(size: 14))
                    }.padding(.top, SAIFSpacing.lg)
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: authManager.isAuthenticated) { _, new in
            if new { dismiss() }
        }
    }
    private var isValid: Bool { !email.isEmpty && !password.isEmpty }
    private func handleSignIn() { Task { await authManager.signIn(email: email, password: password) } }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var body: some View {
        HStack(spacing: SAIFSpacing.md) {
            Image(systemName: icon).foregroundStyle(SAIFColors.mutedText).frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text).textInputAutocapitalization(autocapitalization).keyboardType(keyboardType)
            } else {
                TextField(placeholder, text: $text).textInputAutocapitalization(autocapitalization).keyboardType(keyboardType)
            }
        }
        .padding(SAIFSpacing.lg)
        .background(SAIFColors.surface)
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(SAIFColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack(spacing: SAIFSpacing.lg) {
                ProgressView().scaleEffect(1.5).tint(SAIFColors.primary)
                Text("Loading...").font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
            }
        }
    }
}

#Preview { AuthView().environmentObject(AuthManager()) }
