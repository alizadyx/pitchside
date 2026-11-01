import json, re, sys, collections, glob, difflib, openpyxl
exec(open("build.py").read().split("style, prefix, src, dst")[0])
# value vocabulary from the workbooks made by the other tool
VOC = collections.defaultdict(set)
for f in glob.glob("/home/claude/fm27-presets/0[1-5]-*.xlsx"):
    for r in openpyxl.load_workbook(f, data_only=True)["Instructions"].iter_rows(min_row=4, values_only=True):
        if r[0] in ("IP", "OOP") and r[3]: VOC[r[2]].add(r[3])
EXTRA = {"Balanced", "Standard", "No", "Yes", "Counter-Press", "Regroup", "Drop Off More", "Low Block", "Lower", "Much Lower", "Deeper", "Encourage", "Discourage",
         "Pass Into Space", "Pass Into Feet", "Distribute Quickly", "Slow Pace Down", "Bypass Press", "Long", "Mixed", "Short",
         "Trap Outside", "Trap Inside", "Get Stuck In", "Stay On Feet", "Hit Early Crosses", "Play For Set Pieces",
         "More Disciplined", "More Expressive", "Much More Direct", "More Direct", "Less Often", "More Often", "Fewer", "Invite Crosses", "Stop Crosses"}
def fixval(setting, v):
    known = VOC[setting] | EXTRA
    if v in known: return v, None
    m = difflib.get_close_matches(v, known, n=1, cutoff=0.8)
    return (m[0], None) if m else (v, f"{setting}='{v}'")
def rowsets(texts, ncols):
    out = []
    for t in texts:
        rows = [(p, rr) for p, rr, _ in table(t)]
        if len(rows) == 11: out.append(rows)
    return out
def vote(vals):
    c = collections.Counter(v for v in vals if v)
    if not c: return None, 0, 0
    (v, n), tot = c.most_common(1)[0], sum(c.values())
    return v, n, tot
style, prefix, src, src2, dst = sys.argv[1:6]
d, d2 = json.load(open(src)), json.load(open(src2))
presets, issues, instrs, ments, weak = {}, [], {}, set(), []
for k in d:
    v2 = d2[k]
    Cs = rowsets(v2["C"] + [d[k]["C"]], 2); As = rowsets(v2["A"] + [d[k]["A"]], 1); Os = rowsets(v2["O"] + [d[k]["O"]], 1)
    if not Cs or not Os: issues.append(f"{k[:2]} no complete table (C {len(Cs)}, O {len(Os)})"); continue
    rows = []
    for i in range(11):
        ps, _, _ = vote([c[i][0] for c in Cs])
        ipv = [c[i][1][0] for c in Cs if len(c[i][1]) == 2] + [a[i][1][0] for a in As if a[i][0] == ps and len(a[i][1]) == 1]
        oov = [c[i][1][1] for c in Cs if len(c[i][1]) == 2]
        ip, n1, t1 = vote(ipv); oo, n2, t2 = vote(oov)
        if ip is None or oo is None: issues.append(f"{k[:2]} row {i+1} {ps} unreadable"); continue
        if n1 < 0.7 * t1 or n2 < 0.7 * t2: weak.append(f"{k[:2]} {ps} IP {dict(collections.Counter(ipv))} OOP {dict(collections.Counter(oov))}")
        rows.append([ps, ip, oo])
    # OOP positions: vote the OOP view row by row, then pair by role
    pool = []
    for i in range(11):
        p, _, _ = vote([o[i][0] for o in Os]); r, _, _ = vote([o[i][1][0] for o in Os if len(o[i][1]) == 1]); pool.append((p, r))
    used = [False] * 11; out = []
    for p, ip, oo in rows:
        cands = [i for i, (op, orr) in enumerate(pool) if not used[i] and orr == oo]
        pref = [i for i in cands if side(pool[i][0]) == side(p)] if side(p) else []
        i = (pref or cands or [None])[0]
        if i is None: issues.append(f"{k[:2]} {p} {ip}/{oo}: OOP role not in OOP view {pool}"); out.append([p, ip, p, oo]); continue
        used[i] = True; out.append([p, ip, pool[i][0], oo])
    presets[k] = out
    m = re.search(MENT, d[k]["M"]); ments.add(m.group(1) if m else "?")
    instrs[k] = instr(d[k]["IP"], "IP") + instr(d[k]["OOP"], "OOP")
keys = [tuple(x[:3]) for x in max(instrs.values(), key=len)]
final_i = []
for key in keys:
    vals = collections.Counter(fixval(key[2], x[3])[0] for I in instrs.values() for x in I if tuple(x[:3]) == key)
    v, n = vals.most_common(1)[0]
    if n < len(instrs) - 1: issues.append(f"instruction {key[2]} disagrees: {dict(vals)}")
    _, bad = fixval(key[2], v)
    if bad: issues.append("unknown value " + bad)
    final_i.append(list(key) + [v])
if len(final_i) != 29: issues.append(f"{len(final_i)} instruction rows")
wb = openpyxl.Workbook(); ws = wb.active; ws.title = "Presets"
ws.append([style]); ws.append(["OCR, several readings per table voted, cross-checked against the IP and OOP views."])
ws.append(["Preset ID", "Menu order", "Style", "IP formation", "OOP formation", "Mentality", "Screenshot folder"])
ment = "/".join(sorted(ments)); ids = {}
for k in presets:
    n = int(k[:2]); ipf, oopf = k[3:].split(" -- "); ids[k] = f"{prefix}{n:02d}"
    ws.append([ids[k], n, style, ipf, oopf, ment, k])
r = wb.create_sheet("Roles"); r.append(["Positions and roles"]); r.append([""])
r.append(["Preset ID", "Combined row", "IP position", "IP role", "OOP position", "OOP role", "Source IDs"])
for k, rows in presets.items():
    for i, row in enumerate(rows, 1): r.append([ids[k], i] + row + [""])
ins = wb.create_sheet("Instructions"); ins.append(["Team instructions"]); ins.append([""])
ins.append(["Phase", "Section", "Setting"] + list(ids.values()))
for row in final_i: ins.append(row[:3] + [row[3]] * len(ids))
wb.create_sheet("Audit").append(["OCR"]); wb.save(dst)
print(f"## {style}: mentality {ments}, presets {len(presets)}")
if "-v" in sys.argv:
    for k, rows in presets.items():
        print(k[:2], k[3:], "::", " | ".join(f"{a} {b}/{c} {dd}" if a != c else f"{a} {b}/{dd}" for a, b, c, dd in rows))
    print("IP:", "; ".join(f"{x[2]}={x[3]}" for x in final_i if x[0] == "IP" and x[3] not in ("Balanced", "Standard")))
    print("OOP:", "; ".join(f"{x[2]}={x[3]}" for x in final_i if x[0] == "OOP" and x[3] not in ("Balanced", "Standard")))
print("ISSUES:", issues or "none"); print("WEAK VOTES:", weak or "none")
