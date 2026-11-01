import json, re, sys, difflib
sys.path.insert(0, "/home/claude/pitchside-repo/tools")
import importlib.util
spec = importlib.util.spec_from_file_location("g", "/home/claude/pitchside-repo/tools/presets_to_swift.py")
src = open(spec.origin).read().split("def rows")[0]
g = {}; exec(src, g)
IPV, OOPV = set(g["IP"]), set(g["OOP"]) | {"LHK"}
POSRE = re.compile(r"^(GK|D ?\((R|C|L)\)|WB ?\((R|L)\)|DM|M ?\((R|C|L)\)|AM ?\((R|C|L)\)|ST ?\(.\))\s+(.*)$")
def pos(s):
    s = s.replace(" ", "")
    if s.startswith("ST"): return "ST (C)"
    return re.sub(r"\((.)\)", r" (\1)", s)
def roles_from(rest):
    out = []
    for t in rest.split():
        u = "TW" if "™" in t else re.sub(r"[^A-Z]", "", t)
        if u in IPV | OOPV: out.append(u)
    return out
def table(txt):
    rows = []
    txt = re.sub(r"\(+", "(", txt.replace("{", "("))
    txt = txt.replace("}", ")").replace("©", "C").replace("(c)", "(C)").replace("(r)", "(R)").replace("(l)", "(L)")
    for line in txt.splitlines():
        m = POSRE.match(line.strip())
        if m: rows.append((pos(m.group(1)), roles_from(m.group(6)), line.strip()))
    return rows
SETTINGS = ["Passing Directness","Tempo","Attacking Width","Attacking Transition","Creative Freedom","Time Wasting",
 "Play for Set Pieces","Patience","Shots from Distance","Crossing Style","Dribbling","Supporting Runs","Progress Through",
 "Pass Reception","Build-Up Strategy","Goal Kicks","GK Distribution (Speed)","GK Distribution","Line of Engagement",
 "Defensive Line","Defensive Line Behaviour","Trigger Press","Defensive Transition","Tackling",
 "Short Goalkeeper Distribution","Pressing Trap","Cross Engagement"]
SECTIONS = {"Overview","Final Third","Progression","Buildup","High Press","Mid Block","Low Block"}
def instr(txt, phase):
    sec, out = None, []
    for line in txt.splitlines():
        l = line.strip().strip("|“\"'.,").strip()
        if not l: continue
        h = re.sub(r"\s+(Select|Selected).*$", "", l)
        if h in SECTIONS: sec = h; continue
        if sec is None: continue
        best = None
        for s in sorted(SETTINGS, key=len, reverse=True):
            words = len(s.split())
            head = " ".join(l.split()[:words])
            if difflib.SequenceMatcher(None, head.lower(), s.lower()).ratio() > 0.8:
                best = (s, " ".join(l.split()[words:])); break
        if best: out.append([phase, sec, best[0], best[1]])
    return out
d = json.load(open(sys.argv[1]))
res = {}
for k, r in d.items():
    C, O = table(r["C"]), table(r["O"])
    res[k] = {"C": [(p, rr) for p, rr, _ in C], "O": [(p, rr) for p, rr, _ in O],
              "I": instr(r["IP"], "IP") + instr(r["OOP"], "OOP")}
json.dump(res, open("/home/claude/ocrparse/parsed.json", "w"))
def side(p): return "R" if "(R)" in p else "L" if "(L)" in p else ""
final, problems = {}, []
for k, v in res.items():
    pool = list(v["O"]); used = [False]*len(pool); rows = []
    for p, rr in v["C"]:
        if len(rr) != 2: problems.append((k, p, rr)); continue
        cands = [i for i, (op, orr) in enumerate(pool) if not used[i] and orr == [rr[1]]]
        pref = [i for i in cands if side(pool[i][0]) == side(p)] if side(p) else []
        i = (pref or cands or [None])[0]
        if i is None: problems.append((k, p, rr, "no OOP match")); continue
        used[i] = True; rows.append([p, rr[0], pool[i][0], rr[1]])
    if len(rows) != 11: problems.append((k, "rows", len(rows)))
    final[k] = {"rows": rows, "I": v["I"]}
json.dump(final, open("/home/claude/ocrparse/final.json", "w"))
for k, v in final.items():
    print(k, len(v["rows"]), " | ".join(f"{a} {b}/{c} {d}" if a != c else f"{a} {b}/{d}" for a, b, c, d in v["rows"]))
print("PROBLEMS", problems)
