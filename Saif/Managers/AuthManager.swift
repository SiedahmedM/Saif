import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var error: String?

    private let supabaseService = SupabaseService.shared

    init() {
        Task { await checkAuthStatus() }
    }

    func checkAuthStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            currentUser = try await supabaseService.getCurrentUser()
            isAuthenticated = currentUser != nil
            if let userId = currentUser?.id {
                do {
                    userProfile = try await supabaseService.getProfile(userId: userId)
                } catch SupabaseError.noUser {
                    userProfile = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } catch {
            print("Auth check error: \(error)")
            isAuthenticated = false
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            currentUser = try await supabaseService.signUp(email: email, password: password)
            isAuthenticated = true
        } catch { self.error = error.localizedDescription }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let session = try await supabaseService.signIn(email: email, password: password)
            currentUser = session.user
            if let userId = currentUser?.id {
                do {
                    userProfile = try await supabaseService.getProfile(userId: userId)
                } catch SupabaseError.noUser {
                    userProfile = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
            isAuthenticated = true
            // Avoid immediately re-checking status to prevent redundant reloads
        } catch { self.error = error.localizedDescription; isAuthenticated = false }
    }

    func signOut() async {
        do {
            try await supabaseService.signOut()
            isAuthenticated = false
            currentUser = nil
            userProfile = nil
        } catch { self.error = error.localizedDescription }
    }

    func completeOnboarding(profile: OnboardingProfile) async -> Bool {
        guard let userId = currentUser?.id else { error = "No user found"; return false }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let injuries = profile.injuries.isEmpty ? [] : [profile.injuries]
            let p = UserProfile(
                id: userId,
                fullName: profile.name,
                fitnessLevel: profile.fitnessLevel,
                primaryGoal: profile.goal,
                workoutFrequency: profile.workoutFrequency,
                gymType: profile.gymType,
                injuriesLimitations: injuries,
                createdAt: Date(),
                updatedAt: Date()
            )
            try await supabaseService.createProfile(p)
            self.userProfile = p
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

// MARK: - Portable User/Session wrappers if Supabase not present
#if !canImport(Supabase)
struct User: Identifiable, Codable, Hashable { let id: UUID }
struct Session { let user: User }
#endif
