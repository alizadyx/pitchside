import json, re, sys, collections, openpyxl
exec(open("parse.py").read().split("d = json.load")[0])
_rf = roles_from
def roles_from(rest):
    out = []
    for t in rest.split():
        u = "TW" if "™" in t else re.sub(r"[^A-Z]", "", t)
        if u not in IPV | OOPV and len(set(u)) == 1 and u: u = u[0]
        if u in IPV | OOPV: out.append(u)
    return out
MENT = r"(Very Defensive|Defensive|Cautious|Balanced|Positive|Attacking|Very Attacking)"
def side(p): return "R" if "(R)" in p else "L" if "(L)" in p else ""
style, prefix, src, dst = sys.argv[1:5]
d = json.load(open(src))
presets, issues, instrs, ments = {}, [], {}, set()
for k, r in d.items():
    C = [(p, rr) for p, rr, _ in table(r["C"])]
    O = [(p, rr) for p, rr, _ in table(r["O"])]
    A = collections.Counter((p, rr[0]) for p, rr, _ in table(r["A"]) if rr)
    pool, used, rows = O, [False] * len(O), []
    for p, rr in C:
        if len(rr) != 2: issues.append(f"{k[:2]} combined row {p} {rr}"); continue
        cands = [i for i, (op, orr) in enumerate(pool) if not used[i] and orr == [rr[1]]]
        pref = [i for i in cands if side(pool[i][0]) == side(p)] if side(p) else []
        i = (pref or cands or [None])[0]
        if i is None: issues.append(f"{k[:2]} no OOP match {p} {rr}"); continue
        used[i] = True; rows.append([p, rr[0], pool[i][0], rr[1]])
    if len(rows) != 11: issues.append(f"{k[:2]} {len(rows)} rows")
    mine = collections.Counter((x[0], x[1]) for x in rows)
    if A != mine: issues.append(f"{k[:2]} IP view differs: view-only {dict(A - mine)} combined-only {dict(mine - A)}")
    m = re.search(MENT, r["M"]); ments.add(m.group(1) if m else "?")
    I = instr(r["IP"], "IP") + instr(r["OOP"], "OOP")
    instrs[k] = I
    presets[k] = rows
# instructions: majority value per setting
keys = [tuple(x[:3]) for x in max(instrs.values(), key=len)]
final_i = []
for key in keys:
    vals = collections.Counter(x[3] for I in instrs.values() for x in I if tuple(x[:3]) == key)
    v, n = vals.most_common(1)[0]
    if n < len(instrs) - 1: issues.append(f"instruction {key[2]} disagrees: {dict(vals)}")
    final_i.append(list(key) + [v])
if len(final_i) != 29: issues.append(f"{len(final_i)} instruction rows")
wb = openpyxl.Workbook(); ws = wb.active; ws.title = "Presets"
ws.append([style]); ws.append(["Read from the screenshots by OCR, cross-checked against the IP and OOP views."])
ws.append(["Preset ID", "Menu order", "Style", "IP formation", "OOP formation", "Mentality", "Screenshot folder"])
ment = sorted(ments)[0] if len(ments) == 1 else "/".join(sorted(ments))
ids = {}
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
wb.create_sheet("Audit").append(["OCR"])
wb.save(dst)
print(f"## {style}: mentality {ments}")
for k, rows in presets.items():
    print(k[:2], k[3:], "::", " | ".join(f"{a} {b}/{c} {dd}" if a != c else f"{a} {b}/{dd}" for a, b, c, dd in rows))
print("IP:", "; ".join(f"{x[2]}={x[3]}" for x in final_i if x[0] == "IP" and x[3] not in ("Balanced", "Standard")))
print("OOP:", "; ".join(f"{x[2]}={x[3]}" for x in final_i if x[0] == "OOP" and x[3] not in ("Balanced", "Standard")))
print("ISSUES:", issues or "none")
