# Uni Frame framework reference

The app references https://github.com/SHKinsem/Uni-App-Frame as a pinned Git
submodule at vendor/uni-frame. The app owns business code, permissions, signing
and its standalone version. Common Android adapters and build conventions come
from the framework; do not copy them back into this repository.

After cloning: `git submodule update --init --recursive`.
Check the reference: `python3 tools/uni-frame.py check`.
Release: `python3 tools/uni-frame.py release --sequence N --output /work/releases/app-N --key /secure/publisher.pem`.

Build only in the cloud using Flutter 3.41.6 and the pinned toolchain. Set
UNI_FRAME_RUNTIME_DIR to the publisher's external runtime resources; keep
private keys and Drive OAuth tokens outside source. The module sequence is
independent of the version in pubspec.yaml. Existing device validation gates
still apply; builds do not prove BLE/Garmin behavior.

To upgrade, fetch and check out an explicit framework commit within the
submodule, run app tests plus both build flavors, then commit its updated
pointer in this app repository. Framework changes do not auto-upgrade the app.
