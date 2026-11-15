# Child Link Uses Hylian Shield

**Child Link has full mastery of the Hylian Shield!**
He holds it the same way he holds the Deku Shield. No more crouching under it.

- **Optional:** Like Likes Can't Eat Your Shield (Experimental, not tested on a Like Like yet).
- **Works with** Longshot, Hookshot and Switch emulators.
- **Compatible with other DenizenofWhite mods**, like Dark Link & Demise Glow. Install them in any order.
- **No game files included.** The installer builds the mod from your own copy of the game.

## Install

1. Unzip the download anywhere.
2. Double-click **Install.bat**.
3. If Python says **Missing**, click **Install Prerequisite**.
4. **Longshot / Hookshot:** pick your game folder. **Emulator:** pick your game's romfs folder and your emulator's load
   folder.
5. Optional: tick **Like Likes Can't Eat Your Shield**.
6. Click **Install / Change**, wait a few seconds, then start the game.

To change or remove it, run Install.bat again. Close the game first.

**Something went wrong?** Your game only changes when an install finishes. Click **Report a Problem**: it opens a bug
report on this mod's GitHub page with the details filled in (your user name and folders are hidden; you review it and
click submit yourself).

## Command line

    python install.py --longshot "C:\Games\Longshot"
    python install.py --hookshot "C:\Games\Hookshot"
    python install.py --romfs "D:\dump\romfs" --emulator-load "C:\path\to\emulator\load"

Add `--no-eat` for Like Likes Can't Eat Your Shield. Uninstall: `--uninstall`.

## Notes

- Needs Python 3.14 or newer (python.org; Hookshot's builder also ships one in its `tools\python` folder).
- Made for game build e0f3ccfa (program 0400486024DEC000), the build Longshot and Hookshot support. Tested on Hookshot.
- With Dark Link & Demise Glow installed, this mod is added into it, so both work together. If your copy of Dark Link
  & Demise Glow is too old for that, the installer tells you and links the update.
- Unofficial fan project. Use your own legally obtained copy of the game.

Made by DenizenofWhite. Built with AI assistance.
