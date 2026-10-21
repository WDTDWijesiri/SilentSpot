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

Re-publish `firestore.rules` after this feature update. The current rules add authenticated in-app notification creation and the `contributorIDs` field used to prevent the same user from verifying a quiet spot more than once.

The Swift Package Manager dependency is configured for `FirebaseCore`, `FirebaseAuth`, and `FirebaseFirestore`.

## Apple Personal Team compatibility

The current Xcode targets are configured to install with a free Apple Personal Team. Push Notifications and App Groups are intentionally disabled because Apple doesn't include those entitlements in Personal Team provisioning profiles.

- In-app and scheduled local notifications continue to work.
- The Home Screen widget remains installable, but it cannot read the app's latest measurement without App Groups.
- The `functions/sendInboxPush` server code is kept as an optional future upgrade; don't deploy it until remote push is enabled in a paid Apple Developer team.

## Enabling remote push and live widget data later

After joining the Apple Developer Program:

1. In Xcode, open `TARGETS → SilentSpot → Signing & Capabilities` and add **Push Notifications** and **App Groups**.
2. Open `TARGETS → SilentSpotWidget → Signing & Capabilities` and confirm **App Groups** is enabled.
3. Select `group.com.thanuja.silentspot` for both targets. Automatic signing can create it when your Apple Developer team supports that capability.
4. Create an APNs authentication key in the Apple Developer portal.
5. In Firebase Console, open **Project settings → Cloud Messaging → Apple app configuration**, then upload the `.p8` APNs key with its Key ID and Team ID.
6. Install the Firebase CLI, sign in, then run these commands from this folder:

```sh
npm install -g firebase-tools
firebase login
cd functions && npm install && cd ..
firebase deploy --only firestore:rules,functions
```

7. Restore the Firebase Messaging client registration and App Group shared-defaults code before deployment.

Deploying Cloud Functions requires the Firebase project to use the Blaze plan. Set a billing budget alert before deployment. Push delivery must be tested on a physical iPhone; the user also needs to allow notifications.

## Home Screen widget

With a paid team and App Groups enabled, the `SilentSpotWidget` extension can read the latest successfully saved measurement from shared storage. In the current Personal Team build it acts as a quick launcher and doesn't claim to show shared live data.

On the iPhone, long-press the Home Screen, tap **Edit/Add Widget**, search for **SilentSpot**, and add the small or medium widget.

For a production reward system, move point awards and verification thresholds to trusted Cloud Functions. The coursework MVP currently performs those writes from the authenticated client and restricts them with Firestore rules.
