# Strata Animation Studio — Development Log

Engine: **Godot 4.7.2 (stable)**, GDScript only, Forward+ renderer.
Run: open the folder in Godot 4.7.2 → let it import → press F5.

---

## Milestone 1 — foundation

The spec recommends making the first milestone "drawing studio + animation timeline + 3D layer workspace + scene editor + save/load working together". That is what this stage covers.

### Completed

**Application shell (Phase 1)**
- Custom dark-charcoal theme built in code (`ui/theme_builder.gd`): rounded panels, coral accent for drawing and animation, teal accent for depth and camera, system UI font stack, HiDPI-aware scaling with an "Interface size" override.
- Hand-written SVG icon set rasterized at runtime (`ui/icons.gd`), crisp at any scale.
- Workspaces: **Home, Draw, Animate, Depth, Scenes**. Switching keeps every selection, because all state lives in the `App` autoload.
- Top bar with workspace tabs, project title with an unsaved marker, undo/redo, project menu (new/open, save, save as, show folder, close) and Save button.
- Status bar with messages and a live readout of scene, layer, frame, fps and resolution.
- Unsaved-changes prompt on quit (save and quit / quit without saving / cancel).
- Beginner tips at the top of each workspace. They can be dismissed and brought back from Home.

**Project system (Phase 1)**
- Project = folder: `project.strata.json` holds the structure, and each drawing is its own PNG at `scenes/<scene>/<layer>/<cel>.png` using relative paths, so projects are portable.
- **Incremental save**: only changed drawings are written.
- Atomic save: the JSON is written to `.tmp` and then swapped in. The previous version is kept as `.bak`, and opening falls back to `.bak` automatically if the main file is damaged.
- Autosave every 2 minutes when there are changes.
- Missing-file warning on open (missing drawings load blank instead of crashing).
- Orphaned PNG cleanup on open, when the undo history is empty, so it's safe.
- Recent projects list. "Save As" copies untouched drawings without loading them.
- **Memory management**: drawings load lazily and are unloaded every 15 s if they are saved and more than 36 frames from the playhead or in another scene. Long scenes never need every frame in RAM.

**Drawing engine (Phase 2)**
- Tools: brush (pressure-sensitive size), pencil, eraser (soft or hard), flood fill (closes under anti-aliased line edges), color picker (samples through the visible layers), line, rectangle, ellipse (Shift constrains), move-drawing, and hand/pan.
- Brush size, opacity (flow-compensated so overlapping dabs reach the chosen opacity), hardness, stabilizer, and pressure toggle. Four presets: Sketch, Ink, Paint, Airbrush.
- Color picker button plus a 16-swatch custom palette (right-click a swatch to store the current color).
- Layers: add, duplicate, delete, reorder, rename, show/hide, lock, opacity, role.
- Canvas: zoom at the cursor, pan (middle mouse, Space, or the hand tool), view rotation, fit / 100%, transparent checkerboard, and trackpad pan/pinch.
- Undo/redo for everything. Strokes store only the changed rectangle, so they are memory-light.

**Animation engine (Phase 3)**
- Exposure-sheet model: a layer holds drawing keys, and each drawing is held until the next key.
- Dope-sheet timeline: per-layer rows, key blocks with hold bars, a ruler with second marks, a playhead, scrubbing, Ctrl+wheel zoom and scrolling. It draws only the visible frames, so it stays fast for long scenes.
- New drawing (N), Duplicate drawing (D), Delete drawing, Insert frame (+), Remove frame (−), drag a key to retime it, and double-click an empty cell to start a drawing.
- Onion skin: red for earlier drawings and green for later ones, with an adjustable count before and after (shader-tinted).
- Playback at 12, 15, 24, 25 or 30 fps, with loop, first/last and step controls.

**3D layer environment and camera (Phase 5)**
- Every layer is a textured plane in a real 3D scene, placed by depth, X/Y offset, scale and rotation.
- **"Keep apparent size"** (on by default): pushing a layer back changes only its parallax, not its framing. This is the multiplane-camera behavior animators expect.
- Free view: orbit, pan and zoom, with a ground grid, the scene camera's frustum and an outline on the selected layer.
- Click a layer's painted pixels to select it. Drag to move it, and Shift+drag to push it deeper (undoable).
- Quick depth placements: Far, Back, Mid, Subject, Front.
- Depth list sorted nearest to farthest, with per-layer depth sliders.
- **Camera view** with letterboxing, rule-of-thirds and title-safe guides.
- Animated scene camera: pan, dolly, zoom, roll and shake, with an easing per key (smooth, linear, ease in, ease out, hold). Editing auto-keys the current frame. Camera keys appear as diamonds on the timeline's camera row.
- Camera presets: push in, pull out, pan left/right, parallax truck, crane up, zoom in, impact shake.
- Perspective (parallax) or orthographic (flat) lens per scene.

**Rendering (early part of Phase 11)**
- Renders the current scene through the animated camera at project resolution to a PNG sequence (optionally with a transparent background), with a progress bar and cancel.
- MP4 encoding through FFmpeg when it is found next to the app, in `tools/`, or on PATH. FFmpeg runs on a background thread, so the user never operates it directly.

**Scenes (Phase 6, partial)**
- Scene list as cards with thumbnails: add, duplicate (deep copy of drawings), delete, reorder, double-click to open.
- Scene settings: name, length (frames and seconds), background color.
- Layer stack overview, plus add-a-layer-by-role buttons (Background, Midground, Character, Foreground, Effect), each at a sensible default depth.

## Update — CapCut-style Export, GitHub iOS builds

### Completed
- **Export sheet** (`ui/dialogs/export_dialog.gd`, `render/export_settings.gd`):
  - Choices: Resolution (480p, 720p, 1080p, 2K, 4K), Frame rate (12, 24, 25, 30, 50, 60), Quality (Lower, Recommended, Higher ≈ 5 / 9 / 16 Mbps at 1080p30) and Format (MP4, MOV, GIF, PNG frames). Also Include sound, and Transparent background (PNG only).
  - Shows a live size estimate with duration, size, fps and bitrate.
  - Defaults: file name and save folder (`<project>/exports`). A progress state, then a done state with Open / Show in folder / Export another.
  - Opened from the new **Export** button in the top bar (Ctrl+E): it exports the episode when you're in Episode, otherwise the current scene. Animate's footer, Depth's render section and Episode's button open it too.
- **Rendering:** scenes render straight at the chosen size, so 3D and text stay sharp. Episodes render at project size and FFmpeg scales them. Changing the frame rate retimes with FFmpeg's `fps` filter. MP4/MOV are H.264 at the target bitrate with `+faststart`. GIF uses a two-pass palette (up to 960 px wide, 25 fps). Temporary frames are deleted after encoding.
- **On iOS / without FFmpeg:** only PNG frames (plus a WAV of the sound), with a note explaining why.
- **GitHub iOS builds:** `.github/workflows/ios.yml` (macOS runner):
  - Downloads Godot and its export templates, imports the project and exports the Xcode project.
  - Builds it unsigned with `xcodebuild archive` and packages `Strata-unsigned.ipa`.
  - Uploads it as an artifact and to a rolling `ios-latest` prerelease.

## Update — iOS port (iPad / iPhone)

### Completed
- **Building the .ipa:** `export_presets.cfg` has an iOS preset (arm64, iOS 15+, iPhone and iPad, Files-app access on, camera and photo usage text). The Mobile renderer is used on mobile, ETC2/ASTC texture import is on, and the window is fixed to landscape. Step-by-step `.ipa` instructions are in `BUILD_IOS.md`. They need a Mac with Xcode; the build itself can't be made on Linux.
- **`Platform`** (`core/platform.gd`): detects mobile and whether the system allows running other programs (not on iOS). On mobile, projects go in user:// (the app's Documents folder, visible in Files), and `reveal()` replaces `OS.shell_open`.
- **No FFmpeg on iOS:**
  - The locator returns nothing on mobile.
  - The video dialog explains why and offers **Import frames from images…**, which puts a picked image sequence on a new layer one frame per step. It works on desktop too.
  - Renders produce a PNG sequence only.
- **Touch**
  - Canvas: one finger or Pencil draws. Two or more fingers pinch-zoom, pan and rotate, and cancel any stroke the first finger started.
  - Two-finger tap undoes, three-finger tap redoes.
  - Apple Pencil pressure is read from touch-drag events, because the mouse events made from touches carry none.
  - Depth: two fingers pinch-zoom and pan.
  - Anywhere: press and hold sends a right-click (`Main._input`).
- **Touch-sized UI:** on mobile the UI is scaled from the screen's points scale × 1.1.
- **Capture:** a **Rotate** option, because tablet cameras can deliver sideways pictures.

### Not possible on iOS
- Video import and MP4 encoding, because both need FFmpeg.

## Update — project types: 2D, 2D + 3D, stop motion

### Completed
- **Choosing a type:** the Home "Start a new project" card asks *What are you making?* — **2D**, **2D + 3D** or **Stop motion**.
  - The choice is stored as `ProjectData.mode` ("2d", "2d3d" or "stopmotion"). Projects made before this load as "2d3d", so nothing changes for them.
  - Choosing Stop motion sets the frame rate to 12 fps.
- **Tabs for each type** (`Main.workspaces_for`):
  - 2D: Home, Characters, Draw, Animate, Audio, Scenes, Episode. There's no Depth tab.
  - 2D + 3D: everything, as before.
  - Stop motion: Home, **Capture**, Draw, Animate, Audio, Scenes, Episode.
- **What 2D and stop motion turn off:** in these projects the 3D stage is off. There's no floor, set pieces, low-poly set, stage lights or haze, and layers render as a flat stack in layer order (no depth, turn or tilt). The 3D set guide row doesn't appear. Render and Episode use the same pipeline, just flat.
- **Render scene…** is now also in the Animate footer, so projects without a Depth tab can export a PNG sequence and an MP4.
- **Capture workspace** (`ui/workspaces/capture_workspace.gd`):
  - **Camera:** live camera through Godot's `CameraServer`, with a camera picker and Start/Stop. It turns on `monitoring_feeds` and picks the largest camera format on newer Godot versions.
  - **Picture handling:** RGB / YCbCr / two-plane YCbCr conversion in a shader, with a manual "Colours" override if the picture looks green or purple. Mirror option. The picture is cropped to fill the canvas and rendered at canvas size, so captures match the project.
  - **Shooting:** Capture (Space or Enter) adds the next frame. "Each photo lasts N frames" sets ones or twos. Also Delete last (Backspace), Retake this frame, Play (P), and Back to live.
  - **Onion skin:** up to 3 previous photos over the live picture, with a strength slider. O toggles it, and holding F flips to the last photo.
  - **Other:** framing grid, a filmstrip of the last 40 frames (click to jump), and **Add photos from files…** (natural file-name order, cropped to fill the canvas).
  - **Undo:** each capture or import is one undo step (`Ops.add_photos`, `Ops.remove_photo`).
- New stop-motion scenes get a **Photos** layer with a **Draw on top** layer above it. Retouching and drawing over photos uses the normal Draw/Animate tools and onion skin.

### Test plan additions
1. Create one project of each type and check which tabs appear.
2. In 2D, draw on two layers and render from Animate: the result should be flat and in layer order.
3. In stop motion, start a webcam and capture 5 frames while moving an object. Onion skin should show the previous frame. Play, delete the last frame, then retake one.
4. Add 10 photos from files and check their order and the crop.
5. Open an older project: it should still have the Depth tab and its set.

### Known limitations
- Camera support depends on the platform's Godot camera backend. If no camera is listed, use Add photos.
- Imported photos are kept in memory until the project is saved. Save often on very long shoots.

## Fix — background removal looked like it did nothing

- **Cause:** after the video preview was added, the preview showed the *original* frame by default. Changing Keep, Sensitivity or other settings didn't switch to the processed view, and before Result had been pressed once, setting changes did nothing at all. So background removal appeared broken.
- **Now:**
  - Any change to Elements or the look switches to a live **Result** at the playhead. It's debounced and only one render runs at a time.
  - Scrubbing shows the original while you drag, then refreshes the result when you stop.
  - Pressing pause refreshes it too.
  - Drawing a subject box or finishing tracking shows the result.
- A status line under the preview shows how much of the frame is kept. It warns when nothing or everything is kept, with what to adjust.
- Subject mode safety net: if the colour model keeps almost nothing inside the box, the cut is loosened. If that still fails, an oval inside the box is kept, so the subject never vanishes entirely.
- Scrubbing with roto on no longer re-picks (and resets) the palette. Only "Preview look" re-picks it.

## Update — 3D set guide in Draw / Animate

### Completed
- New **"3D set (from Depth)"** row in the Layers panel. It shows the Depth workspace's set (floor, shapes, low-poly set, drawings on shapes, light and shadows, haze) through the scene camera at the current frame, so you can draw over it.
  - Eye toggle, opacity slider, and a button that puts it behind your drawings (default) or in front for tracing.
  - It's a guide only. It's never exported, and renders still use the real 3D set.
  - The row only appears when the scene has a set (shapes, floor or low-poly). Settings are `stage.draw_guide*` and undoable.
- `DepthView` renders the guide in its own small viewport (up to 1280 px wide). It only re-renders while a canvas is showing the guide, and only when something changes.
- Drawing planes now live on visual layer 4 (`DepthView.PLANE_LAYER`), so the guide can show the set without the drawings. The output cameras (scene camera, render, episode feed) use `ART_MASK` = set + drawings.

### Test plan additions
1. Build a quick set in Depth, then switch to Draw. The set should appear under the layers in the camera framing. Scrub frames with an animated camera: the guide should follow.
2. Toggle the eye, change the opacity, and flip it to the front.
3. Render the scene: the output should be unchanged, with no double set.

## Update — pick a subject and track it (background removal)

### Completed
- New Elements option, **"A subject I pick (tracked through the clip)"** (`drawing/subject_tracker.gd`, matte mode 5):
  1. Drag a box around the subject on the preview. Optionally paint **+ Subject** and **− Background** marks.
  2. Press **Track subject**. You can add more boxes on frames where the track slips and track again; each box becomes a key, shown as a green diamond on the range bar.
- **How it works** (no machine-learning models, runs offline):
  - Colour model: subject vs background histograms (16 levels per channel), with box-centre weighting, your marks weighted 8×, and two GrabCut-style refinement passes, stored as a 64×64 lookup table.
  - Tracking: mean-shift on the probability map over the proxy frames, forward and backward from every key. Between keys the two tracks are blended, the box size follows the subject's mass, a lost subject is held, and the box path is smoothed over time.
  - Per-frame mask (256 px wide): probability × a "near the box" prior, keeping only the blobs that belong to the subject and filling small enclosed holes.
  - Full-resolution edge (`matte_key.gdshader`): the low-res mask sets the core, and near its edge the real pixel colours decide (the "Edge detail" slider). The existing Clean up / Grow pass runs after that.
- Sensitivity sets the colour cut. Invert keeps only the background. The keep-area crop still applies.
- The subject is tracked automatically when you press Import if you haven't tracked yet. The Result preview shows the cut-out on any frame.

### Test plan additions
1. Import a clip of a person walking past a busy background. Box them on one frame, track, scrub (the green box should follow), then press Result on a few frames.
2. Add − marks on a background colour that leaks in, then re-track: the leak should disappear.
3. Add a second box late in the clip where the person has turned, then re-track and check the middle of the clip.

### Known limitations
- The colour model can't separate a subject from background of the same colour. Use − marks, Clean up, or the keep-area box.
- Tracking runs on the low-res proxy (at most 12 fps), so very fast motion between proxy frames can slip. Add a key there.
- Thin details far from the mask edge (a raised hand outside the box margin) can be cut. Draw the box a bit larger.

## Update — Shapes tab, clear and drawable shapes, steadier rotoscope

### Completed
- The Depth workspace's right panel now has tabs: **Layer**, **Shapes**, **Light** and **Camera** (camera and render).
- Toolbar tools: **Move (W)**, **Rotate (E)**, **Scale (R)** and **Draw (B)**.
  - Rotate draws rings around the X, Y and Z axes and snaps to 15° steps (Alt for free movement).
  - Scale resizes along the piece's own sides: height grows up from the floor, width and depth grow both ways. The centre box resizes evenly.
  - Layers can be rotated (rotation, turn, tilt) and scaled with the same tools.
  - Shortcuts: Ctrl+D duplicates, Delete removes, Esc deselects. The view takes keyboard focus when you click in it.
- **Shapes tab**
  - A list of every shape to select from.
  - Add buttons for Box, Ball, Pillar, Cone, Pyramid, Ramp, Ring and Wall.
  - Selected shape: name, shape type, role, position, rotation (three axes) and size, with ½×/0.9×/1.1×/2× quick-resize buttons, plus colour.
  - **See-through** (solid → clear) and **Casts a shadow**. A fully clear shape is invisible in the picture but can still cast its shadow, and stays visible in the editor as a faint blue ghost on the helper layer.
- **Draw on shapes**: drag on any set piece to paint on its surface, with pen colour, size (in world units, so dabs stay the same size on big and small shapes), an eraser and Clear drawing.
  - Drawings sit on a slightly inflated, UV-mapped "paint shell" (`depth/shape_mesh.gd`), so they stay when the shape is made clear. Strokes cast shadows shaped like the lines.
  - Each stroke is one undo step (`Ops.commit_prop_paint`).
  - Drawings are saved as PNGs in `scenes/<scene>/props/`, referenced from `prop_paint` in the scene JSON. Duplicating a shape copies its drawing.
- Picking set pieces now tests their real triangles, so you can click through the hole in a ring.
- Low-poly set: cone, pyramid and ring are supported. Partly clear shapes use a see-through toon shader, and ink outlines are hidden on mostly clear shapes.
- **Rotoscope**: new "Steady over time" slider, on at 45% by default (`TemporalStabilizer`, `shaders/temporal_hold.gdshader`).
  - Where the source hasn't really changed since a pixel was last refreshed, the previous frame's colours and lines are kept, so flat areas and lines stop flickering.
  - A held reference copy of the source makes slow drifts refresh once they add up.

### Test plan additions
1. Shapes tab: add a Ring. Rotate it with E, scale it with R (drag the centre box and an axis), and undo each step.
2. Press B, set the pen colour, and draw on a Ball. Set See-through to 100%: the strokes should float in 3D, and orbiting should show them wrapping the sphere.
3. Save, close and reopen the project: the drawing should still be there.
4. Import a video with roto at Steady 0 and at 60, and compare flicker on a still background.

### Known limitations
- Brush dabs are clipped where two UV patches meet (box faces, the sphere seam). Draw across a seam in two strokes.
- Changing a shape's type after drawing on it rewraps the drawing with the new shape's UV layout.
- With very high Steady values, slow subtle motion (breathing, drifting shadows) can freeze until it builds up past the threshold.

## Update — blockout → low-poly set

### Completed
- **Blockout tools**
  - Quick sets that drop in a rough layout: Street, Room, Forest, Hills, plus Clear. Undo restores your own layout.
  - Ready pieces: Building, Tree, Bush, Rock, Hill. These are blockout shapes with a role set.
  - Each shape has a "Becomes" option: Automatic, Plain shape, Building, Tree, Bush, Rock or Hill.
  - Blockout shapes are tinted by role, so the rough set reads at a glance.
  - Grid snap (0.5 units) when dragging set pieces and the lamp. Hold Alt to move freely.
- **Make low-poly set** (`depth/lowpoly_builder.gd`, `LowPolyBuilder`)
  - Shapes are split into facets and get a seeded wobble. Shared vertices move together, so no cracks appear.
  - Each facet gets its own colour from a palette: Storybook, Dusk, Pastel, Desert, or Ink & paper. Shapes you coloured yourself keep that colour.
  - Roles add detail:
    - Building: gable roof, windows and a door.
    - Tree: a round canopy, or stacked cones for tall trees.
    - Bush: clustered blobs.
    - Rock: a rough icosphere.
    - Hill: a grassy dome.
  - Optional rolling terrain that stays flat around the acting area.
  - Toon banded lighting (`shaders/lowpoly_toon.gdshader`) or soft lighting.
  - Ink outline from an inflated hull (`shaders/lowpoly_ink.gdshader`), with colour and thickness controls.
  - Meshes are only rebuilt when a shape or a style setting changes. Moving a piece just moves it.
- **Distance haze**: depth fog in the scene's background colour. It applies to the editor view, renders and episode feeds.
- Settings live in `stage.lowpoly`, `stage.haze` and `stage.snap`, and every change is undoable.

### Test plan additions
1. Depth → 3D set → Street, then Make low-poly set. You should see buildings with roofs and windows, trees, and ink outlines.
2. Change the palette and the detail level, and press Reshuffle: the set should rebuild with each change.
3. Move a building with the arrows: it should snap in 0.5 steps, and move freely with Alt held.
4. Set "Becomes" to Rock on a box and check that it changes.
5. Turn on haze: far pieces and far drawing layers should fade toward the background colour.
6. Render the scene: it should match the camera view.

### Known limitations
- The ink hull uses world-space thickness, so outlines get thinner with distance.
- Only shapes with an ink outline get one: windows and terrain don't have outlines.
- Very large shapes are capped at 3 subdivision levels.

## Update — working 3D set, lighting, video import preview

### Completed
- **3D set** (per scene, `SceneData.stage`):
  - Floor with colour and height. Scenes saved before this update load with the floor off, so their look doesn't change.
  - Set pieces (box, wall, pillar, ball, ramp) with size, turn, lift and colour. They catch shadows and can be selected and moved in the view.
- **Move gizmo** on the selected layer, set piece or lamp: drag an arrow to move along one axis. Every layer gets a faint outline, so empty layers are still visible in space.
- **Layers in 3D**:
  - Turn and tilt.
  - "Lit by the light": per-pixel shading when on.
  - "Casts a shadow": uses a shadow-only alpha-scissor twin, so the shadow follows the painted pixels.
  - "Stand on floor" moves a layer so the bottom of its drawing touches the floor.
- **Light**:
  - Choose sun (direction/height dial plus sliders), lamp (placed with the gizmo, adjustable reach) or none.
  - Light colour, brightness and ambient fill.
  - Shadows on/off, darkness and softness, with the **shadow meter** swatch.
  - Renders and episode feeds share the stage's ambient light through `DepthView.make_environment()`.
- **Undo**: every stage edit is undoable via `Ops.set_stage_value`, `commit_stage_edit`, `add_prop`, `set_prop_field` and `delete_prop`, with the `App.stage_changed` signal.
- **Video import preview**:
  - Low-res proxy frames are decoded in the background, so you can play and scrub straight away.
  - Space plays the clip. The IN/OUT handles sync with Start/Length; Set in / Set out work at the playhead.
  - Drag a box on the picture to set the keep-area crop.
  - Original/Result toggle. Result processes the frame under the playhead.
  - Only the chosen range and area are imported, matted and rotoscoped.

### Test plan additions
1. Depth: draw on two layers. Add a Box. Set the light to Sun and drag the dial: the drawings' shadows should move across the floor and the box.
2. Turn on "Lit by the light" on a layer and move a lamp near it: it should brighten.
3. Drag each gizmo arrow, then undo. Do the same for a set piece and the lamp.
4. Shadow darkness at 0 should give no visible shadow; at 100 the shadows should be dark. The meter should follow.
5. Import a video: it should start playing within a second or two. Set IN/OUT, drag a box, press Result, then Import. Only that range and area should arrive.

### Known limitations
- Set pieces are picked with a box test, so round shapes are picked slightly generously.
- The shadow shape uses a 0.35 alpha cutoff (no soft-edged shadows from soft brush edges).
- The preview area box is rectangular only.

## Milestone 5 — Episodes, titles and full-episode render (this stage)

### Completed
**Episode production (Phase 9)**
- New **Episode** workspace with an episode library: title, number, production status (Planning → Final), description, and running time.
- An episode is a running order of **references** to scenes (`data/episode_data.gd`). Nothing is copied, so editing a scene updates every episode that uses it. Removed scenes show as "missing" instead of breaking.
- A new episode starts with a title card, every scene in order, and end credits.
- **Episode strip** (`ui/timeline/episode_strip.gd`): shots at their real lengths with thumbnails, transitions shown as overlaps, a timecode ruler, click to scrub, **drag to reorder**, Ctrl+wheel zoom and Fit. The episode soundtrack shows underneath, and you can drag music to retime it.
- **Storyboard view**: a grid of shot cards with thumbnails, length, transition, and editable notes (action, dialogue).
- **Shot list**: #, shot, type, start timecode, length, transition and notes, clickable.
- Per shot: change the scene, **trim start/end**, transition in (cut, fade through black, dissolve, wipe) with its length, duplicate, move, remove, and open the scene in Animate.

**Titles, credits and text (Phases 10 and 14)**
- Title cards with four styles (classic, bold, minimal, chapter), animations (fade, rise, typewriter, none), background/text colors and duration (`episode/title_view.gd`).
- **Scrolling credits**: one line per credit, `#Heading` for headings, `Role - Name` for two-column credits.
- **On-screen text over any shot**: lower third (name + role), subtitle or caption, with a frame range and soft fades.

**Preview and render (Phase 11)**
- **Full-episode preview with sound**: one wall-clock timeline drives the scene picture (`episode/scene_feed.gd`, the scene camera through the shared 3D stage), the compositor (`episode/episode_compositor.gd`: transitions, fades, titles, overlays) and the audio engine. Scene audio follows each shot, trims included, and the episode soundtrack plays across scenes.
- **Full-episode render** (`render/episode_renderer.gd`): every frame in order at full resolution, through the same compositor. Dissolves and wipes render both scenes exactly, frame by frame. Then one soundtrack is mixed (each scene's audio at its position and trim, plus the episode music) and a single **MP4 with sound** is encoded, with progress and cancel.
- The audio mix-down was generalized (offsets and time windows per clip) so scene and episode renders share one mixer.
- Preview viewports only render while the Episode workspace is visible.

**Video import as layer** (`ui/dialogs/video_import_dialog.gd`, `Ops.add_video_layer`)
- Layers panel → film button, or drag a video onto the window. Accepts MP4, MOV, M4V, WebM, MKV, AVI, OGV, GIF, MPG, WMV and FLV.
- FFmpeg decodes straight into canvas-sized, transparent-padded RGBA PNGs inside the project. Each frame becomes a normal drawing key at project fps, either every frame or on 2s/3s. The video is a regular layer: draw over it, move it in 3D, animate it, render it.
- Options: start time, length, frame step, **reference only** (locked, faded, never rendered, for rotoscoping), and **import the sound** as a WAV clip lined up with the first frame.
- Shows the source duration, fps and size, the frame count and estimated disk use, with a warning for very long clips.
- FFmpeg runs as a separate process with live progress (counting written frames) and **Cancel**, which removes partial frames. Frames load lazily from disk, so long clips don't fill memory. One undo step removes the layer, the audio and the scene extension.
- Needs FFmpeg (next to the app, in `tools/`, or on PATH). Without it the dialog explains how to add it.
- **Auto-rotoscope** (checkbox in the video import window): every decoded frame is redrawn on the GPU in a cel style (`drawing/toon_processor.gd`). Pass 1, `shaders/toon_blocks.gdshader`: a Kuwahara filter (edge-preserving smoothing) flattens detail into painted patches, a colour boost is applied, then colours are snapped to brightness bands plus coarser colour steps (YCbCr), giving flat colour blocks. Pass 2, `shaders/toon_lines.gdshader`, reads pass 1 through a BackBufferCopy and draws solid outlines wherever neighbouring blocks differ, so lines follow shapes instead of video noise (no outline against transparent padding). Settings: simplify (block size), colour bands, outline thickness, outline detail, colour boost, outline colour. They're specified at 1080p and scaled to the canvas resolution. **Preview look** rotoscopes one frame from the start point and updates live as you change sliders. Processing has a progress bar and can be cancelled. The result is normal drawings you can touch up by hand.

**Video import "Elements": choose what to keep** (`drawing/matte_processor.gd`, `shaders/matte_*.gdshader`)
- **Moving subjects / remove a still background**: a clean background plate is built on the GPU as the per-pixel **median of 9 frames** spread over the import range (`matte_median`, a 19-step sorting network), so anything that moves drops out. Pixels that differ from the plate (3×3-blurred difference) are kept. Best with a locked-off camera.
- **Everything except a colour**: chroma key in YCbCr with **spill removal** (the key hue is pulled out of kept edges). Click the preview to pick the colour.
- **Remove light areas / remove dark areas**: brightness keys (white paper, sky, black backgrounds).
- **Keep only an area**: a keep-box with left/right/top/bottom edges and a soft edge.
- **Cleanup** (`matte_clean`): blur-and-recut of the mask fills holes, removes specks and smooths the edge, plus **shrink/grow**. **Keep the removed part instead** inverts the selection (background only).
- Applied per frame **before** auto-rotoscope: removed areas are transparent, so they get no colours or outlines, and the palette is picked from the kept parts only. The preview shows the result on a checkerboard.
- No AI segmentation: a bundled person-segmentation model would need an ML runtime, which isn't available in pure GDScript, so moving-camera background removal isn't automatic. Use colour/brightness keys or the keep-area box there.

### Test plan additions
1. Episode → **+** creates "Episode 1" (title, all scenes, credits). Press **Play**: the whole episode plays with sound.
2. Drag a shot in the strip to reorder it. Pick a shot → Transition "Dissolve" (24 fr), trim start 12 fr. Watch the overlap in the strip.
3. Edit the title card: style Bold, animation Rise, subtitle. Edit the credits text using `#Heading` and `Role - Name`.
4. On a scene shot, add on-screen text "Mia\nThe inventor" as a lower third for frames 0–72.
5. **+ Music…** adds a song across the episode. Drag it in the strip, lower its volume.
6. Go to Animate, change a drawing in a scene, come back: the episode shows the change (non-destructive).
7. **Render episode…** gives PNG frames, a WAV soundtrack, and one MP4 with picture, transitions, titles and sound in sync.
9. Import a short video with **Auto-rotoscope** checked → Preview look → adjust Simplify/Colour bands/Outline → Import: frames become flat colour blocks with black outlines.
8. Layers → film button (or drag an MP4 onto the window) → 5 s on 2s with sound → a new layer with a drawing every 2 frames plus an audio track. Draw over it, press Enter: picture and sound stay in sync.

### Bug fixes
- **Pen strokes started with an oversized dot.** Hovering pens report 0 pressure, which the canvas treated as full pressure, and press events carry no pressure, so the first dab was stamped at full brush size. Now the first dab waits for the first real pressure reading, hover no longer changes the stored pressure, pen pressure is lightly smoothed to remove touch-down spikes, a dropped reading mid-stroke keeps the last value, and a pen tap draws a light dot. Mouse drawing is unchanged (full pressure).

- **"Won't connect to FFmpeg."** Detection only looked next to the running executable (the Godot editor itself when run from the editor), `tools/`, and the process PATH. The new `core/ffmpeg_locator.gd` checks a user-chosen location (Home → Interface → FFmpeg → Locate…, which accepts the executable or the unzipped folder), nested folders next to the app, the Strata project and the user project, every PATH entry read directly, and common install locations: Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`), MacPorts, winget (Links and Packages), Scoop, Chocolatey, `C:\ffmpeg`, unzipped `ffmpeg*` folders in Downloads/Desktop/C:\, `/usr/bin`, Snap and Flatpak. Every candidate is run with `-version` before it's accepted. When nothing works, the video dialog and Home show OS-specific help (including the macOS quarantine fix) and a list of what was found but couldn't run.

- **Auto-rotoscope colours looked like a heat map.** Banding brightness and rounding the chroma channels separately created false-colour cycles. Colours are now **palette-based**: k-means in CIE Lab (`drawing/palette_tools.gd`) picks 2–10 representative colours from the clip once (from the preview frame, or from six frames spread across the clip), and the shader snaps each smoothed pixel to the nearest palette colour in Lab and paints it with that entry's output colour. The palette is the same for every frame, so colours don't flicker. New controls: **Look** presets (Video colours, Night & flame, Ink & paper, Red & white, Sunset, Ocean, Forest; preset colours are mapped onto the clusters dark → light), **number of colours**, **shadows to solid ink** (dark areas become the ink colour, for graphic silhouettes), editable **palette swatches** to recolour any area, **clean up specks** (a neighbour-majority filter removes tiny noise islands before outlining), and a shared ink/outline colour.

- **Auto-rotoscope regions were blotchy and ragged on textured footage.** The processor (`drawing/toon_processor.gd`) is now a multi-pass GPU pipeline in one render, each pass reading the previous through a BackBufferCopy, all with `blend_disabled` so passes replace pixels exactly: two **edge-preserving blur** passes (`shaders/toon_bilateral.gdshader`) wash out paper grain, film noise and texture but keep real edges; then palette snap + ink (`toon_blocks`, now reading the previous pass); then three **shape-smoothing** passes (`shaders/toon_mode.gdshader`, a distance-weighted majority vote over palette colours in a 40-sample disc) round jagged borders and swallow small islands; then outlines along the smoothed borders. New controls: "Remove texture & detail" (blur strength) and "Smooth shapes" (majority-filter radius), replacing the speck checkbox.

- **Auto-rotoscope: smoothing removed the outlines, and only 10 colours were allowed.** Lines are now a separate layer traced from the **original frame**, not from the smoothed fills: an inner viewport runs a light edge-preserving blur, then **XDoG** line tracing (`shaders/toon_xdog.gdshader`, difference of two Gaussians with a soft ink threshold), then thickening (`toon_line_dilate`), then smooth-and-cut (`toon_line_smooth`: blur plus an anti-aliased 50% cut, so long strokes become clean curves and specks disappear). The final pass composites that mask in the ink colour **on top of** the smoothed colour fills, so it looks traced with the colours underneath. Outlining every colour area is now optional. New controls: Trace ink lines, Line thickness, Line detail, Line smoothness, Also outline every colour area. The palette limit was raised from 10 to **32** colours (shader arrays, majority filter bins, k-means).

### Known limitations added this stage
- Auto-rotoscope uses one palette per clip (stable colours), but region edges can still wobble slightly from frame to frame on noisy footage. Higher Simplify or importing on 2s reduces it.
- In the live **preview**, dissolves and wipes between two scenes use a frozen last frame of the outgoing scene. The final render is exact.
- Fades through black dip only the picture. Audio crossfades at transitions aren't automatic yet (use clip fades).
- The preview switches the app's current scene as it plays, so scenes with many characters may hitch briefly at cuts.
- Episode rendering is offline and switches scenes per frame during transitions, so it's slower than real time.

## Milestone 4 — Audio Studio and lip-sync

### Completed
**Audio import and storage (Phase 8)**
- WAV, OGG and MP3, from "Import audio…" (several files at once) or by **dragging files onto the window**. Dropped images become layers. FLAC isn't decodable at runtime in Godot, so convert it to WAV or OGG first; the app says so.
- Files are copied into the project's `audio/` folder and referenced by relative path, so projects stay portable. Save As copies them, and missing files are reported on open and marked in the timeline.
- Import picks a track type from the name and length (dialogue, music, SFX or ambience) and extends the scene if the audio is longer.

**Audio engine (`core/audio_engine.gd`, autoload `Audio`)**
- Waveforms are decoded on a background thread with `AudioStreamPlayback.mix_audio()` (Godot 4.4+) and cached next to the audio file as `.peaks`, so each file is analysed only once.
- **Synchronized playback**: picture playback now runs on the wall clock, and every clip is checked against the playhead each frame. Clips are started, stopped or re-seeked when they drift more than 90 ms, including on loop wrap.
- **Frame-by-frame scrubbing**: stepping or scrubbing plays a short slice of audio at each frame. It can be toggled.
- Mute, solo, track volume, clip gain, fades, clip looping and master volume, with an output level meter.
- **Offline mix-down** to a 16-bit stereo WAV the exact length of the scene (on a thread).

**Audio Studio workspace**
- Multitrack timeline (`ui/timeline/audio_timeline.gd`): waveforms, drag clips to move them (frame-snapped), drag edges to trim the start or end, fade ramps, M/S buttons, a time ruler, scrubbing, markers (double-click the ruler), and Delete to remove a clip.
- Clip panel: start frame, trim start, length, gain, fade in/out and loop. Track panel: name, type, volume, reorder, delete.
- Split at the playhead, duplicate, new track by type.
- A live scene preview above the timeline (resizable split) to watch mouths while listening.
- Export scene audio as WAV.

**Lip-sync**
- **Manual**: choose the character layer and part (default "Mouth"), step to a frame, and click a mouth shape or press **1–9**. It keys the drawing and steps forward one frame.
- **Assisted** ("Auto lip-sync selected clip"): measures the clip's loudness per frame and maps it to the character's mouth drawings: silence to rest, short dips to MBP (closed), quiet to E/L, medium to O/U, loud to AI. It alternates shapes for variety, holds each shape at least 2 frames and closes the mouth after the line. It only replaces that part's keys inside the clip's range, it's one undo step, and every frame stays editable by hand. It falls back to drawing order when the drawings use other names. It's optional: nothing depends on it.

**Integration**
- The Animate timeline shows the scene's audio tracks (waveforms) under the layers, for timing.
- **Render** now mixes the scene audio next to the frames, and the MP4 includes it (AAC 192 kbps).
- Picture and audio both run on the real-time clock, so they stay in sync during preview.

### Test plan additions
1. Audio → Import a dialogue WAV and a music OGG (or drag them onto the window). Waveforms appear after a moment.
2. Press Enter: picture and sound play together. Drag the music clip later, trim its start, add a 2 s fade-out, and solo/mute tracks.
3. Step with , and . and hear each frame. Double-click the ruler on a word to drop a marker.
4. With a character in the scene: Lip-sync → select the dialogue clip → Auto lip-sync → Enter. Fix a few frames with keys 1–9.
5. Animate: the waveform shows under the layers. Depth → Render with MP4 checked: the MP4 has sound in sync.
6. Save As to a new folder, then open the copy: audio still plays.

### Known limitations added this stage
- Assisted lip-sync is loudness-based (no phoneme recognition), so expect hand refinement for close-ups.
- Changing clip settings during playback rebuilds the players, which can cause a short audio hiccup.
- Clips can't be dragged from one track to another yet (delete and re-import, or duplicate on the target track).
- Per-track meters, EQ and effects aren't built yet (master meter only).
- Audio decoding for waveforms and the mix-down relies on Godot 4.4+ APIs. 4.7.2 has them.

## Milestone 3 — Character Studio and puppet animation

### Completed
**Character library (Phase 4)**
- New **Characters** workspace. Characters are project assets (`data/character_data.gd`) stored under `characters/<id>/<view>/<part>/`.
- **Body template**: one click creates Leg L/R, Arm L/R, Body, Head, Eyes (open/half/closed) and Mouth (rest, AI, E, O, U, MBP, FV, L), with joints and a parent hierarchy already laid out. A blank character is also available.
- Parts: add, delete, reorder (draw order), rename (children stay attached), "Attached to" (parent), and joint position by clicking with **Set joint** or typing coordinates. Bones are drawn between joints.
- **Front, side and back views**, each with its own parts. "Copy front here" starts a view from the front's parts and art.
- **Swappable drawings** per part (mouth shapes, eye states, hands...): add, delete and select them, then draw each one. Undrawn ones are dimmed.
- **Expressions**: save the current drawing of every swappable part under a name, preview it, delete it.
- **Rig test**: a live puppet preview with "wiggle every joint" to check pivots.
- Drawing uses the same engine and tools as everywhere else (selection, fill, undo...). Only the canvas source changed (`CanvasProvider` → `CharacterProvider`).
- Duplicate, rename and delete characters.

**Linked instances in scenes (non-destructive)**
- "Add to current scene" creates a character layer that references the character. Editing the artwork, joints or parts updates every instance in every scene.
- Instances behave like any layer in the 3D stage: depth, position, scale, opacity and motion keys. They render through the camera.
- `Rigs` autoload (`core/rig_manager.gd`) renders each instance as a puppet (`characters/character_rig.gd`: joints as Node2D, parts as Sprite2D) into its own transparent SubViewport, only when something changed.

**Puppet animation (Animate → Pose panel)**
- Joint rotation sliders for every part. Changes auto-key the current frame, keys interpolate with easing (smooth, linear, ease in, ease out, hold), and you can reset the pose.
- View switching (front/side/back) keyed per frame.
- Drawing swaps (lip-sync mouth shapes, blinks) keyed per frame and held until the next change, plus one-click expressions.
- **Actions**: save frames A–B of an instance's posing to its character (wave, nod, walk) and apply it to any instance, repeated N times.
- The timeline shows character rows as a violet band, with pose keys as violet diamonds and drawing/view switches as ticks.
- Character layers refuse drawing tools and drawing-timeline edits, with a message explaining where to edit them.

**Project format**
- Saving, the missing-file check and orphan cleanup now walk every drawing collection (scene layers, clips, character parts) through one shared helper.

### Test plan additions
1. Characters → **Body template** → select each part in Parts and draw it (Focus part helps). Draw a few mouth shapes and the closed eyes.
2. **Set joint** → click the shoulder for Arm L, and so on. Tick "Wiggle every joint" to check.
3. Pick Eyes "closed" → name it "Blink" → Save expression.
4. **Add to current scene** → Animate → select the character layer → Pose panel: move Arm L at frame 1, go to frame 12, move it again → Enter: the arm swings.
5. Change Mouth drawings on several frames. Click the Blink expression on a frame.
6. Save frames 1–12 as the action "Wave" → apply it ×2 on another instance or scene.
7. Back in Characters, recolor the head: every instance updates. Depth → move the character in depth → render: the character appears in the frames.

### Known limitations added this stage
- No inverse kinematics yet: poses are set by rotating joints (forward kinematics). IK for arms and legs is planned.
- No posing by dragging on the canvas yet (sliders only).
- Character renders are premultiplied. The 3D stage and renders handle that, but the 2D canvas may show slightly dark edges on soft, semi-transparent pixels of character parts.
- Each part drawing is stored at full canvas size: simple, but memory-heavy for big rigs. Cropping to the art's bounds is planned.
- Character thumbnails don't appear in scene cards.
- Character-specific color palettes and turnaround/model-sheet export aren't built yet.

## Milestone 2 — animation engine completion, selection, import

### Completed
**Layer animation (transform keyframes, Phase 3)**
- Each layer can be animated over time: horizontal/vertical position, depth, scale, rotation and opacity, with an easing per key (smooth, linear, ease in, ease out, hold). The interpolation code is shared with the camera (`core/key_track.gd`).
- Auto-key behavior: until a layer has keys, its values place it for the whole scene. Once it has keys, any change, including dragging it in the 3D view, keys the current frame.
- Depth workspace → "Layer animation": add/delete key, remove all keys (keeps the current placement), easing, and presets (fade in/out, slide in ←/→, grow in, float loop).
- Motion keys show as yellow diamonds along the bottom of each layer row in the timeline. Animated opacity is also previewed on the 2D canvas.

**Reusable animation clips / cycles (Phase 3–4)**
- Save frames A–B of a layer (drawings, timing and motion) as a clip in the project library (`data/clip_data.gd`, stored under `clips/<id>/`).
- Insert a clip at the playhead on any layer in any scene, repeated N times (walk cycles, blinks, talk loops). The drawing that was showing after the inserted range carries on afterwards.
- Rename and delete clips. Everything is undoable and saved incrementally like scene drawings.
- Timing builder: lay out N blank drawings on 1s/2s/3s/4s from the playhead, ready to draw with onion skin.

**Timeline markers**
- Press M, or double-click the ruler, to toggle a marker. Markers show as flags with labels on the ruler and as lines through the rows. The Markers panel lets you rename them, jump to them and delete them. They're saved per scene.

**Selection and transform (Phase 2)**
- Rectangle select (S, Shift for a square) and lasso (A).
- Drag inside a selection to lift and move it, and drag the corner handles to scale it (Shift keeps the aspect ratio). Enter applies, Esc cancels, Delete/Backspace clears.
- Ctrl+C / Ctrl+X / Ctrl+V copy, cut and paste. The clipboard is shared between workspaces and scenes, and pasting lands as a movable floating selection. Ctrl+A selects all, Ctrl+D deselects.
- A floating selection is applied automatically before undo, save, a frame/layer/scene change or a tool change, so it never conflicts with the history.

**Image import and reference layers (Phase 2)**
- Layers panel → import an image (PNG, JPG, WebP, SVG, BMP, TGA) as a new layer, scaled to fit and centered.
- Import as **reference**: a locked layer drawn faded on the canvas that never appears in the 3D stage, renders or thumbnails (good for model sheets, layouts and rotoscoping). Any layer can be switched to the "Reference" role.

### Test plan additions
1. Depth → select the character → "Slide in ←" → Enter: it slides in. Drag it at a later frame: a new key appears (yellow diamond).
2. Animate → Timing builder: 8 drawings on 2s → draw them → Save as clip "Walk" (use the ⤢ button for the layer's whole range) → go to another layer or scene → Insert ×3.
3. Press M on a few frames, rename the markers, and click a marker's frame number to jump.
4. Draw → S → drag a box → drag inside to move, drag a corner to scale → Enter. Lasso (A) → Ctrl+C → change frame → Ctrl+V → place → Enter. Ctrl+Z should undo each step cleanly.
5. Layers → import a photo as a reference → trace over it → Depth / render: the reference doesn't appear.

### Known limitations added this stage
- Selections can be moved and scaled but not rotated or flipped yet.
- Clips are copied when inserted: editing a clip later doesn't update copies already placed. Linked instances are planned with the Character Studio.
- Drawing tools don't respect the selection as a mask yet.
- Clip motion keys store absolute positions.
- Autosave can run while a selection is floating. The lifted pixels are saved once the selection is applied.

### Architecture

| Spec system | Implemented in |
|---|---|
| MainApplication / WorkspaceManager | `app/main.gd` |
| (global state + signals) | `core/app_state.gd` → autoload `App` |
| UndoRedoManager | `core/history.gd` → autoload `History` |
| Layer/Keyframe/Scene/Camera edit ops | `core/edit_ops.gd` → autoload `Ops` |
| ProjectManager / AssetManager (storage) | `core/project_io.gd` → autoload `ProjectIO` |
| Data models | `data/project_data.gd`, `scene_data.gd`, `layer_data.gd`, `cel_data.gd`, `clip_data.gd` |
| KeyframeManager (interpolation) | `core/key_track.gd` |
| SelectionManager | selection section of `ui/canvas/canvas_view.gd` + `BrushEngine.polygon_mask` |
| Clip library / markers UI | `ui/panels/clips_panel.gd` |
| CharacterCreator | `ui/workspaces/character_workspace.gd`, `ui/canvas/character_provider.gd`, `data/character_data.gd`, `data/part_data.gd` |
| CharacterRigManager | `characters/character_rig.gd`, `core/rig_manager.gd` (autoload `Rigs`) |
| Posing UI | `ui/panels/pose_panel.gd` |
| AudioManager / DialogueManager / LipSyncManager | `core/audio_engine.gd` (autoload `Audio`), `Ops.auto_lipsync`, `ui/workspaces/audio_workspace.gd` |
| Audio data | `data/audio_track_data.gd`, `data/audio_clip_data.gd` |
| Audio timeline | `ui/timeline/audio_timeline.gd` |
| EpisodeManager / StoryboardManager / VideoEditor | `data/episode_data.gd`, `ui/workspaces/episode_workspace.gd`, `ui/timeline/episode_strip.gd`, `Ops` episode section |
| Compositor / titles | `episode/episode_compositor.gd`, `episode/title_view.gd`, `episode/scene_feed.gd` |
| Full-episode RenderManager | `render/episode_renderer.gd` |
| DrawingEngine / BrushManager | `drawing/brush_engine.gd` |
| CanvasManager / OnionSkinManager | `ui/canvas/canvas_view.gd`, `shaders/onion.gdshader` |
| TimelineManager | `ui/timeline/timeline_view.gd`, `ui/panels/transport_bar.gd` |
| LayerManager (UI) | `ui/panels/layer_panel.gd` |
| Layer3DManager / CameraManager | `depth/depth_view.gd` |
| RenderManager / ExportManager | `render/render_exporter.gd` |
| SceneManager (UI) | `ui/workspaces/scene_workspace.gd` |

Rules followed: UI never edits data directly. Edits go through `Ops` (undoable) and are broadcast by `App` signals. Rendering (canvas, 3D view) only reads data.

### Not validated yet — please read
This stage was written without access to a Godot binary (the build environment had no network access to download one), so **it has not been launched or run through the Godot parser yet**. The code was reviewed by hand and cross-checked with a script (method references, icon names, theme variations, indentation, bracket balance), but expect a handful of small parse or runtime fixes on first launch. Next session, the first task is: open it in 4.7.2, fix any errors in the Output and Debugger panels, and run the test plan below.

### Test plan
1. Home → Create project (Full HD, 24 fps). You should land in Draw.
2. Draw a character on "Character" and a landscape on "Background". Test the brush, pencil, eraser, fill inside a closed shape, the picker, shapes with Shift, the move tool, undo/redo, and the zoom/pan/rotate view.
3. Animate → press N a few times and draw each frame. Check onion skin, Enter to play, dragging a key to retime it, and Insert/Remove frame.
4. Depth → Free view: the planes should be separated in space. Click "Far" with Background selected, then drag the character. Switch to Camera view and click "Parallax truck", then Enter: the background should move slower than the character.
5. Render scene… → choose a folder → PNG frames appear (and an MP4 if FFmpeg is installed).
6. Ctrl+S, close Strata, reopen the project from Recent: everything should be identical.
7. Scenes → add and duplicate a scene, rename it, change its length, switch between scenes.

### Known limitations / bugs
- Eraser and flood fill are implemented in GDScript: large erasers (>150 px) and fills on 4K canvases can feel slow. Plan: move them to a compute shader or GDExtension.
- Canvas and planes re-upload the whole drawing texture on each redraw while painting. Plan: partial updates.
- The free 3D view drags layers along world X/Y, not along the screen plane, when viewed at steep angles.
- Thumbnails are generated on the CPU. This is fine for a few dozen scenes.
- Undo is global across scenes, which can be surprising after switching scenes.
- Autosave writes into the project itself. There is no separate crash-recovery copy yet.

### Unfinished systems (by roadmap phase)
- **Phase 2**: selection rotate/flip, selection as a paint mask, text tool, masks and clipping, custom brush tips, canvas resize UI.
- **Phase 3**: graph-style curve editor, exposure-sheet (X-sheet) view, linked clip instances.
- **Phase 4**: IK, posing by dragging on the canvas, character palettes, model-sheet export, linked clip instances.
- **Phase 5**: multiple cameras per scene, camera switching, a camera-path display.
- **Phase 6**: Background/Environment workspace, prop and environment libraries, multiple shots per scene, scene transitions.
- **Phase 7**: blend modes, effects (blur, glow, color correction), particles, compositor.
- **Phase 8**: drag clips between tracks, per-track meters/effects, phoneme-based lip-sync.
- **Phase 9–10**: per-shot camera switching inside a scene, title templates library, episode templates, audio crossfades at transitions.
- **Phase 11**: render queue, WebM, GIF, sprite sheets, resolution/quality presets per render.
- **Phase 12**: tutorials, sample project, performance pass.

### Next development tasks (in order)
1. **First launch in Godot 4.7.2**: fix parse and runtime errors, then run all five test plans end to end. This is now the top priority: five milestones haven't been run yet.
2. Effects and compositing (Phase 7): blend modes, blur, glow, color correction, vignette, particle effects (rain, snow, dust, smoke).
3. Export options (Phase 11): WebM, GIF, sprite sheets, resolution/quality presets, render queue.
4. Beginner mode and sample project (Phase 12): guided onboarding, an example character and scenes, tutorials.
5. IK and drag-to-pose; selection rotation; brush tips.
