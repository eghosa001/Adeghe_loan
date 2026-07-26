---
name: Web preview limits
description: sqflite_sqlcipher does not work in the web preview; database-backed features will fail there.
---

The web preview is useful for UI verification, but `sqflite_sqlcipher` has no web implementation. Encrypted database operations, including customer/loan/payment creation, will fail when running in the browser preview.

**How to apply:** Use the web preview only for layout and navigation checks. For end-to-end data-flow testing, build and run the APK on an Android device or emulator. Local VS Code builds are required for APKs because Replit does not have the Android SDK/toolchain available.
