---
name: DropdownButtonFormField deprecation
description: Replace value with initialValue in Flutter 3.33+ to avoid deprecation warnings.
---

Starting around Flutter 3.33, `FormField.value` is deprecated. `DropdownButtonFormField` is a `FormField`, so passing `value:` to it triggers the deprecation warning.

**How to apply:** Replace `value: someValue` with `initialValue: someValue` in `DropdownButtonFormField` constructors. The form field's internal state will still update correctly when `onChanged` fires, so the displayed selection remains in sync.
