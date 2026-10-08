# Saif

A native iOS workout app that combines set logging, session planning, and training history. It uses a local exercise knowledge base to assemble plans and OpenAI for contextual recommendations and coaching responses.

## Planning and persistence

[WorkoutManager](Saif/Managers/WorkoutManager.swift) owns the active session, completed sets, exercise preferences, and plan state. It saves a snapshot in `UserDefaults` so a recent session can be restored after reopening the app.

[SessionPlanGenerator](Saif/Services/SessionPlanGenerator.swift) builds plans in Swift. It ranks exercises from the bundled JSON, applies preference and injury rules, places compound movements before accessories, and calculates volume targets using recent logged sets. These decisions can be read directly in the planner rather than inferred from a prompt.

[OpenAIService](Saif/Services/OpenAIService.swift) handles model-assisted workout, exercise, and set recommendations, plus coaching conversations. It uses `URLSession` and currently requests `gpt-4o-mini`. [SupabaseService](Saif/Services/SupabaseService.swift) handles authentication, profiles, workout sessions, exercise sets, and preferences. It also defines storage methods for plans and adaptations.

The interface uses SwiftUI and Swift Charts. Supabase's Swift package provides authentication and database access; exercise and volume knowledge is stored under [`Knowledge/`](Knowledge).

## Open in Xcode

The app target specifies iOS 18.2. Use Xcode on macOS with an appropriate iOS SDK.

1. Open `Saif.xcodeproj` and resolve its Supabase Swift package dependency.
2. Copy `Saif/Config.sample.swift` to `Saif/Config.swift`. Rename `ConfigSample` to `Config`, then supply your Supabase URL, public anon key, and OpenAI key. `Config.swift` is ignored by Git.
3. Choose a simulator, or configure your signing team for a device, and build the `Saif` target.

Full use requires a matching Supabase database. The public repository does not include SQL migrations or database policies. The service expects `profiles`, `workout_sessions`, `exercises`, `exercise_sets`, `exercise_preferences`, `session_plans`, `session_adaptations`, and `stretches`; the Swift models and service calls describe the client-side contract.

## Current scope

The repository includes onboarding, workout planning and logging, exercise browsing, session history, and progress screens. The local session snapshot and in-memory query caches do not provide a durable queue for offline database writes.

The current configuration puts the OpenAI key on the device. A distributed build would need to move those requests behind a server that holds the credential. Exercise and injury rules are application heuristics, with no clinical validation established here.

[`TrainingKnowledgeServiceTests`](SaifTests/TrainingKnowledgeServiceTests.swift) checks that the bundled exercise data loads without using the fallback dataset and contains a known exercise. The remaining test files are starter tests. Run the test target from Xcode with Product > Test.
