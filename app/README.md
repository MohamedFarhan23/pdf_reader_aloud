# PDF Reader Aloud: the app

One Flutter codebase for **Android** and **desktop** (Linux, Windows, macOS).

## Run it on your Arch Linux laptop

```bash
# Toolchain (Flutter from the AUR, or download it from flutter.dev)
sudo pacman -S --needed git clang cmake ninja pkgconf gtk3
yay -S flutter-bin            # or: install Flutter manually and add flutter/bin to PATH

cd pdf_reader_aloud/app
flutter pub get
flutter run -d linux           # debug build with hot reload
# or a release build:
flutter build linux --release && ./build/linux/x64/release/bundle/pdf_reader_aloud ~/some.pdf
```

On first launch, tap **Download Kokoro** (about 132 MB, once). Then open a PDF and press play.

## Run it on your Pixel (USB debugging)

1. **Install the Android toolchain:**
   ```bash
   sudo pacman -S android-tools android-udev     # adb + USB permissions
   yay -S android-studio                         # includes the Android SDK
   ```
   Open Android Studio once and let it install the SDK. Then run
   `flutter doctor --android-licenses`, and check that `flutter doctor` shows Android as OK.
2. **On the phone**, open Settings → About phone and tap *Build number* 7 times.
   Then open Settings → System → Developer options and turn on **USB debugging**.
3. **Plug the phone in** and accept the "Allow USB debugging?" prompt.
   `adb devices` should list it. If it shows `no permissions`, add yourself to
   the `adbusers` group and log out and back in.
4. **Run the app:**
   ```bash
   cd pdf_reader_aloud/app
   flutter run --release        # release = full speed; debug builds are slower
   ```
5. In the app: tap **Download Kokoro**, then open **Voices** and tap **Test voice & speed**.
   * **≥ 1.3× real time**: Kokoro will read smoothly on this phone.
   * **1.0–1.3×**: it keeps up, with an occasional short pause.
   * **< 1.0×**: use a Piper voice (about 20× real time, so smooth on any phone).

   With `flutter run`, the console also prints one line per sentence, e.g.
   `tts: 4.6s audio in 3.1s (1.48x real time, 88 chars)`.

To produce an installable APK to sideload or share:
`flutter build apk --release --split-per-abi`. Copy
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` to the phone.

## Project layout

```
lib/
  main.dart                     app entry; desktop: `pdf_reader_aloud file.pdf` opens it
  src/core/                     platform-independent logic (unit-tested)
    interfaces.dart             DocumentText, TtsEngine, AudioOutput: the seams
    text_chunker.dart           PDF text cleanup, heading detection, sentence splitting
    read_aloud_controller.dart  play/pause/skip, synthesize-ahead pipeline, progress
  src/tts/
    voice_catalog.dart          Kokoro + Piper models, the 28 Kokoro English speakers
    sherpa_engine.dart          sherpa-onnx on a background isolate; speed test
    model_manager.dart          download + unpack voice models (once)
  src/audio/soloud_output.dart  low-latency playback (miniaudio)
  src/pdf/                      page text via pdfrx (PDFium)
  src/library/stores.dart       recent documents, reading position, settings
  src/ui/                       home/library, reader + player panel, voices screen
test/                           unit tests + real-model integration tests
```

### Extending it

* **New voice engine** (e.g. a cloud voice, or the platform's built-in TTS): implement
  `TtsEngine.synthesize()` and return mono float PCM.
* **New document type** (EPUB, web pages, plain text): implement `DocumentText`.
* **New desktop feature**: everything under `lib/src/ui` already works on desktop;
  `isMobile` in `app_state.dart` is the only platform switch.

## Tests

```bash
flutter test                       # unit tests (no models needed)

# Also run the real voice models (unpacked sherpa-onnx archives in one folder):
SHERPA_TEST_MODELS=/path/to/models \
LD_LIBRARY_PATH=$HOME/.pub-cache/hosted/pub.dev/sherpa_onnx_linux-1.13.8/linux/x64 \
flutter test
```

## Notes and known limitations

* `sherpa_onnx` is pinned to **1.13.8**, the last release that includes espeak-ng.
  Version 2.x removed it, so words missing from Kokoro's dictionary (names, jargon)
  would have no pronunciation fallback.
* Scanned PDFs (images without a text layer) are detected but not OCR'd yet.
* Android stops the app's audio if the system kills the app in the background.
  Reading with the screen off needs a foreground media service, which is planned.
* Headers, footers and multi-column layouts are read in the PDF's text order.
