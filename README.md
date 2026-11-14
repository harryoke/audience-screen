# Audience Screen

A native macOS slideshow player with a separate audience window for a projector, TV, or second display. macOS 13 Ventura or newer, Apple Silicon and Intel. No third-party runtime required.

## Download the compiled app

Open [Actions](https://github.com/harryoke/audience-screen/actions), select the latest successful **Build macOS app** run, and download **Audience-Screen-macOS-Universal** under Artifacts (GitHub sign-in required). Unzip the artifact, then unzip `Audience-Screen-macOS-Universal.zip` and drag **Audience Screen.app** into Applications.

This personal build is ad-hoc signed, not Apple Developer ID signed or notarized. On first launch macOS may require **System Settings → Privacy & Security → Open Anyway** after an attempted launch. An Apple Developer certificate is needed for a notarized distribution.

## Use

1. Choose a folder containing images and videos. Enable **Include subfolders** if needed. Use rescan after changing folder contents.
2. Select the audience display, then **Full screen**. Keep the control window on your main display. Use extended desktop, rather than mirroring, for separate controls.
3. Set default duration, shuffle, loop, and transition. Press **Play**.
4. Select any file and set a duration override. **0** restores the default. Overrides are remembered by absolute file path. Video defaults to its full length; a timed video loops or trims to fit its override. Timing changes take effect on the next file.

Transitions: cut, dissolve, slide, reveal, move in, or a random effect. Adjustable transition duration, aspect-fit or crop-to-fill, audio mute, pause/resume, previous/next, and blackout are included. Blackout hides the audience output and mutes audio while playback continues. Closing the audience window stops the show.

In the audience window: **Space** pauses/resumes, **← / →** navigate, **B** toggles blackout, **Esc** leaves fullscreen.

Images and movies use macOS decoders (including JPEG, PNG, HEIC and compatible MP4/MOV videos). Actual video support depends on its codec, not just its extension. Unreadable files are skipped; the show stops if every file fails. GIFs are displayed as still images. Audio uses the Mac's selected system output device.

## Build and validation

With Xcode or its command-line tools installed on macOS:

```sh
bash scripts/build-macos.sh
```

The build runs playlist tests, compiles both architectures, combines them into a universal executable, creates the icon and app bundle, signs it ad hoc, checks the signature and architectures, and launches a short window smoke test. The app ZIP and SHA-256 checksum are in `dist/`.

The automated launch test does not replace a real projector/audio test. Before a live event, verify the selected display, video codecs, audio route, and transitions with your actual media.
