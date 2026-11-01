"""Independent re-computation of Pitchside's numbers from the raw attributes (no Swift code reused)."""
import json, sys, math
import numpy as np
from scipy.optimize import linear_sum_assignment
D = json.load(open("/tmp/audit.json"))
AK = {k: i for i, k in enumerate(D["attrKeys"])}; PK = {k: i for i, k in enumerate(D["posKeys"])}
KW, SW, OW = D["weights"]
roles = D["roles"]; RI = {r["code"]: i for i, r in enumerate(roles)}
sq = {p["id"]: p for p in D["squad"]}
fails = collections = []
def fail(*a): fails.append(" ".join(map(str, a)))
def r1(x): return math.floor(x * 10 + 0.5) / 10
# 1. Role scores from the attribute weights
def role_score(p, r):
    a = p["a"]; listed = set(r["key"] + r["support"])
    pool = D["pools"]["keeper"] if r["pos"] == ["GK"] else D["pools"]["outfield"]
    s = w = 0
    for k in r["key"]: s += KW * a[AK[k]]; w += KW
    for k in r["support"]: s += SW * a[AK[k]]; w += SW
    for k in pool:
        if k not in listed: s += OW * a[AK[k]]; w += OW
    return r1(s / w)
n = bad = 0
for p in D["squad"]:
    for i, r in enumerate(roles):
        n += 1
        if abs(role_score(p, r) - p["rs"][i]) > 0.051: bad += 1; fail("role score", p["name"], r["code"], role_score(p, r), p["rs"][i])
    nat = {k for k, i in PK.items() if i < len(p["pos"]) and p["pos"][i] >= 15}
    cand = [p["rs"][i] for i, r in enumerate(roles) if r["ip"] and nat & set(r["pos"])] or [p["rs"][i] for i, r in enumerate(roles) if r["ip"]]
    if abs(max(cand) - p["best"]) > 0.051: fail("best role score", p["name"], p["best"], max(cand))
print(f"role scores: {n - bad}/{n} match")
def fam(p, pos):
    i = PK.get(pos); return p["pos"][i] if i is not None and i < len(p["pos"]) else 0
def pen(f): return 0 if f >= 15 else 0.8 if f >= 12 else 2 if f >= 9 else None
def slot(p, ip, oop):
    a = p["rs"][RI[ip]] if ip in RI else None; b = p["rs"][RI[oop]] if oop in RI else None
    if a is not None and b is not None: return r1(0.6 * a + 0.4 * b)
    return a if a is not None else (b or 0)
def check_fit(name, picks, level, depth, oopc, value_fn, n_slots):
    ids = [x["player"] for x in picks if x["player"]]
    if len(ids) != len(set(ids)): fail(name, "player picked twice")
    tot = 0
    for s, x in enumerate(picks):
        if not x["player"]: continue
        p = sq[x["player"]]
        if fam(p, x["pos"]) != x["fam"]: fail(name, x["label"], "familiarity", fam(p, x["pos"]), x["fam"])
        if pen(x["fam"]) is None: fail(name, x["label"], p["name"], "can't play there", x["fam"])
        if abs(p["rs"][RI[x["role"]]] - x["ip"]) > 0.051: fail(name, x["label"], "IP score", x["ip"])
        if abs(p["rs"][RI[x["oop"]]] - x["oopS"]) > 0.051: fail(name, x["label"], "OOP score", x["oopS"])
        tot += x["score"]
    if abs(tot / n_slots - level) > 0.01: fail(name, "level", level, tot / n_slots)
    if sum(1 for x in picks if x["player"] and x["fam"] < 15) != oopc: fail(name, "out-of-position count")
    return tot
# 2. Squad report (My tactic, 4-3-3 default)
rep = D["report"]
for s in rep["slots"]:
    if s["starter"]:
        p = sq[s["starter"]]
        v = slot(p, s["role"], s["oop"])
        if abs(v - s["score"]) > 0.051 and abs(v - pen(fam(p, s["pos"]) or 0) - s["score"]) > 0.051:
            fail("report slot", s["label"], p["name"], s["score"], "expected", v)
# 3. Presets: rebuild the value matrix and solve the assignment independently
ids = list(sq)
worse = 0
for pr in D["presets"]:
    n_s = len(pr["slots"])
    M = np.full((n_s, len(ids)), -1000.0)
    for s, (ipp, ipr, oopp, oopr) in enumerate(pr["slots"]):
        for j, pid in enumerate(ids):
            p = sq[pid]; fi = fam(p, ipp); fo = fi if oopp == ipp else fam(p, oopp)
            pi = pen(fi)
            if pi is None: continue
            po = pi if oopp == ipp else (pen(fo) if pen(fo) is not None else 3)
            M[s, j] = slot(p, ipr, oopr) - (0.6 * pi + 0.4 * po)
    r, c = linear_sum_assignment(-M)
    opt = sum(M[i, j] for i, j in zip(r, c) if M[i, j] > -999)
    got = check_fit(pr["id"], pr["picks"], pr["level"], pr["depth"], pr["oop"], None, n_s)
    if got < opt - 0.05: worse += 1; fail(pr["id"], "XI not optimal", round(got, 2), "vs", round(opt, 2))
    for s, x in enumerate(pr["picks"]):
        if x["player"] and abs(M[s, ids.index(x["player"])] - x["score"]) > 0.051:
            fail(pr["id"], x["label"], "pick score", x["score"], "expected", round(M[s, ids.index(x["player"])], 2))
print(f"presets: {len(D['presets'])} checked, {worse} with a non-optimal XI")
# 4. Formations (best roles per player): check consistency, level, uniqueness
for f in D["formations"]:
    check_fit(f["name"], f["picks"], f["level"], f["depth"], f["oop"], None, len(f["picks"]))
    for x in f["picks"]:
        if not x["player"]: continue
        r = next(rr for rr in roles if rr["code"] == x["role"])
        if x["pos"] not in r["pos"]: fail(f["name"], x["label"], "IP role", x["role"], "not offered at", x["pos"])
        o = next(rr for rr in roles if rr["code"] == x["oop"])
        if x["pos"] not in o["pos"]: fail(f["name"], x["label"], "OOP role", x["oop"], "not offered at", x["pos"])
print(f"formations: {len(D['formations'])} checked")
# 5. Style fit, recomputed from the rules and attributes
GROUPS = {"Goalkeeper": {"GK"}, "Centre-backs": {"DC"}, "Full-backs": {"DL", "DR", "WBL", "WBR"},
          "Defenders": {"DC", "DL", "DR", "WBL", "WBR"}, "Midfielders": {"DM", "MC"},
          "Wide players": {"ML", "MR", "AML", "AMR", "WBL", "WBR"}, "Attackers": {"ML", "MR", "AML", "AMR", "AMC", "ST"},
          "Strikers": {"ST"}, "Central midfield & attack": {"DM", "MC", "AMC", "ST"}}
def relevant(pos):
    out = []
    for rule in D["styleRules"]:
        g = rule["group"]
        if (pos != "GK") if g == "Outfield" else (pos in GROUPS[g]):
            for k, _ in rule["attrs"]:
                if k not in out: out.append(k)
    return out
def baseline(p, pos):
    ks = relevant(pos)
    return sum(p["a"][AK[k]] for k in ks) / len(ks) if ks else 10
styles = {s["name"]: s for s in D["styles"]}
spread = {}
for pr in D["presets"]:
    xi = [(sq[x["player"]], x["pos"]) for x in pr["picks"] if x["player"]]
    seen, dem = set(), []
    for _, sec, setting, value in styles[pr["style"]]["instructions"]:
        phase = _
        for rule in D["styleRules"]:
            if rule["phase"] != phase or rule["setting"] != setting or not any(v in value for v in rule["values"]): continue
            key = setting + "|" + rule["group"]
            if key in seen: continue
            seen.add(key)
            ps = [(p, pos) for p, pos in xi if (pos != "GK" if rule["group"] == "Outfield" else pos in GROUPS[rule["group"]])]
            if not ps: continue
            tw = sum(w for _, w in rule["attrs"])
            sc = sum(sum(p["a"][AK[k]] * w for k, w in rule["attrs"]) / tw - baseline(p, pos) for p, pos in ps) / len(ps)
            dem.append((sc, rule["weight"] * (1.5 if value.startswith("Much") else 1)))
    s = sum(a * b for a, b in dem) / sum(b for _, b in dem) if dem else 0
    pr["_raw"] = s
    if abs(pr["combined"] - (pr["level"] + 0.5 * pr["styleScore"])) > 0.001: fail(pr["id"], "combined")
    spread.setdefault(pr["style"], []).append(pr["styleScore"])
mean = sum(p["_raw"] for p in D["presets"]) / len(D["presets"])
for pr in D["presets"]:
    if abs(pr["_raw"] - mean - pr["styleScore"]) > 0.01: fail(pr["id"], "style fit", round(pr["styleScore"], 3), "expected", round(pr["_raw"] - mean, 3))
print("style fit recomputed for", len(D["presets"]), "presets")
print("FAILS:", len(fails)); [print("  ", f) for f in fails[:25]]
