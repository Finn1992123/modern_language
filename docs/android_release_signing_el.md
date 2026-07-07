# Android Release Signing

Το Play Store δεν δέχεται release build υπογεγραμμένο με debug key. Το project έχει πλέον Gradle setup που διαβάζει production signing στοιχεία από `android/key.properties`.

## Τι πρέπει να δημιουργηθεί

Στον φάκελο `android/` χρειάζεται αρχείο:

```properties
storePassword=το-keystore-password
keyPassword=το-key-password
keyAlias=upload
storeFile=../upload-keystore.jks
```

Υπάρχει template στο `android/key.properties.example`. Το πραγματικό `key.properties` δεν πρέπει να μπει στο git.

## Δημιουργία upload keystore

Από το root του project:

```powershell
keytool -genkey -v -keystore android/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Κράτα backup του `upload-keystore.jks` και των passwords. Αν χαθούν, μπορεί να μπλοκάρει μελλοντικό update της εφαρμογής, εκτός αν γίνει reset upload key από Play Console.

## Build για Play Store

```powershell
flutter build appbundle --release
```

Το output θα είναι:

```text
build/app/outputs/bundle/release/app-release.aab
```

Αυτό ανεβαίνει στο Play Console.
