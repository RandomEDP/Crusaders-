"""Turns the SRD 5.1 JSON from https://github.com/5e-bits/5e-database (src/2014/en)
into the compact Swift data files the app bundles.

Usage: python3 scripts/srd/convert.py <5e-database>/src/2014/en CrusadersKit/Sources/CrusadersKit/Characters/SRD
"""
import json, sys, os
src = sys.argv[1]; out = sys.argv[2]
def load(n): return json.load(open(os.path.join(src, f'5e-SRD-{n}.json')))
races, subraces, traits = load('Races'), load('Subraces'), load('Traits')
classes, subclasses, levels, features, spells = load('Classes'), load('Subclasses'), load('Levels'), load('Features'), load('Spells')
trait_by = {t['index']: t for t in traits}
feat_by = {f['index']: f for f in features}
children = {}
for f in features:
    if 'parent' in f: children.setdefault(f['parent']['index'], []).append(f['name'])

def text(d):
    if isinstance(d, list): return "\n".join(d)
    return d or ""
def trait(ref):
    t = trait_by[ref['index']]
    return {"name": t['name'], "description": text(t.get('desc'))}
def feature(ref):
    f = feat_by[ref['index']]
    d = text(f.get('desc'))
    if f['index'] in children:
        d += "\nOptions: " + ", ".join(children[f['index']])
    return {"name": f['name'], "description": d}
def bonuses(lst): return {b['ability_score']['index']: b['bonus'] for b in lst}

R = []
for r in races:
    sub = [s for s in subraces if s['race']['index'] == r['index']]
    item = {
        "id": r['index'], "name": r['name'], "speed": r['speed'], "size": r['size'],
        "abilityBonuses": bonuses(r['ability_bonuses']),
        "languages": r.get('language_desc', ''),
        "age": r.get('age', ''), "alignment": r.get('alignment', ''),
        "traits": [trait(t) for t in r['traits']],
        "subraces": [{"id": s['index'], "name": s['name'], "description": s.get('desc', ''),
                       "abilityBonuses": bonuses(s['ability_bonuses']),
                       "traits": [trait(t) for t in s['racial_traits']]} for s in sub],
    }
    opt = r.get('ability_bonus_options')
    if opt:
        item["abilityBonusChoice"] = {"count": opt['choose'], "bonus": opt['from']['options'][0]['bonus'],
            "from": [o['ability_score']['index'] for o in opt['from']['options']]}
    R.append(item)

def human(k):
    return k.replace('_', ' ').capitalize()
def counters(cs):
    out = {}
    for k, v in (cs or {}).items():
        if isinstance(v, dict) and 'dice_count' in v: v = f"{v['dice_count']}d{v['dice_value']}"
        elif isinstance(v, bool): v = "Yes" if v else "No"
        elif isinstance(v, list): continue
        elif isinstance(v, dict): continue
        out[human(k)] = str(v)
    return out

C = []
for c in classes:
    cl = sorted([l for l in levels if l.get('class', {}).get('index') == c['index'] and 'subclass' not in l], key=lambda l: l['level'])
    assert len(cl) == 20, c['index']
    lv = []
    for l in cl:
        sc = l.get('spellcasting') or {}
        e = {"level": l['level'], "proficiencyBonus": l['prof_bonus'],
             "abilityScoreImprovement": any('ability-score-improvement' in f['index'] for f in l['features']),
             "features": [feature(f) for f in l['features'] if 'ability-score-improvement' not in f['index']],
             "counters": counters(l.get('class_specific'))}
        if sc:
            e["spellSlots"] = [sc.get(f'spell_slots_level_{i}', 0) for i in range(1, 10)]
            if 'cantrips_known' in sc: e["cantripsKnown"] = sc['cantrips_known']
            if 'spells_known' in sc: e["spellsKnown"] = sc['spells_known']
        lv.append(e)
    choice = c['proficiency_choices'][0]
    skills = [o['item']['index'].removeprefix('skill-') for o in choice['from']['options'] if o.get('item', {}).get('index', '').startswith('skill-')]
    s = [x for x in subclasses if x['class']['index'] == c['index']][0]
    sl = sorted([l for l in levels if l.get('subclass', {}).get('index') == s['index']], key=lambda l: l['level'])
    sub = {"id": s['index'], "name": s['name'], "flavor": s['subclass_flavor'], "description": text(s['desc']),
           "features": {str(l['level']): [feature(f) for f in l['features']] for l in sl if l['features']},
           "bonusSpells": {}}
    for sp in s.get('spells', []):
        lvl = [p for p in sp['prerequisites'] if p['type'] == 'level']
        at = int(lvl[0]['index'].split('-')[-1]) if lvl else 1
        sub["bonusSpells"].setdefault(str(at), []).append(sp['spell']['index'])
    first_sub_level = min(int(k) for k in sub["features"]) if sub["features"] else 3
    prof = [p['name'] for p in c['proficiencies'] if not p['index'].startswith('saving-throw')]
    item = {"id": c['index'], "name": c['name'], "hitDie": c['hit_die'],
            "savingThrows": [x['index'] for x in c['saving_throws']],
            "proficiencies": prof,
            "skillChoices": {"count": choice['choose'], "from": skills},
            "subclassLevel": first_sub_level, "subclass": sub, "levels": lv}
    if 'spellcasting' in c:
        item["spellcastingAbility"] = c['spellcasting']['spellcasting_ability']['index']
    C.append(item)

S = []
for s in spells:
    S.append({"id": s['index'], "name": s['name'], "level": s['level'], "school": s['school']['name'],
              "castingTime": s['casting_time'], "range": s['range'], "components": s['components'],
              "material": s.get('material'), "duration": s['duration'], "concentration": s['concentration'],
              "ritual": s['ritual'], "description": text(s['desc']),
              "higherLevel": text(s.get('higher_level')) or None,
              "classes": [x['index'] for x in s['classes']]})
for name, data in [('Races', R), ('Classes', C), ('Spells', S)]:
    data_s = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
    assert '"#' not in data_s and '\\#' not in data_s
    swift = (
        "// Generated by scripts/srd/convert.py from the 5e-bits/5e-database copy of the SRD 5.1.\n"
        "// SRD 5.1 content is (c) Wizards of the Coast LLC, licensed under CC BY 4.0. Do not edit by hand.\n\n"
        "extension SRDData {\n"
        f"    static let {name.lower()}JSON = #\"{data_s}\"#\n"
        "}\n")
    open(os.path.join(out, f'SRD{name}.swift'), 'w').write(swift)
    print(name, len(data), len(data_s))
