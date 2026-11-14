# Building Strata for iPad / iPhone (.ipa)

The project is set up for iOS: touch controls, an iOS export preset (`export_presets.cfg`) and the Mobile renderer for phones and tablets. Apple only lets iOS apps be built and code-signed on a Mac with Xcode, so the `.ipa` itself has to be made there. It takes about 15 minutes the first time.

## Easiest: let GitHub build it

The repo has a GitHub Actions workflow (`.github/workflows/ios.yml`). Every push to `main` builds an **unsigned `Strata-unsigned.ipa`** on a Mac in the cloud. It's also attached to the **"iOS build"** release, under *Releases* on the repo page, and you can rerun the build from *Actions › Build iOS app › Run workflow*. A build takes roughly 15–25 minutes.

An unsigned `.ipa` has to be signed to install, but tools do that for you with your Apple ID:

- **Sideloadly** (Windows or Mac): connect the iPad, drop in `Strata-unsigned.ipa`, enter your Apple ID and press Start.
- **AltStore** (Windows or Mac): install AltServer, then open the `.ipa` with AltStore on the device.
- The first time, on the iPad: go to Settings › General › VPN & Device Management and trust your Apple ID. On iOS 16 or later, also turn on Settings › Privacy & Security › Developer Mode.

With a free Apple ID the app has to be re-signed every 7 days. AltStore can do this automatically. With a paid developer account it lasts a year.

Private repos have a limited number of free macOS build minutes each month. Public repos build for free.

## Building it on your own Mac

### What you need

- A **Mac** running a recent macOS, with **Xcode** from the App Store. Open Xcode once so it can finish installing its components.
- **Godot 4.7.2** for macOS, plus its **export templates**: in Godot, choose Editor › Manage Export Templates › Download and Install.
- An **Apple ID**. Which kind you need depends on how you'll use the app:
  - A free Apple ID can install the app on your own iPad or iPhone. It stops opening after 7 days, and you then just reinstall it.
  - A paid Apple Developer membership ($99 a year) gives a one-year install, TestFlight and the App Store.

### Steps

1. **Sign Xcode in.** In Xcode, open Settings › Accounts › + and add your Apple ID. Note your **Team ID**: it's shown next to your team in Accounts, or at developer.apple.com › Account › Membership.
2. **Open the project.** In Godot on the Mac, open the `strata` folder (the one containing `project.godot`) and let it finish importing.
3. **Set up the export.** Go to Project › Export… and select the **iOS** preset (it's already set up):
   - **App Store Team ID:** your Team ID.
   - **Bundle Identifier:** something unique to you, such as `com.yourname.strata`.
   - **Export Method (Debug/Release):** *Development* for installing on your own device.
   - **Icons:** optional. Leave them empty to use the project icon.
4. **Export.** Click **Export Project…**, leave the name as `Strata.ipa` and save it. Godot builds the Xcode project and runs Xcode to produce the signed `.ipa`.
   - If Godot reports a signing error, tick **Export Project Only** in the preset and export again.
   - Open the generated `Strata.xcodeproj` in Xcode and choose your team under *Signing & Capabilities*.
   - Choose Product › Archive, then **Distribute App** › *Debugging* (or *Release Testing*) › Export. That gives you the `.ipa`.
5. **Install it.** Connect the iPad or iPhone, open Xcode › Window › **Devices and Simulators**, select the device and drag `Strata.ipa` onto *Installed Apps*. Apple Configurator, AltStore or Sideloadly also work.
   - With a free Apple ID, go to Settings › General › VPN & Device Management on the device and **trust** your developer profile the first time.
   - iOS 16 and later also asks you to turn on **Developer Mode**, under Settings › Privacy & Security.

## Differences from the desktop version

Almost everything is the same: Draw, Animate, Depth (3D sets, low-poly, lights, shapes, drawing on shapes), Capture (it uses the iPad camera), Characters, Audio, Scenes, Episodes, rotoscope and background removal on imported frames. The only differences are the ones iOS forces:

| Desktop | iPad / iPhone |
|---|---|
| Import a video file (MP4, MOV…) | Not possible: Apple doesn't allow apps to run FFmpeg. Export the clip as images from another app and use **Import frames from images…** (same dialog), or import the video on desktop and open the project here. |
| Render to PNG sequence **and MP4** | PNG sequence only. Put it together in a video editor that accepts image sequences, or render the MP4 on desktop. |
| "Show in folder" | A message tells you where the file is in the **Files** app: *On My iPad › Strata*. |
| Keyboard shortcuts | Still work with a hardware keyboard. Touch alternatives are listed below. |

**Files:** projects are saved in *Files › On My iPad › Strata › Projects*. To bring in audio, photos or frames, copy them anywhere under *On My iPad › Strata*, then pick them in the app. To move a project between desktop and iPad, copy the whole project folder.

## Touch controls

| Gesture | What it does |
|---|---|
| One finger or Apple Pencil | Draw, or use the selected tool. Pencil pressure works. |
| Two-finger pinch / drag | Zoom / pan (and rotate) the canvas. In Depth, zoom and pan the 3D view. |
| One finger on empty space in Depth | Orbit the 3D view |
| Two-finger tap | Undo |
| Three-finger tap | Redo |
| Press and hold (about half a second) | Right-click, for example colour swatch options |

## Notes

- An iPad is strongly recommended. iPhone screens are very small for this interface.
- The 3D stage, rotoscope and background removal are heavy. An iPad with an M1 chip or newer is recommended.
- If the camera picture in **Capture** arrives sideways, use **Rotate**. If its colours look wrong, change **Colours**.
- This port couldn't be test-run on a device while it was written. If something misbehaves, note what you did and what you saw. If Xcode or Godot shows errors, copy them so the problem can be fixed.
