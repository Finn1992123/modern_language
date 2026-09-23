# Αυτόματο ανέβασμα στο Google Play

Η εφαρμογή είναι η `gr.modernlanguage.app`. Χρειάζονται Node.js 20+, Flutter και η υπάρχουσα υπογραφή Android. Δεν χρειάζεται εγκατάσταση npm πακέτων.

## Αρχική σύνδεση (μία φορά)

1. Στο [Google Cloud Console](https://console.cloud.google.com/) επίλεξε το υπάρχον project της εφαρμογής ή δημιούργησε ένα.
2. Στο APIs & Services → Library ενεργοποίησε το **Google Play Android Developer API**.
3. Στο IAM & Admin → Service Accounts δημιούργησε λογαριασμό `modern-language-publisher`. Δεν χρειάζεται ρόλο Owner ή Editor στο Cloud project.
4. Άνοιξε τον λογαριασμό → Keys → Add key → Create new key → JSON. Αποθήκευσε το αρχείο ως `.secrets/google-play-service-account.json` μέσα στο project. Ο φάκελος εξαιρείται από το Git. Μην επικολλήσεις το περιεχόμενο στη συνομιλία. Εναλλακτικά όρισε `GOOGLE_PLAY_SERVICE_ACCOUNT` σε διαδρομή αρχείου εκτός project.
5. Στο [Play Console](https://play.google.com/console/) → Users and permissions → Invite new users βάλε το email του service account. Δώσε πρόσβαση μόνο στο Modern Language, με **View app information (read-only)**, **Release apps to testing tracks** και **Release to production, exclude devices, and use Play App Signing**. Δεν χρειάζονται οικονομικά στοιχεία ή διαχείριση χρηστών.
6. Εκτέλεσε `node scripts/play-console.mjs check`. Αυτό ανοίγει προσωρινό edit, διαβάζει τα tracks και το διαγράφει, χωρίς δημοσίευση.

Πηγές: [ρύθμιση API](https://developers.google.com/android-publisher/getting_started), [δικαιώματα](https://support.google.com/googleplay/android-developer/answer/9844686).

## Ανέβασμα

Γράψε τις σημειώσεις της συγκεκριμένης έκδοσης σε UTF-8 αρχείο (έως 500 χαρακτήρες). Από τη ρίζα του project:

```powershell
# Έλεγχοι και build χωρίς ανέβασμα:
powershell -File scripts/release-android.ps1 -NotesFile .secrets/release-notes.txt

# Δημιουργία και διανομή στην εσωτερική δοκιμή:
powershell -File scripts/release-android.ps1 -NotesFile .secrets/release-notes.txt -Track internal -Upload

# Δημιουργία και υποβολή στην παραγωγή:
powershell -File scripts/release-android.ps1 -NotesFile .secrets/release-notes.txt -Track production -Upload
```

Ο αριθμός build επιλέγεται πάνω από τον τοπικό αριθμό και όσους επιστρέφει το Play στα tracks/bundles/APKs. Η έκδοση ονόματος παραμένει αυτή του `pubspec.yaml`, το οποίο δεν τροποποιείται. Εκτελούνται `flutter analyze`, `flutter test`, και υπογεγραμμένο release build. Κάθε αποτυχία σταματά τη διαδικασία. Αν ιστορικός αριθμός δεν επιστραφεί από το API, η Google μπορεί να απορρίψει επαναχρησιμοποίησή του· τότε αύξησε τον τοπικό αριθμό στο pubspec και ξανατρέξε.

Το build περιλαμβάνει όλες τις τρέχουσες τοπικές αλλαγές. Πριν από πραγματική έκδοση ελέγχουμε το diff και κάνουμε δοκιμή σε συσκευή. Η ρύθμιση του αυτοματισμού δεν ανεβάζει από μόνη της έκδοση.

Το ανέβασμα δεν αντικαθιστά υπάρχον draft ή σταδιακό rollout. Ανεβάζει AAB, ενημερώνει το track, κάνει validate και commit. Σε αποτυχία commit έλεγξε το Play Console πριν ξανατρέξεις. Δεν γίνεται αυτόματη επανάληψη που θα μπορούσε να στείλει δεύτερη έκδοση. Μην κάνεις παράλληλες εκδόσεις από Console και script.

Η υποβολή υπόκειται στους ελέγχους της Google. Αν είναι ενεργό Managed publishing ή η Google απαιτεί ενέργεια στο Publishing overview, το τελικό βήμα γίνεται εκεί. Το script δεν παρακάμπτει αυτές τις απαιτήσεις και δεν επιβεβαιώνει ότι η έκδοση είναι ήδη δημόσια.

Πηγές: [edits.commit](https://developers.google.com/android-publisher/api-ref/rest/v3/edits/commit), [tracks και releases](https://developers.google.com/android-publisher/tracks).

Έλεγχος του αυτοματισμού χωρίς credentials ή δημοσίευση:

```powershell
node --test scripts/play-console.test.mjs
```
