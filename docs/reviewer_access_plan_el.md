# Reviewer Access Plan

Η εφαρμογή έχει login και connect code flow, άρα Apple και Google reviewers πρέπει να μπορούν να μπουν χωρίς να χρειαστεί να επικοινωνήσουν μαζί σου.

## Προτεινόμενο setup

1. Δημιούργησε έναν demo γονέα/κηδεμόνα στο Supabase Auth.
2. Σύνδεσέ τον με demo μαθητή μέσω `user_access` ή μέσω demo connect code.
3. Βάλε demo δεδομένα για:
   - ανακοινώσεις,
   - βαθμούς,
   - εργασίες,
   - πρόγραμμα/τάξεις,
   - λεξιλόγιο,
   - πληρωμές,
   - φωτογραφία προφίλ προαιρετικά.
4. Δημιούργησε έναν demo καθηγητή, αν θέλεις να εγκριθεί και το teacher flow.

## Τι θα δώσεις στο App Store / Play Console

Parent demo:

- Email: `review-parent@modernlanguage.gr`
- Password: `θα το ορίσεις εσύ`
- Connect code: `θα το ορίσεις εσύ`

Teacher demo:

- Email: `review-teacher@modernlanguage.gr`
- Password: `θα το ορίσεις εσύ`

## Reviewer Instructions Draft

Use the demo credentials below to sign in. If the app asks for a connection code, enter the provided demo connect code. The account contains sample student/class data for review purposes only.

Parent account:
Email: review-parent@modernlanguage.gr
Password: [insert password]
Connect code: [insert code]

Teacher account:
Email: review-teacher@modernlanguage.gr
Password: [insert password]

## Πώς θα το υλοποιήσω όταν μου δώσεις credentials

Θα ελέγξω ότι το login περνάει μέχρι HomePage, ότι το connect code βρίσκει linked user, και ότι ο reviewer βλέπει demo δεδομένα χωρίς να χρειάζεται πραγματική σχολική εγγραφή. Δεν θα βάλω credentials μέσα στον κώδικα.
