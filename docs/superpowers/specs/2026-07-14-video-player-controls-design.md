# Video Player Controls Design

## Goal

Make video seeking reliable for videos of any duration, replace the persistent brightness and volume sliders with full-screen vertical gestures, and keep the existing zoom and playback controls usable.

## Interaction Model

- Dragging the playback progress bar previews the target time, pauses playback during the drag, seeks when released, and resumes only if the video was playing before the drag began.
- A vertical drag that begins in the left half of the video changes screen brightness. Dragging upward increases brightness and dragging downward decreases it.
- A vertical drag that begins in the right half of the video changes player volume. Dragging upward increases volume and dragging downward decreases it.
- Brightness remains clamped to `0.05...1`; volume remains clamped to `0...1`.
- Gesture classification uses the drag's starting position and requires vertical movement to dominate horizontal movement. This prevents horizontal motion, taps, and small movements from changing brightness or volume.
- When the video is zoomed above `1x`, dragging continues to pan the zoomed video instead of changing brightness or volume.
- During a brightness or volume adjustment, a temporary centered indicator displays the relevant icon and percentage. It disappears shortly after the gesture ends.

## Controls Layout

The bottom controls keep play or pause, replay, backward 10 seconds, forward 10 seconds, mute, elapsed time, duration, and the seekable playback progress bar. The separate volume and brightness slider rows are removed entirely. Removing those rows also removes their divider-like tracks and makes the controls panel shorter.

The playback progress bar remains inside the controls overlay and owns its drag gesture. Full-screen brightness and volume gestures attach to the player surface behind that overlay, so progress dragging is not intercepted by the player surface.

## Implementation Boundaries

- `ZoomableVideoPreview` owns playback state, scrubbing behavior, zoom state, full-screen adjustment gesture state, and the temporary adjustment indicator.
- A small pure gesture policy classifies a drag as brightness, volume, or no adjustment based on container width, start location, translation, and zoom scale. Its value calculation converts vertical translation into a clamped value.
- `VideoPlayerControlsOverlay` renders playback and seeking controls only. It no longer owns brightness or volume bindings or slider callbacks.
- Existing `AVPlayerLayer` playback and buffered `AVPlayerItem` setup remain unchanged.

## Conflict Handling

- The progress bar receives touches before the underlying player surface, so scrubbing remains independent of screen adjustment gestures.
- Pinch zoom remains simultaneous with the video surface. Once zoomed, drag input pans the video.
- Single tap continues to show or hide controls, and double tap continues to toggle zoom.
- Adjustment gestures update controls continuously but do not force the bottom controls to remain visible; the temporary indicator supplies feedback without covering the seek bar.

## Testing

- Unit tests cover left-half brightness classification, right-half volume classification, horizontal-drag rejection, small-movement rejection, zoomed-state rejection, upward increase, downward decrease, and value clamping.
- Source-structure tests confirm that the playback progress slider remains present and the separate volume and brightness control sliders are removed.
- The focused unit test target runs before and after implementation to demonstrate the regression test changing from red to green.
- A simulator build using a dedicated DerivedData path verifies the app and extensions still compile without colliding with Xcode's active build database.

## Out of Scope

- Changing video buffering, audio-session policy, zoom limits, or the surrounding full-screen media pager.
- Using system-wide volume APIs or displaying the native system volume HUD. The gesture changes the current `AVPlayer` volume, matching the existing player-specific volume control.
