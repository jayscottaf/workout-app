# Next Up

A native iPhone workout tracker (SwiftUI + SwiftData, iOS 17+) built around a rotation of days with no fixed schedule. It starts as
**Chest & triceps → Back & biceps → Shoulders & legs**, and the routine is yours to change. Whenever you show up, it offers whichever day is next.

## Opening it

1. Open `NextUp.xcodeproj` in Xcode 16 or newer.
2. Pick an iPhone simulator and press Run.
3. To run on your own phone, select the NextUp target → Signing & Capabilities → choose your Team.

To explore with six weeks of sample history (kept in memory, never saved): Product → Scheme → Edit Scheme → Run →
Arguments → add `-demoData`.

## What it does

| Area | Behaviour |
| --- | --- |
| Rotation | Offers the day after the one you did last, however long ago. You can pick a different day. |
| Routine | Rename, add, remove and reorder days, and choose the exercises each day starts with, or switch to a ready-made routine (Push / Pull / Legs, Upper / Lower, Full body). Open it from Change → Edit routine on Today, or Settings → Days and exercises. Logged workouts and records are kept. |
| Abs | Add-on offered every few days (default 3, change in Settings). |
| Fast logging | Sets pre-filled with today's target, one tap to confirm, +/- for weight and reps (hold to keep changing, or tap the weight to type it, for big jumps like 135 to 225), rest timer starts by itself. |
| Plates and warm-ups | Barbell and plate-loaded exercises show what to put on each side (45 lb bar, standard plates), on the phone and the Watch. The phone also suggests lighter warm-up sets before the first set; they are not logged. |
| Rest on the Lock Screen | The rest countdown shows on the Lock Screen and in the Dynamic Island (a Live Activity), so you can see it without opening the app. |
| Fix a past workout | Open a workout from the calendar or the summary, tap Edit, and change or remove a set. Personal records are worked out again afterwards. |
| Beat last time | Every set shows what you did last time and the number that beats it. |
| Gyms | Each gym has its own equipment list. Machines keep a separate history per machine; dumbbells, barbells and body weight share one history everywhere. |
| Swap | One tap to an equivalent exercise that the current gym can do. The choice is remembered for that gym. |
| During a workout | "Later" moves an exercise to the end when its machine is busy. Add any exercise (abs included), choose 2.5, 5 or 10 lb weight steps, and tick the gym's equipment on or off, without leaving the workout. Later, steps and Add also work on the Watch. |
| Your own exercises and machines | Not on the list? "Create your own" under Add an exercise makes a new exercise (name, muscle, what it uses, rep range), and "Add a machine that is not listed" makes a new machine. Both then work like built-in ones: suggestions, records, swaps, per-gym equipment and the Watch. Manage them in Settings. |
| 20-minute version | Four biggest moves of the day, two sets each, shorter rest. |
| Progress | Personal records, estimated strength chart, weekly sets per muscle group, calendar, monthly recap. |
| Apple Health | Reads runs, walks and body weight. Saves each lifting session as a strength workout. |
| Streak | Counts weeks where you hit your weekly goal (default 3), not days. |
| Pounds or kilograms | Settings → Units. Weights are always saved in pounds, so switching never changes your history; what is shown and typed, the plates (20 kg bar, kilogram plates) and the weight steps (5 lb ↔ 2.5 kg) follow the choice, on the phone and the Watch. |
| Export | Settings → Export workouts (CSV) makes a spreadsheet of every logged set, to save to Files, AirDrop or email as a backup. |
| Privacy | Everything stays on your devices: no accounts, ads, analytics or tracking. `NextUp/PrivacyInfo.xcprivacy` and `NextUpWatch/PrivacyInfo.xcprivacy` are Apple's privacy manifests; The privacy policy is published at https://sites.google.com/view/next-up-privacy-policy (text in `docs/privacy.md`) and linked from Settings. |

## Apple Watch

The Watch app (`NextUpWatch`, watchOS 10+) is installed with the iPhone app. The phone keeps all the data; the Watch
shows today's workout and sends back what you do on it.

- **Today:** the workout that is next, with Start and the 20 minute version.
- **Log a set:** tap weight or reps, turn the crown to change it, tap Log set (or double tap your fingers on newer Watches).
- **Rest:** a countdown ring that taps your wrist when rest is over.
- **Live:** swipe left for elapsed time, heart rate and calories, plus Swap and Finish.
- **Summary:** sets, records, calories and average heart rate.

A workout started on either device shows on both. The Watch records heart rate and calories and saves the workout to
Apple Health; when it does, the phone does not save a second copy. Sets logged while the phone is out of reach are
delivered when it is back in range. Starting a workout and swapping an exercise need the phone nearby.

To try the Watch screens with sample data and no phone, run the `NextUpWatch` scheme with the `-demoData` argument.

## The suggestion rules, in plain language

Each exercise has a rep range, for example 8 to 12.

- **Normal day:** same weight as last time, aim for one more rep on each set.
- **Top of the range on every set:** next time the weight goes up by one real step on that equipment
  (each piece of equipment has its own step size, set under Gyms).
- **One session without progress:** nothing changes, try again.
- **Two in a row without progress:** hold the weight and match last time. If reps fell below the bottom of the
  range, drop about 10% and rebuild.
- **Two weeks or more away:** start about 10% lighter.
- **First time on a machine:** a light starting guess; whatever you log becomes the baseline.

A set is a personal record when it is the heaviest weight, the most reps at that weight, or the best estimated
strength so far on that same equipment. The first session never counts, because there is nothing to beat yet.

## Layout

```
NextUp/Core/        The rules: catalog, rotation, suggestions, swaps, records, streak, recap. Plain Swift, no UI.
NextUp/Models/      What is saved on the phone (SwiftData).
NextUp/Services/    Saving and loading, Apple Health, rest timer, Apple Watch connection.
NextUp/Views/       The screens.
NextUp/Design/      Colours, fonts, shared pieces.
NextUpWatch/        The Apple Watch app: screens, connection to the phone, heart-rate recording.
NextUpRestActivity/ The small extension that draws the rest countdown on the Lock Screen.
Shared/             The data the phone and the Watch send each other, plus the plate and warm-up maths.
NextUpUITests/      Drives the app in the simulator through the main flow and screenshots each step.
Tests/              Unit tests for the rules.
docs/               The privacy policy web page.
```

## Tests

```bash
swift test
```

runs the 34 rule tests (works on a Mac or Linux, no simulator needed).

```bash
xcodebuild test -project NextUp.xcodeproj -scheme NextUp -destination 'platform=iOS Simulator,name=iPhone 16'
```

builds the app and runs the simulator walkthrough. The same two steps run automatically on GitHub for every push
(`.github/workflows/ios.yml`); screenshots are attached to each run under Artifacts.
