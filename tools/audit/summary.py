import json
D = json.load(open("/tmp/audit.json")); sqn = {q["id"]: q["name"] for q in D["squad"]}
print("teams:", D["teams"], "| squad:", len(D["squad"]))
for f in D["formations"][:3]: print("shape", f["name"], "level %.2f depth %.2f oop %d" % (f["level"], f["depth"], f["oop"]))
ps = D["presets"]
for key, lab in (("rating", "roles"), ("styleScore", "style"), ("combined", "both")):
    top = sorted(ps, key=lambda p: -p[key])
    print("by %s: best %s %s %.2f | worst %s %s %.2f" % (lab, top[0]["style"], top[0]["name"], top[0][key], top[-1]["style"], top[-1]["name"], top[-1][key]))
lv = [p["level"] for p in ps]; st = [p["styleScore"] for p in ps]
print("roles level %.2f-%.2f, style fit %+.2f to %+.2f" % (min(lv), max(lv), min(st), max(st)))
by = {}
for p in ps: by.setdefault(p["style"], []).append(p["styleScore"])
print("style fit by style:", ", ".join("%s %+.1f" % (k, sum(v)/len(v)) for k, v in sorted(by.items(), key=lambda kv: -sum(kv[1]))))
b = sorted(ps, key=lambda p: -p["rating"])[0]
print("best preset XI:", "; ".join("%s %s %s/%s %.1f%s" % (x["label"], sqn[x["player"]].split()[-1], x["role"], x["oop"], x["score"], "!" if x["fam"] < 15 else "") for x in b["picks"] if x["player"]))
print("demands:", "; ".join("%s %+.1f" % (d["label"], d["score"]) for d in b["demands"][:6]))
print("set pieces:", {k: v[:2] for k, v in D["setPieces"].items()})
print("instructions:", D["instructions"]["mentality"], D["instructions"]["items"][:5])
