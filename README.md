# Loop — Uri Bregman's personal fork

This is my personal, modified version of [Loop](https://github.com/LoopKit/LoopWorkspace), the open-source automated insulin delivery app. It is based on **Loop 3.14.9**.

It is **not** the official Loop, it is **not** affiliated with or endorsed by LoopKit or Loop and Learn, and it has not been reviewed by them.

## ⚠️ Read this before you do anything with it

- **This app doses insulin.** A bug here can cause serious harm or death.
- **The changes were made with AI.** Almost all of the code that differs from official Loop was written by an AI coding assistant (Anthropic's Claude) working under my direction. I am not a professional iOS developer, and no experienced Loop developer has reviewed it.
- **It has been tested properly on exactly one person: me.** It runs on my own phone, with my own CGM (Dexcom G7) and my own pump. It has never been tested on anyone else, on other pumps or sensors, or in a clinical setting.
- **The newest commits have had less testing than the rest.** The update to 3.14.9 and the removal of the AI carb feature were checked on the iOS Simulator; see "What is tested" below.
- **It touches dosing-related code.** See "Changes that can affect dosing" below. Do not assume the algorithm is identical to official Loop.
- **It is not medical advice and comes with no warranty** (MIT license, same as Loop). If you build or use it, you do so entirely at your own risk.

If you want a safe, supported Loop, use the official one: <https://loopkit.github.io/loopdocs/>.

## Why it exists

I spent countless hours on this — describing what I wanted, testing on myself, reporting what broke, and going around again — to make Loop fit the way I actually live with it. I am sharing it so the work is visible and backed up, and in case one of the ideas is useful to someone who knows how to review it properly. I am not recommending that anyone run it.

## What is different from official Loop

### Look and feel
- **Home screen rebuilt on iOS 26 Liquid Glass**: glass status pills at the top, a floating glass bottom bar, an "action island" for pod/sensor expiry lines and other notices.
- **A shared glass design system** used across the fork's screens (tiles, buttons, press animations), with separate tuning for iOS 26 and iOS 27 dark mode.
- **Custom app icon.**

### Meals
- **Redesigned Add Meal screen**: one meal can hold several parts (for example fast carbs plus slow fat/protein), each with its own amount, start time, absorption time and food emoji.
- **Searchable food-emoji picker**, grouped by fast / medium / slow.
- **Favourite meals** that reuse the same meal screen, with optional photo.
- **Meal names and emoji kept with the entries** and shown in the carb list.

### Statistics and history
- **History Log**: an append-only, permanent copy of glucose, doses, carbs and loop status, because Loop itself keeps only about 7 days. Can be kept in iCloud Drive.
- **Statistics screen** built on that log: time in range for 3 / 7 / 14 / 30 / 60 / 90 days or all history, a "best run" comparison, insulin and carbs per day, post-meal summaries, a scrollable 7-day glucose chart with day markers, and an HTML report.

### Alerts
- **Custom alerts**: glucose rate / trend alerts and a low-reservoir alert, each with its own sound and settings.
- **Dexcom-style alert tones** (six sounds from the MIT-licensed [vguttmann/dexcom_sounds](https://github.com/vguttmann/dexcom_sounds) project; licence included in `Loop/Loop/CustomAlertSounds`).
- **Alarm volume handling during phone calls.**

### Live Activity
- **Redesigned Lock Screen chart and expanded Dynamic Island**: one shared chart with a 6-hour window, thin dashed grid lines and a trend value aligned with the loop ring.

### Therapy settings
- **Profiles**: save, load, rename and edit sets of therapy settings (correction range, carb ratios, basal rates, insulin sensitivities). Ported by hand from Loop and Learn's `profiles` customization and extended. Loading a profile changes your real settings and sends the basal schedule to the pump.
- **Preferences screen** with guard-railed options, including Basal Lock (see below).

### Following
- **Follow**: an optional, off-by-default feed that publishes read-only status through CloudKit so another person can see your Loop. The follower app itself is a separate project and is **not** in this repository.

### Devices and system
- **Dexcom G7: recovery from a stuck Bluetooth handshake.** When the sensor connects but the handshake keeps failing, the fork resets the connection instead of waiting. This is my own change on top of upstream's G7 fix, made after I lost readings for over an hour twice.
- **Builds and runs on Xcode 27 / iOS 27**, with its own scene-lifecycle handling.
- **Performance fixes** in the fork's own code (caching of alert settings, meal lists, date formatters, batched history writes).

### Removed
- **AI carb estimation** (photo-based carb estimates through Claude / Gemini / OpenAI) used to be part of this fork. I removed it before publishing. It is still in the git history, at tag `ai-carb-v1` in the `Loop` repository. No API keys were ever stored in the code.

## Changes that can affect dosing

I did not set out to change Loop's dosing algorithm, but these parts of the fork are in or next to dosing code. Read the diffs yourself.

- **Basal Lock** (`LoopKit/LoopKit/LoopAlgorithm/DoseMath.swift`): Loop and Learn's customization. When switched on, and glucose is above a threshold you choose (200–300 mg/dL), Loop will not lower basal below your scheduled rate. Off by default.
- **`allowStalePumpData`** (`Loop/Loop/Managers/LoopDataManager.swift`): an extra parameter on glucose prediction that defaults to `false`.
- **Profiles** change the therapy settings Loop doses from, by design.
- **History Log and Follow** add write-only hooks at the end of the loop cycle and where carb entries are stored. They are meant to observe only.
- **G7 reconnect logic** changes when Loop gets glucose readings back after a failed connection.

## What is tested

| What | How |
|---|---|
| Most features above | Daily use on my own phone, by me only |
| Update to Loop 3.14.9 (2026-10-08) | Builds; runs on the iOS 27 Simulator. Not yet a long run on my phone at the time of writing |
| Removal of AI carb estimation (2026-10-08) | Builds; Add Meal, emoji picker and Settings checked on the iOS 27 Simulator |
| Other pumps (Medtronic, Medtrum, Dana), Libre, Eversense, Apple Watch app | **Not tested** |
| Anyone other than me | **Not tested** |

## Where the code is

This repository is the container. The app code lives in git submodules, and seven of them point at my forks (branch `loop-fork`):

| Submodule | What I changed |
|---|---|
| [Loop](https://github.com/Uribregman/Loop) | Almost everything above |
| [LoopKit](https://github.com/Uribregman/LoopKit) | Profiles, Preferences, Basal Lock, shared button style |
| [G7SensorKit](https://github.com/Uribregman/G7SensorKit) | Stuck-handshake recovery |
| [OmnipodKit](https://github.com/Uribregman/OmnipodKit) | Small fork edits in `OmniPumpManager.swift` |
| [NightscoutService](https://github.com/Uribregman/NightscoutService) | Uploads the active profile name |
| [LoopOnboarding](https://github.com/Uribregman/LoopOnboarding), [LoopSupport](https://github.com/Uribregman/LoopSupport) | Minor |

All other submodules are the unmodified upstream versions pinned by Loop 3.14.9.

## Looking at it or building it

I build it with Xcode 27 on a Mac; other Xcode versions are untested. The app requires iOS 26 or later.

```
git clone --recurse-submodules https://github.com/Uribregman/LoopWorkspace
cd LoopWorkspace
xed .
```

In Xcode, select the **LoopWorkspace** scheme (not "Loop") and an iPhone simulator, then Run. The simulator needs no changes. In the app you can add Loop's built-in Pump Simulator and CGM Simulator, so nothing real is dosed.

**Building to a real phone is not something I have set up for other people.** You would need at least to:

1. Put your own Apple team id in `LoopConfigOverride.xcconfig` (`LOOP_DEVELOPMENT_TEAM`).
2. Change `MAIN_APP_BUNDLE_IDENTIFIER` in `Loop/Loop.xcconfig` to your own.
3. Change the three iCloud container identifiers that contain my bundle id, in `Loop/Loop/Loop.entitlements`, `Loop/Loop/Info.plist` and `Loop/Loop/Managers/Follow/FollowerShareManager.swift`.

The browser build (GitHub Actions) from upstream is untested with this fork.

## Credits and licence

All credit for Loop itself goes to the LoopKit authors and the Loop community; this fork only exists because of their work. Loop and this fork are released under the [MIT licence](Loop/LICENSE.md). The Profiles and Basal Lock features come from [Loop and Learn](https://www.loopandlearn.org/custom-code/) customizations.

---

# Original LoopWorkspace README

The Loop app can be built using GitHub in a browser on any computer or using a Mac with Xcode.

* Non-developers may prefer the GitHub method
* Developers or Loopers who want full build control may prefer the Mac/Xcode method

## GitHub Build Instructions

The GitHub Build Instructions are at this [link](fastlane/testflight.md) and further expanded in [LoopDocs: Browser Build](https://loopkit.github.io/loopdocs/gh-actions/gh-overview/).

## Mac/Xcode Build Instructions

The rest of this README contains information needed for Mac/Xcode build. Additonal instructions are found in [LoopDocs: Mac/Xcode Build](https://loopkit.github.io/loopdocs/build/overview/).

### Clone

This repository uses git submodules to pull in the various workspace dependencies.

To clone this repo:

```
git clone --branch=<branch> --recurse-submodules https://github.com/LoopKit/LoopWorkspace
```

Replace `<branch>` with the initial LoopWorkspace repository branch you wish to checkout.

### Open

Change to the cloned directory and open the workspace in Xcode:

```
cd LoopWorkspace
xed .
```

### Input your development team

You should be able to build to a simulator without changing anything. But if you wish to build to a real device, you'll need a developer account, and you'll need to tell Xcode about your team id, which you can find at https://developer.apple.com/.

Select the LoopConfigOverride file in Xcode's project navigator, uncomment the `LOOP_DEVELOPMENT_TEAM`, and replace the existing team id with your own id.

### Build

Select the "LoopWorkspace" scheme (not the "Loop" scheme) and Build, Run, or Test.
