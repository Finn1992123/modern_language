# Push notifications setup

The application code and Supabase backend are ready for announcement push
notifications. The remaining steps connect the repository to the production
Firebase and Supabase projects.

## 1. Firebase apps

Create or select a Firebase project and register both native apps with the same
identifiers already used by this repository:

- Android package: `gr.modernlanguage.app`
- iOS bundle ID: `gr.modernlanguage.app`

Install the Firebase CLI and FlutterFire CLI, sign in, and run:

```text
flutterfire configure
```

Select Android and iOS. Confirm that these files are generated/downloaded:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

The Android build applies the Google Services plugin automatically when its
configuration file exists. Do not add placeholder Firebase values.

## 2. Apple Push Notification service

In the Apple Developer account, create an APNs authentication key and upload it
in Firebase Console under Project Settings > Cloud Messaging. The Runner target
already contains the Push Notifications entitlement and the remote-notification
background mode. A physical Apple device is required for the final test.

## 3. Supabase migration and function

Apply the migration:

```text
supabase db push
```

Deploy the sender:

```text
supabase functions deploy send-announcement-notification
```

Create a Firebase service-account key with permission to send FCM messages. In
the Supabase Dashboard, open Edge Functions > Secrets and add its complete JSON
value as:

```text
FIREBASE_SERVICE_ACCOUNT_JSON
```

Never commit the service-account JSON to the repository.

## 4. End-to-end check

1. Install a Firebase-configured build on a physical Android or iOS device.
2. Sign in and allow notification permission.
3. From a `headteacher` account, open Teacher menu > New announcement.
4. Publish once to a class and once to Everyone.
5. Confirm that an unrelated class does not receive or see the class-only item.
6. Tap the push and confirm that the matching announcement opens.
