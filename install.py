"""Child Link Uses Hylian Shield: builds the mod from YOUR OWN copy of The Legend of Zelda: Ocarina of Time (Switch 2)
and installs it. No game files ship with this patcher; everything is made from your files on your PC.

  Longshot:  python install.py --longshot "C:/Games/Longshot"           (uses <folder>/romfs, installs to <folder>/mods)
  Hookshot:  python install.py --hookshot "C:/Games/Hookshot"           (same layout)
  Emulator:  python install.py --romfs "D:/dump/romfs" --emulator-load "C:/Users/me/AppData/Roaming/<emulator>/load"
  Folder:    python install.py --romfs "D:/dump/romfs" --out "D:/mods-out"
Options:   --no-eat   Like Likes can't eat your shield (experimental)
If Dark Link & Demise Glow is installed in the same game, this mod is added into it (it keeps the shield when you change
its look); otherwise it gets its own mod folder. Uninstall: --uninstall.
Needs Python 3.14+ (Hookshot's builder ships one)."""
import argparse, hashlib, json, os, shutil, sys

if sys.version_info < (3, 14):
    sys.exit("Python 3.14 or newer is needed (it has compression.zstd). Hookshot users: use the Python inside "
             "HookshotBuilder's tools/python folder.")
HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "patcher")
sys.path.insert(0, LIB)
import addons  # noqa: E402
import shieldmod  # noqa: E402

MOD_NAME = shieldmod.ADDON
VERSION = "1.0.0"
TITLE_ID = "0400486024DEC000"
DARK_LINK = "DarkLink-DemiseGlow"
DARK_LINK_PAGE = "https://gamebanana.com/mods/740922"


def check_game(romfs):
    """Every game file the patcher reads must match the version it was made for."""
    want = json.load(open(os.path.join(LIB, "game_files.json")))
    bad = []
    for rel, sha in want["sha256"].items():
        p = os.path.join(romfs, *rel.split("/"))
        if not os.path.exists(p):
            bad.append(f"missing {rel}")
        elif hashlib.sha256(open(p, "rb").read()).hexdigest() != sha:
            bad.append(f"different {rel}")
    if bad:
        sys.exit(f"This game version doesn't match the one the patcher was made for ({want['version']}):\n  "
                 + "\n  ".join(bad[:10]))


def version_tuple(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return (0,)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hookshot", help="Hookshot folder (has romfs and mods)")
    ap.add_argument("--longshot", help="Longshot folder (Hookshot's successor: same romfs and mods layout)")
    ap.add_argument("--romfs", help="romfs folder of your own game dump")
    ap.add_argument("--emulator-load", help="the emulator's 'load' folder (mods go to load/<title id>/<mod>)")
    ap.add_argument("--out", help="write the mod folder here instead")
    ap.add_argument("--no-eat", action="store_true", help="Like Likes can't eat your shield (experimental)")
    ap.add_argument("--uninstall", action="store_true", help="remove the mod (back to stock)")
    a = ap.parse_args()
    a.hookshot = a.hookshot or a.longshot
    if a.hookshot:
        romfs = a.romfs or os.path.join(a.hookshot, "romfs")
        dest = os.path.join(a.hookshot, "mods", MOD_NAME)
    elif a.romfs and (a.emulator_load or a.out):
        romfs = a.romfs
        dest = os.path.join(a.emulator_load, TITLE_ID, MOD_NAME) if a.emulator_load else os.path.join(a.out, MOD_NAME)
    else:
        ap.error("give --longshot or --hookshot, or --romfs with --emulator-load or --out")
    assert os.path.basename(dest) == MOD_NAME     # this tool only ever writes or deletes its own folder ...
    host = os.path.join(os.path.dirname(dest), DARK_LINK)  # ... and its own note + patches inside Dark Link's folder
    host_note = os.path.join(host, addons.HOST_NOTES, MOD_NAME + ".json")
    merged = os.path.isfile(host_note)
    check_game(romfs)
    if a.uninstall:
        done = False
        if merged:
            addons.apply(host, romfs, json.load(open(host_note))["patches"], reverse=True)
            os.remove(host_note)
            print(f"Uninstalled: taken back out of Dark Link & Demise Glow ({host}).")
            done = True
        if os.path.isdir(dest):
            shutil.rmtree(dest)
            print(f"Uninstalled: removed {dest}.")
            done = True
        print("The game is back to stock for this mod." if done else "Not installed. Nothing to remove.")
        return
    note = shieldmod.note(romfs, VERSION, a.no_eat)
    if os.path.isdir(host):
        info = os.path.join(host, "install.json")
        dl_version = json.load(open(info)).get("version", "0") if os.path.exists(info) else "0"
        if version_tuple(dl_version) < (1, 1, 0):
            sys.exit(f"Dark Link & Demise Glow v{dl_version} is installed in this game. To use both mods together, update "
                     f"it to v1.1 or newer first ({DARK_LINK_PAGE}), then run this installer again.")
        if merged:      # changing options: take the old patches back out first
            addons.apply(host, romfs, json.load(open(host_note))["patches"], reverse=True)
        addons.apply(host, romfs, note["patches"])
        os.makedirs(os.path.dirname(host_note), exist_ok=True)
        json.dump(note, open(host_note, "w"), indent=1)
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        print(f"Dark Link & Demise Glow is installed here, so {shieldmod.TITLE} was added into it ({host}).\n"
              "It stays when you change Dark Link's look.")
    else:
        # Build next to the target under a disabled name (a leading "-" makes Longshot/Hookshot skip it), then swap.
        tmp = os.path.join(os.path.dirname(dest), "-" + MOD_NAME + "-building")
        shutil.rmtree(tmp, ignore_errors=True)
        addons.apply(tmp, romfs, note["patches"])
        json.dump(note, open(os.path.join(tmp, addons.NOTE), "w"), indent=1)
        open(os.path.join(tmp, "README.txt"), "w").write(
            f"{MOD_NAME} {VERSION}: child Link holds the Hylian Shield normally"
            + (", Like Likes can't eat your shield (experimental)" if a.no_eat else "")
            + ". Made by install.py from your own game files. Run the installer again to change or uninstall.\n")
        json.dump({"mod": MOD_NAME, "version": VERSION, "no_eat": a.no_eat}, open(os.path.join(tmp, "install.json"), "w"))
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        os.rename(tmp, dest)
        print(f"Installed: {dest}")
    print("Start the game. Run the installer again to change or uninstall.")


if __name__ == "__main__":
    main()
