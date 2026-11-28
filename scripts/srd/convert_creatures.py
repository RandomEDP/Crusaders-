"""Turns the SRD 5.1 monster JSON from https://github.com/5e-bits/5e-database (src/2014/en/5e-SRD-Monsters.json)
into the creature list the app bundles.

Usage: python3 scripts/srd/convert_creatures.py <5e-database>/src/2014/en/5e-SRD-Monsters.json \
    CrusadersKit/Sources/CrusadersKit/Resources/srd-creatures.json
"""
import json, sys

src, out = sys.argv[1], sys.argv[2]
monsters = json.load(open(src))

TYPES = {"swarm of Tiny beasts": "swarm"}

def cr(value):
    return value  # 0.125, 0.25 and 0.5 stay as fractions of 1

def join(items):
    return ", ".join(items) if items else None

def armor_note(entry):
    t = entry["type"]
    if t == "natural":
        return "natural armor"
    if t == "armor":
        return ", ".join(a["name"].lower() for a in entry.get("armor", []))
    if t == "spell":
        return "with " + entry["spell"]["name"].lower()
    if t == "condition":
        return "while " + entry["condition"]["name"].lower()
    return None

def armor(m):
    entries = m["armor_class"]
    first = entries[0]
    note = armor_note(first)
    extra = [f"{e['value']} {armor_note(e)}" for e in entries[1:] if armor_note(e)]
    if extra:
        note = ", ".join(filter(None, [note] + [f"({x})" for x in extra])) if note else "(" + ", ".join(extra) + ")"
    return first["value"], note or None

def speed(s):
    parts = []
    for key in ["walk", "burrow", "climb", "fly", "swim"]:
        if key in s:
            value = s[key]
            if key == "walk":
                parts.append(value)
            else:
                parts.append(f"{key} {value}" + (" (hover)" if key == "fly" and s.get("hover") else ""))
    return ", ".join(parts)

def senses(s):
    parts = [f"{k} {v}" for k, v in s.items() if k != "passive_perception"]
    parts.append(f"passive Perception {s['passive_perception']}")
    return ", ".join(parts)

def signed(n):
    return f"+{n}" if n >= 0 else str(n)

def profs(m, prefix):
    out = []
    for p in m["proficiencies"]:
        name = p["proficiency"]["name"]
        if name.startswith(prefix):
            label = name.split(": ", 1)[1]
            if prefix == "Saving Throw":
                label = label.capitalize()
            out.append(f"{label} {signed(p['value'])}")
    return join(out)

def usage(u):
    if not u:
        return ""
    if u["type"] == "recharge on roll":
        low = u["min_value"]
        return f"Recharge {low}–6" if low < 6 else "Recharge 6"
    if u["type"] == "per day":
        return f"{u['times']}/Day"
    if u["type"] == "recharge after rest":
        rests = u.get("rest_types", [])
        return "Recharges after a " + " or ".join(f"{r} rest" for r in rests) if rests else ""
    return ""

def features(lst):
    result = []
    for f in lst or []:
        name = f["name"].strip()
        tag = usage(f.get("usage"))
        if tag and "(" not in name:
            name = f"{name} ({tag})"
        result.append({"name": name, "description": f["desc"].strip()})
    return result

creatures = []
for m in monsters:
    ac, note = armor(m)
    c = {
        "id": m["index"],
        "name": m["name"],
        "size": m["size"].lower(),
        "type": TYPES.get(m["type"], m["type"]),
        "alignment": m["alignment"],
        "armorClass": ac,
        "hitPoints": m["hit_points"],
        "hitDice": m["hit_points_roll"].replace("+", " + ").replace("-", " - "),
        "speed": speed(m["speed"]),
        "abilities": {k[:3]: m[k] for k in ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]},
        "senses": senses(m["senses"]),
        "languages": m.get("languages") or "—",
        "challengeRating": cr(m["challenge_rating"]),
        "traits": features(m.get("special_abilities")),
        "actions": features(m.get("actions")),
        "reactions": features(m.get("reactions")),
        "legendaryActions": features(m.get("legendary_actions")),
    }
    if m["type"] in TYPES:
        c["subtype"] = "Tiny beasts"
    elif m.get("subtype"):
        c["subtype"] = m["subtype"]
    if note:
        c["armorNote"] = note
    for key, value in [
        ("savingThrows", profs(m, "Saving Throw")),
        ("skills", profs(m, "Skill")),
        ("damageVulnerabilities", join(m["damage_vulnerabilities"])),
        ("damageResistances", join(m["damage_resistances"])),
        ("damageImmunities", join(m["damage_immunities"])),
        ("conditionImmunities", join([x["name"].lower() for x in m["condition_immunities"]])),
    ]:
        if value:
            c[key] = value
    if m.get("desc"):
        c["description"] = m["desc"] if isinstance(m["desc"], str) else "\n".join(m["desc"])
    creatures.append(c)

creatures.sort(key=lambda c: c["name"])
with open(out, "w") as f:
    json.dump({"creatures": creatures}, f, indent=1, ensure_ascii=False)
    f.write("\n")
print(len(creatures), "creatures")
