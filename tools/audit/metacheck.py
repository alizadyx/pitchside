import json, re, sys, bisect, statistics as st
src = open("/home/claude/pitchside-repo/app/Sources/PitchsideCore/Meta.swift").read()
def wts(name):
    block = src.split(f"static let {name}: [String: Double] = [")[1].split("]")[0]
    return {k: float(v) for k, v in re.findall(r'"(\w+)": ([\d.]+)', block)}
OF, GKW = wts("outfield"), wts("goalkeeper")
def r1(x): return round(x + 1e-9, 1)
def compute(people, meta):
    AK = {k: i for i, k in enumerate(meta["playerAttrKeys"])}; pi = meta["personalityKeys"].index("Pressure")
    out = {}
    for p in people:
        a = p.get("a") or []; fam = p.get("pos") or []
        gk = bool(fam) and fam[0] >= 15 and max(fam) == fam[0]
        w = GKW if gk else OF
        tw = sum(v for k, v in w.items() if AK.get(k, 99) < len(a))
        m = sum(a[AK[k]] * v for k, v in w.items() if AK.get(k, 99) < len(a)) / tw if tw else 0
        pp = p.get("p") or []
        if pi < len(pp) and 0 < pp[pi] < 8: m -= 0.25 * (8 - pp[pi])
        out[p["id"]] = [r1(max(0, m)), gk]
    g = [v[0] for v in out.values() if v[1] and v[0] > 0]; o = [v[0] for v in out.values() if not v[1] and v[0] > 0]
    if len(g) >= 30 and len(o) >= 30:
        mg, sg, mo, so = st.mean(g), st.pstdev(g), st.mean(o), st.pstdev(o)
        for v in out.values():
            if v[1] and v[0] > 0: v[0] = r1(max(0, mo + (v[0] - mg) * so / sg))
    srt = sorted(v[0] for v in out.values())
    for v in out.values(): v.append(round(100 * bisect.bisect_left(srt, v[0]) / (len(srt) - 1)))
    return out
if __name__ == "__main__":
    d = json.load(open(sys.argv[1])); A = json.load(open(sys.argv[2]))
    res = compute(d["players"], d["meta"])
    bad = [(p["name"], p["meta"], res[p["id"]]) for p in A["squad"] if abs(p["meta"] - res[p["id"]][0]) > 0.051 or abs(p.get("metaRating", -1) - res[p["id"]][2]) > 1]
    print("checked", len(A["squad"]), "mismatches", len(bad), bad[:5])
