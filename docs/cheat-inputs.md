# Cheat input integration

The user-supplied `GTA5Port.ipa` (1.3.1, build 7) contains a native console/gamepad cheat feature. Its SHA-256 is `63dc6bb66f7a9a04598a8352c00fa39ba517d08a66220529a84d9d4625f31a05`. Its bundled manifest matches the build input manifest: `c5d7b041dbcde22e54f97dc271a52690ea6101391bfda3fb9ecd13d8ef748c1a`.

The integration uses the existing engine input block and virtual controller. No reference executable, additional game code, dynamic library, private Apple API or game script-native invocation is added. UIKit presents the interface; the native engine host sends the game's own input.

The pinned engine publishes input at `0x64748c`, aligned to four bytes. Version
1.3.4 corrects an eight-byte alignment check that rejected all requests before
input started. Tests now exercise the actual address and reject only genuinely
misaligned or out-of-bounds input. Rejections include the block address, game
state and pause state in the diagnostic log.

- **Console:** focus keyboard input, open the in-game console with virtual key 192 and the backtick character, send uppercase ASCII through the existing 64-entry UTF-16 ring, then press Return. Reference delays are preserved: 120/80/300 ms to open, 60/40 ms per character, then 100/80/400 ms to submit.
- **Gamepad:** neutral input for 100 ms, each button held for 90 ms and released for 60 ms, then 400 ms to finish. Triggers include their analog values.
- **Auto:** use one of the 29 supported reference gamepad mappings, otherwise console. The reference's `SNOW` entry duplicated its weather sequence; this app retains the real `SNOWDAY` code and uses console for it. The limousine mapping excludes a trailing zero padding entry.
- **Custom:** 1–32 ASCII letters A–Z, sent through the console. The code itself is never localized.

Input ownership is reserved before the worker is launched. During delivery, normal touch, controller, keyboard and mouse producers cannot overwrite the sequence. Scene deactivation requests cancellation, and the worker releases keys, mouse state and the virtual pad before relinquishing ownership. Invalid requests, unavailable player state, a pause menu, full/corrupt character ring and worker creation failures fail without claiming activation.

The UI says **input sent** when delivery completes. GTA V can refuse a cheat during missions or before a vehicle is unlocked; the game's own confirmation remains authoritative. See Rockstar's [cheat saving and achievement guidance](https://support.rockstargames.com/articles/4ewFY12QOE4O7V1uWDEekt/information-about-saving-and-achievements-while-using-gta-v-cheat-codes).

Native labels, descriptions, input choices and status/error messages use the English/Turkish `Cheats.xcstrings` catalog. This does not translate game dialogue or menus contained in the user's game data.

`app/Tests/cheat_input.c` exercises actual sequencing helpers, ring bounds/wrap, pad edges/triggers, concurrent ownership and cancellation cleanup. The simulator smoke test launches the real Swift app UI with engine substitutes; it does not claim on-device gameplay verification.
