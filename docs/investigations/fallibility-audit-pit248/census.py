#!/usr/bin/env python3
"""Full-tree census for the PIT-248 fallibility-downgrade audit (t-mungw3ci-0i43).

Comparisons (all against HEAD = pristine tree):
  head vs coord, head vs fixed2, head vs fixed3
on both gen roots: reference/rust/gen (f64) and reference/rust-f32/gen (f32).

Per pair+root it reports:
  [inventory]   file counts per tree (denominator), file-set deltas
  [byte-diff]   authoritative changed-file set (diff -rq equivalent)
  [sigs]        per-symbol signature comparison on the common file set:
                for each (file, fn-name, params) the return type in each tree,
                classified RESULT_LOST / RESULT_GAINED / OTHER
  [counts]      unwrap() and Result< as LINES and as OCCURRENCES (two calibers,
                per the TCN-121 counting pitfall); per-file unwrap() deltas
  [line-diff]   unified diff of each changed file (written to evidence/*.u)

Calibers:
  LINES        = number of lines containing >=1 occurrence (grep -c style)
  OCCURRENCES  = total occurrences across the tree (grep -o style)
Signature key = (file, fn name, normalized params); ret compared separately.
"""
import os, re, difflib

WS = "/home/losses/Development/tq-workspace"
EV = os.path.join(WS, "dc-warn/out/fallibility-audit/evidence")

TREES = {
    "head":   os.path.join(WS, "p09-chainA-work/execution-option-c-head-e1c65975"),
    "coord":  os.path.join(WS, "p09-chainA-work/execution-option-c-coord"),
    "fixed2": os.path.join(WS, "p09-chainA-work/execution-option-c-chainA-fixed2"),
    "fixed3": os.path.join(WS, "p09-chainA-work/execution-option-c-chainA-fixed3"),
}
ROOTS = ["reference/rust/gen", "reference/rust-f32/gen"]
PAIRS = [("head", "coord"), ("head", "fixed2"), ("head", "fixed3")]

FN_RE = re.compile(r'(?:(?:pub|const|unsafe|async|extern)\s+)*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(')

def norm(s):
    return re.sub(r'\s+', ' ', s).strip()

def rs_files(root):
    out = set()
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if f.endswith(".rs"):
                out.add(os.path.relpath(os.path.join(dp, f), root))
    return out

def signatures(text):
    """Return list of (name, norm_params, norm_ret) for every fn declaration."""
    sigs = []
    for m in FN_RE.finditer(text):
        name = m.group(1)
        i = m.end() - 1                      # position of '('
        depth = 0
        j = i
        while j < len(text):
            c = text[j]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if depth != 0:
            continue
        params = norm(text[i + 1:j])
        k = j + 1
        while k < len(text) and text[k] not in "{;":
            k += 1
        if k >= len(text):
            continue
        ret = norm(text[j + 1:k])
        sigs.append((name, params, ret))
    return sigs

def count(text, pat):
    occ = len(re.findall(pat, text))
    lines = sum(1 for ln in text.splitlines() if re.search(pat, ln))
    return lines, occ

def main():
    print("# census start")
    inv = {}
    for t, tp in TREES.items():
        for r in ROOTS:
            root = os.path.join(tp, r)
            files = rs_files(root)
            inv[(t, r)] = files
            print(f"[inventory] tree={t} root={r} rs_files={len(files)}")
    print()

    for (ta, tb) in PAIRS:
        for r in ROOTS:
            ra = os.path.join(TREES[ta], r)
            rb = os.path.join(TREES[tb], r)
            fa, fb = inv[(ta, r)], inv[(tb, r)]
            common = fa & fb
            only_a = sorted(fa - fb)
            only_b = sorted(fb - fa)
            print(f"===== pair={ta}->{tb} root={r} =====")
            print(f"[file-set] a={len(fa)} b={len(fb)} common={len(common)} only_in_a={len(only_a)} only_in_b={len(only_b)}")
            if only_a: print(f"[only-in-{ta}] " + " ".join(only_a[:40]) + (f" (+{len(only_a)-40} more)" if len(only_a) > 40 else ""))
            if only_b: print(f"[only-in-{tb}] count={len(only_b)} first20: " + " ".join(only_b[:20]))

            changed = []
            for f in sorted(common):
                with open(os.path.join(ra, f), "rb") as fh: da = fh.read()
                with open(os.path.join(rb, f), "rb") as fh: db = fh.read()
                if da != db:
                    changed.append(f)
            print(f"[byte-diff] changed_files={len(changed)}")
            for f in changed:
                print(f"  CHANGED {f}")
            print()

            def root_counts(tree_root):
                tot = {"unwrap_lines": 0, "unwrap_occ": 0, "result_lines": 0, "result_occ": 0,
                       "sigs": 0, "sigs_result": 0, "files": 0}
                perfile = {}
                for f in sorted(rs_files(tree_root)):
                    with open(os.path.join(tree_root, f), "r", errors="replace") as fh:
                        text = fh.read()
                    tot["files"] += 1
                    ul, uo = count(text, r"\.unwrap\(\)")
                    rl, ro = count(text, r"Result<")
                    tot["unwrap_lines"] += ul; tot["unwrap_occ"] += uo
                    tot["result_lines"] += rl; tot["result_occ"] += ro
                    s = signatures(text)
                    ns = len(s)
                    nsr = sum(1 for _, _, rt in s if rt.startswith("-> Result<"))
                    tot["sigs"] += ns
                    tot["sigs_result"] += nsr
                    perfile[f] = (ul, uo, rl, ro, ns, nsr)
                return tot, perfile
            ca, pf_a = root_counts(ra)
            cb, pf_b = root_counts(rb)
            ua = {f: v[1] for f, v in pf_a.items() if v[1]}
            ub = {f: v[1] for f, v in pf_b.items() if v[1]}
            # common-set restricted totals
            cc_a = [0, 0, 0, 0, 0, 0]; cc_b = [0, 0, 0, 0, 0, 0]
            for f in sorted(common):
                for idx, v in enumerate(pf_a.get(f, (0, 0, 0, 0, 0, 0))): cc_a[idx] += v
                for idx, v in enumerate(pf_b.get(f, (0, 0, 0, 0, 0, 0))): cc_b[idx] += v
            print(f"[counts-common] common_files={len(common)}")
            print(f"[counts-common] {ta}: unwrap_lines={cc_a[0]} unwrap_occ={cc_a[1]} result_lines={cc_a[2]} result_occ={cc_a[3]} sigs={cc_a[4]} sigs_result={cc_a[5]}")
            print(f"[counts-common] {tb}: unwrap_lines={cc_b[0]} unwrap_occ={cc_b[1]} result_lines={cc_b[2]} result_occ={cc_b[3]} sigs={cc_b[4]} sigs_result={cc_b[5]}")
            print(f"[counts-common] DELTA ({tb}-{ta}): unwrap_occ={cc_b[1]-cc_a[1]:+d} result_occ={cc_b[3]-cc_a[3]:+d} sigs={cc_b[4]-cc_a[4]:+d} sigs_result={cc_b[5]-cc_a[5]:+d}")
            print(f"[counts] {ta}: files={ca['files']} unwrap_lines={ca['unwrap_lines']} unwrap_occ={ca['unwrap_occ']} "
                  f"result_lines={ca['result_lines']} result_occ={ca['result_occ']} sigs={ca['sigs']} sigs_result={ca['sigs_result']}")
            print(f"[counts] {tb}: files={cb['files']} unwrap_lines={cb['unwrap_lines']} unwrap_occ={cb['unwrap_occ']} "
                  f"result_lines={cb['result_lines']} result_occ={cb['result_occ']} sigs={cb['sigs']} sigs_result={cb['sigs_result']}")
            print(f"[counts] DELTA ({tb}-{ta}): unwrap_lines={cb['unwrap_lines']-ca['unwrap_lines']:+d} unwrap_occ={cb['unwrap_occ']-ca['unwrap_occ']:+d} "
                  f"result_lines={cb['result_lines']-ca['result_lines']:+d} result_occ={cb['result_occ']-ca['result_occ']:+d} "
                  f"sigs={cb['sigs']-ca['sigs']:+d} sigs_result={cb['sigs_result']-ca['sigs_result']:+d}")
            delta_files = sorted(set(ua) | set(ub))
            nd = 0
            for f in delta_files:
                d = ub.get(f, 0) - ua.get(f, 0)
                if d:
                    nd += 1
                    print(f"  [unwrap-per-file] {f}: {ua.get(f,0)} -> {ub.get(f,0)} ({d:+d})")
            print(f"  [unwrap-per-file] files_with_delta={nd}")

            lost, gained, other = [], [], []
            for f in sorted(common):
                with open(os.path.join(ra, f), "r", errors="replace") as fh: ta_text = fh.read()
                with open(os.path.join(rb, f), "r", errors="replace") as fh: tb_text = fh.read()
                sa = {}
                for n, p, rt in signatures(ta_text):
                    sa.setdefault((n, p), []).append(rt)
                sb = {}
                for n, p, rt in signatures(tb_text):
                    sb.setdefault((n, p), []).append(rt)
                for key in sorted(set(sa) | set(sb)):
                    ra_ret, rb_ret = sa.get(key, []), sb.get(key, [])
                    if ra_ret == rb_ret:
                        continue
                    a_is_res = all(x.startswith("-> Result<") for x in ra_ret) if ra_ret else False
                    b_is_res = all(x.startswith("-> Result<") for x in rb_ret) if rb_ret else False
                    ent = (f, key[0], key[1], ra_ret, rb_ret)
                    if a_is_res and not b_is_res and ra_ret and rb_ret:
                        lost.append(ent)
                    elif b_is_res and not a_is_res and ra_ret and rb_ret:
                        gained.append(ent)
                    else:
                        other.append(ent)
            print(f"[sigs] common_files={len(common)} RESULT_LOST={len(lost)} RESULT_GAINED={len(gained)} OTHER_SIG_DIFF={len(other)}")
            for f, n, p, ra_ret, rb_ret in lost:
                print(f"  RESULT_LOST  {f} :: {n}({p})\n     {ta}: {ra_ret}\n     {tb}: {rb_ret}")
            for f, n, p, ra_ret, rb_ret in gained:
                print(f"  RESULT_GAINED {f} :: {n}({p})\n     {ta}: {ra_ret}\n     {tb}: {rb_ret}")
            for f, n, p, ra_ret, rb_ret in other:
                print(f"  OTHER        {f} :: {n}({p})\n     {ta}: {ra_ret}\n     {tb}: {rb_ret}")

            for f in changed:
                with open(os.path.join(ra, f), "r", errors="replace") as fh: da = fh.readlines()
                with open(os.path.join(rb, f), "r", errors="replace") as fh: db = fh.readlines()
                diff = list(difflib.unified_diff(da, db, fromfile=f"{ta}/{f}", tofile=f"{tb}/{f}", lineterm=""))
                safe = f.replace("/", "__")
                outp = os.path.join(EV, f"v2diff_{ta}_{tb}_{r.replace('/', '__')}_{safe}.u")
                with open(outp, "w") as fh:
                    fh.write("".join(diff) if diff else "(no line diff; byte-level only)\n")
                print(f"[line-diff] {f} -> {os.path.relpath(outp, EV)} ({len(diff)} diff lines)")
            print()
    print("# census done")

if __name__ == "__main__":
    main()
