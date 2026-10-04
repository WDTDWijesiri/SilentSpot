# SilentSpot Firebase setup

The app code now uses Firebase Authentication and Cloud Firestore. It intentionally shows a setup warning instead of falling back to hardcoded community data when Firebase is not configured.

1. Open Firebase Console and create or select a project.
2. Add an iOS app with bundle ID `com.thanuja.silentspot`.
3. Download `GoogleService-Info.plist` without renaming it.
4. Drag it into the `SilentSpot` group in Xcode and enable the `SilentSpot` target membership checkbox.
5. In Firebase Console → Authentication → Sign-in method, enable Email/Password.
6. Create a Cloud Firestore database.
7. Publish the included `firestore.rules` file using Firebase CLI or paste its contents into Firestore Rules.
8. Build and run the app. Create the first account from the Sign Up screen.

The Swift Package Manager dependency is already configured for `FirebaseCore`, `FirebaseAuth`, and `FirebaseFirestore`.

For a production reward system, move point awards and verification thresholds to trusted Cloud Functions. The coursework MVP currently performs those writes from the authenticated client and restricts them with Firestore rules.
