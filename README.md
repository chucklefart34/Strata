# Strata Animation Studio

**Downloads:** every push to `main` builds the apps on GitHub: **Windows** (`Strata-windows.zip` under *Releases › Windows build*: unzip and run `Strata.exe`, with FFmpeg included) and **iPad/iPhone** (*Releases › iOS build*).

**iPad / iPhone:** the project is ready to export for iOS — see [BUILD_IOS.md](BUILD_IOS.md) for making the `.ipa` on a Mac.

When you start a project, choose **2D**, **2D + 3D** (adds the Depth stage) or **Stop motion** (shoot frames with a camera or add photos, with onion skin, then draw over them).

2D animation with real depth. Draw, animate frame by frame, then stage your layers as planes in 3D and move a camera through them for natural parallax. Built with **Godot 4.7.2**.

## Run it
1. Install [Godot 4.7.2](https://godotengine.org/download) (standard build, not .NET).
2. In the Godot Project Manager choose **Import**, then select this folder's `project.godot`.
3. Open the project, wait for the first import to finish, and press **F5** (Run).

To ship it as a desktop app: Project → Export → add your platform → Export Project.
Rendered MP4s include the scene's mixed audio. FFmpeg is also used to import videos as layers. Strata searches common install locations automatically; if it can't find FFmpeg, set it in Home → Interface → FFmpeg → Locate…. For MP4 export, put an `ffmpeg` (or `ffmpeg.exe`) binary next to the exported app or in a `tools/` folder, or install FFmpeg system-wide.

## Workspaces
- **Home**: create or open projects, quick-start guide, interface size.
- **Characters**: build reusable puppet characters from parts, with joints, front/side/back views, mouth shapes and expressions.
- **Draw**: brushes, pencil, eraser, fill, shapes, layers, palette.
- **Animate**: dope-sheet timeline, character posing, reusable actions, onion skin, playback, reusable clips/cycles, timing builder, markers.
- **Depth**: a real 3D set. Layers stand in space on a floor among simple set pieces (box, wall, pillar, ball, ramp). Move anything with the red/green/blue arrows. Turn or tilt layers. Light the set with a sun (drag it on the dial) or a lamp you place, and control shadows with the shadow meter. Use the Shapes tab to add boxes, balls, pillars, cones, pyramids, ramps and rings, then move (W), rotate (E) and scale (R) them. You can draw on any shape (B) and make the shape clear, which leaves your lines floating in 3D. Rough out a space with shapes or a quick set (street, room, forest, hills), then press **Make low-poly set** to turn it into a faceted, toon-shaded set with ink outlines, rolling ground and distance haze that blends with the drawings. Also: layer animation, the scene camera, camera and motion presets, render.
- **Audio**: import dialogue, music and effects (or drag files in), edit and mix them, and lip-sync characters by hand or automatically.
- **Scenes**: manage the scenes in your project.
- **Episode**: assemble scenes (linked) with title cards, credits, on-screen text and transitions; storyboard and shot list; preview with sound; render the whole episode to one MP4.

## Shortcuts
B brush · P pencil · E eraser · G fill · I picker · L line · U rectangle · O ellipse · S select · A lasso · V move · H hand · Space+drag pan · wheel zoom · [ ] brush size · , . previous/next frame · Enter play · N new drawing · D duplicate drawing · + / − insert/remove frame · M marker · 1–9 key mouth shapes (Audio) · Ctrl+C/X/V copy/cut/paste · Ctrl+A select all · Ctrl+D deselect · Enter apply selection · Esc cancel · Delete clear selection · Ctrl+Z / Ctrl+Shift+Z undo/redo · Ctrl+S save · Ctrl+0 fit view

See `DEVELOPMENT.md` for what's done, what's next, and the test plan.
