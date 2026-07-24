## 0.2.0

* Add CameraX and AVFoundation live preview through Flutter Texture.
* Analyze accepted frames with the shared OpenCV/C++ detector and latest-only backpressure.
* Add Flutter overlay, native stability, automatic capture, diagnostics, flash, and lens switching.
* Add the complete document-library app with multipage storage, PDF, sharing, settings, and recovery.
* Add native iOS static detection, perspective crop, and OpenCV image filters on both platforms.
* Add native OCR with offline ML Kit on Android and Vision on iOS, with searchable persisted text.
* Add folders, favorites, trash/restore, encrypted backup/merge, and WebDAV synchronization.
* Migrate 38 Document Scanner locale catalogs to Flutter.
* Restore the legacy iOS auto-scan stability rule and its delayed progress behavior.
* Smooth live preview corners and reject isolated contour jumps before auto-capture.
* Crop automatic captures immediately while keeping manual captures in the corner editor.
* Avoid rebuilding the entire app for non-locale settings changes.
* Refresh page previews after native filters and open tapped pages in a zoomable full-screen view.
* Remove the direct local backup and restore actions from the settings interface.
* Remove WebDAV settings and automatic startup synchronization from the app.
* Remove folder creation, navigation, editing, and document-folder assignment from the app.
* Keep the rename form controller alive until its dialog finishes closing.
* Remove PIN, biometric authentication, app locking, native permissions, and related dependencies.
* Correct the Android CameraX SurfaceTexture geometry without double rotation or mirroring.
* Match Android auto-scan movement filtering and overlay smoothing to the iOS stability tracker.
* Render trashed documents with a read-only list so restoring them does not violate Flutter's reorder callback contract.
* Restore the legacy live-preview minimum document area of 4% on Android and iOS.
* Remove CardWallet and the NativeScript/Svelte/Webpack build pipeline.

## 0.1.0

* Add the Android static-image scanner pipeline.
* Preserve and encapsulate the legacy OpenCV C++ document detector.
* Add normalized corner models, lifecycle-safe controller, overlay, and crop editor.
* Add perspective crop, EXIF orientation, image picker, typed errors, and native status.
* Add example, Dart/widget/JVM tests, integration fixture, and migration documentation.
* Keep live camera and native iOS processing explicitly out of this phase.
