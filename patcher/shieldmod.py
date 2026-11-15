"""Child Link Uses Hylian Shield, as an add-on patch list (see addons.py).

Child Link crouches under shields tagged ForAdult; the Hylian Shield carries that tag (the Deku Shield doesn't). Like Likes
eat shields tagged CanEat (Deku and Hylian). Each edit swaps one tag in the shield's ShieldParam SubType list for a
second Blunt tag (same size), in every pack that holds that shield's ShieldParam. The Like Like option also renames the
tag in the item table (one letter, same size). Nothing else changes."""
import os, struct
import addons

ADDON = "Child-Link-Uses-Hylian-Shield"
TITLE = "Child Link Uses Hylian Shield"
HYLIAN_PARAM = "Component/ShieldParam/Weapon_Shield_Hylian.game__component__ShieldParam.bgyml"
DEKU_PARAM = "Component/ShieldParam/Weapon_Shield_Deku.game__component__ShieldParam.bgyml"
HYLIAN_PACKS = ["Weapon_Shield_Hylian.pack.zs", "Weapon_Shield_DarkLinkShield.pack.zs"]
DEKU_PACK = "Weapon_Shield_Deku.pack.zs"
POUCH = "RSDB/PouchActorInfo.Product.111.rstbl.byml.zs"
POUCH_TAGS = {"Weapon_Shield_Deku": "Blunt,DekuShield,CanEat", "Weapon_Shield_Hylian": "Blunt,ForAdult,HyliaShield,CanEat"}
FOR_ADULT, CAN_EAT, BLUNT = 1646495920, 4203889317, 3473086895


def subtype_slots(b):
    """(offset, tag hash) of every entry in a ShieldParam's SubType list (BYML: root dict -> 'SubType' u32 array)."""
    assert b[:2] == b"YB"
    _, ktab, _, root = struct.unpack_from("<HIII", b, 2)
    n = int.from_bytes(b[ktab + 1:ktab + 4], "little")
    offs = struct.unpack_from(f"<{n}I", b, ktab + 4)
    keys = [b[ktab + o:b.index(b"\0", ktab + o)].decode() for o in offs]
    assert b[root] == 0xC1
    for i in range(int.from_bytes(b[root + 1:root + 4], "little")):
        e = root + 4 + i * 8
        if keys[int.from_bytes(b[e:e + 3], "little")] == "SubType":
            assert b[e + 3] == 0xC0
            arr = struct.unpack_from("<I", b, e + 4)[0]
            cnt = int.from_bytes(b[arr + 1:arr + 4], "little")
            vo = arr + 4 + ((cnt + 3) & ~3)
            return [(vo + j * 4, struct.unpack_from("<I", b, vo + j * 4)[0]) for j in range(cnt) if b[arr + 4 + j] == 0xD3]
    raise ValueError("no SubType list")


def patches(romfs, no_eat=False):
    """The add-on's patch list, worked out from the stock game files."""
    dicts = addons.zs_dicts(romfs)
    out = []

    def tag_patches(pack, param, drop):
        raw, _ = addons.unpack(open(os.path.join(romfs, "Pack", "Actor", pack), "rb").read(), dicts)
        s, t = addons.sarc_entries(raw)[param]
        found = []
        for off, tag in subtype_slots(raw[s:t]):
            if tag in drop:
                out.append({"file": "Pack/Actor/" + pack, "inner": param, "offset": off,
                            "old": struct.pack("<I", tag).hex(), "new": struct.pack("<I", BLUNT).hex()})
                found.append(tag)
        assert sorted(found) == sorted(drop), (pack, found)

    hylian = [FOR_ADULT] + ([CAN_EAT] if no_eat else [])
    for pack in HYLIAN_PACKS:
        tag_patches(pack, HYLIAN_PARAM, hylian)
    if no_eat:
        tag_patches(DEKU_PACK, DEKU_PARAM, [CAN_EAT])
        raw, _ = addons.unpack(open(os.path.join(romfs, *POUCH.split("/")), "rb").read(), dicts)
        for tags in POUCH_TAGS.values():
            at = raw.find(tags.encode() + b"\0")
            assert at >= 0 and raw.count(tags.encode() + b"\0") == 1
            out.append({"file": POUCH, "inner": None, "offset": at + tags.index("CanEat") + 5, "old": "74", "new": "54"})
    return out


def note(romfs, version, no_eat=False):
    return {"addon": ADDON, "title": TITLE, "version": version, "options": {"no_eat": no_eat},
            "patches": patches(romfs, no_eat)}
