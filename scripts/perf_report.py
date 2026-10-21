#!/usr/bin/env python3
"""Summarizes a BOAR performance trace or the phone's jetsam reports (scripts/perf.sh, docs/PERF.md).

perf_report.py TRACE        hangs, BOAR signposts (model.load, answer, main.stall…), CPU per thread, main-thread hot
                            frames inside each hang
perf_report.py --jetsam DIR memory kills (biggest processes, BOAR's footprint, MTLCompilerService) and BOAR crashes
"""
import collections, glob, json, os, subprocess, sys, xml.etree.ElementTree as ET

SUBSYSTEM = "team.sopa.boar"


def export(trace, schema):
    xpath = f'/trace-toc/run[1]/data/table[@schema="{schema}"]'
    r = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return []
    root = ET.fromstring(r.stdout)
    ids = {}

    def resolve(e):
        ref = e.get("ref")
        if ref is not None:
            return ids.get(ref, e)
        if e.get("id") is not None:
            ids[e.get("id")] = e
        for c in e:
            resolve(c)
        return e

    cols, rows = [], []
    for node in root.iter("node"):
        schema_el = node.find("schema")
        if schema_el is not None:
            cols = [c.findtext("mnemonic") for c in schema_el.findall("col")]
        for row in node.findall("row"):
            vals = {}
            for i, c in enumerate(row):
                vals[cols[i] if i < len(cols) else c.tag] = resolve(c)
            rows.append(vals)
    return rows


def fmt(e):
    return "" if e is None else (e.get("fmt") or e.text or "")


def num(e):
    try:
        return int(e.text) / 1e9
    except (AttributeError, TypeError, ValueError):
        return None


def frames(bt):
    if bt is None:
        return []
    return [f.get("name") or "?" for f in bt.iter("frame")]


def report(trace):
    print(f"# {os.path.basename(trace)}")
    hangs = [(num(r.get("start")), num(r.get("duration")), fmt(r.get("hang-type"))) for r in export(trace, "potential-hangs")]
    print(f"\n## Hangs ({len(hangs)}, total {sum(h[1] or 0 for h in hangs):.2f} s)")
    for s, d, t in hangs:
        print(f"  {s:7.2f} s  {d * 1000:7.0f} ms  {t}")

    print("\n## BOAR signposts")
    open_, seen = {}, set()
    # The template records Points of Interest into more than one os-signpost table: the same row comes back once per table.
    rows = [r for r in export(trace, "os-signpost") if fmt(r.get("subsystem")) == SUBSYSTEM]
    for r in sorted(rows, key=lambda r: num(r.get("time")) or 0):
        t, kind, name = num(r.get("time")), fmt(r.get("event-type")), fmt(r.get("name"))
        key = (name, fmt(r.get("identifier")))
        msg = fmt(r.get("message"))
        if (t, kind, key) in seen:
            continue
        seen.add((t, kind, key))
        if kind == "Begin":
            open_[key] = (t, msg)
        elif kind == "End" and key in open_:
            t0, m0 = open_.pop(key)
            print(f"  {t0:7.2f} s  {(t - t0) * 1000:8.0f} ms  {name}  {m0}  → {msg}")
        elif kind == "End":
            print(f"  {t:7.2f} s  {'end only':>11}  {name}  → {msg}  (its Begin came before signposts reached the trace)")
        elif kind == "Event":
            print(f"  {t:7.2f} s  {'event':>11}  {name}  {msg}")
    for (name, _), (t0, m0) in open_.items():
        print(f"  {t0:7.2f} s  {'unfinished':>11}  {name}  {m0}")

    samples = []
    for r in export(trace, "time-profile"):
        t = num(r.get("time"))
        th = fmt(r.get("thread")).split(" (")[0]
        samples.append((t, th, frames(next((r[k] for k in ("stack", "backtrace", "tagged-backtrace") if r.get(k) is not None), None))))
    per_thread = collections.Counter(th for _, th, _ in samples)
    print(f"\n## CPU samples per thread ({len(samples)} × 1 ms)")
    for th, n in per_thread.most_common(8):
        print(f"  {n:6d}  {th}")

    for s, d, _ in hangs[:6]:
        inside = [f for t, th, f in samples if th.startswith("Main Thread") and t is not None and s <= t <= s + d]
        if not inside:
            print(f"\n## Main thread in the hang at {s:.2f} s: no CPU samples (blocked: I/O, lock, or the system starved it)")
            continue
        incl = collections.Counter()
        for f in inside:
            for name in set(f):
                incl[name] += 1
        ours = [(n, c) for n, c in incl.most_common(400) if n != "?" and not any(x in n for x in ("start", "main", "UIApplication", "CFRunLoop", "GSEvent", "dispatch"))]
        print(f"\n## Main thread in the hang at {s:.2f} s ({len(inside)} samples), heaviest frames")
        for n, c in ours[:12]:
            print(f"  {c:5d}  {n[:140]}")


def jetsam(d):
    for f in sorted(glob.glob(os.path.join(d, "**", "JetsamEvent-*.ips"), recursive=True)):
        body = json.loads(open(f).read().split("\n", 1)[1])
        ps = body.get("pageSize", 16384)
        procs = body.get("processes", [])
        mb = lambda p, k="rpages": p.get(k, 0) * ps >> 20
        killed = [p for p in procs if p.get("reason")]
        reasons = collections.Counter(p["reason"] for p in killed)
        free = body.get("memoryStatus", {}).get("memoryPages", {}).get("free", 0) * ps >> 20
        boar = [p for p in procs if p.get("name") == "Boar"]
        mtl = [mb(p) for p in procs if p.get("name") == "MTLCompilerService"]
        top = sorted(procs, key=lambda p: -p.get("rpages", 0))[:3]
        print(f"{os.path.basename(f)[12:-4]}  free {free} MB  killed {len(killed)} {dict(reasons)}")
        print("    top: " + ", ".join(f"{p.get('name')} {mb(p)} MB" for p in top))
        if boar:
            print(f"    Boar: {mb(boar[0])} MB now, {mb(boar[0], 'lifetimeMax')} MB max, {boar[0].get('states')}")
        if mtl:
            print(f"    MTLCompilerService ×{len(mtl)}: {sum(mtl)} MB")
    for f in sorted(glob.glob(os.path.join(d, "**", "Boar-*.ips"), recursive=True)):
        b = json.loads(open(f).read().split("\n", 1)[1])
        th = b["threads"][b.get("faultingThread", 0)]
        imgs = b.get("usedImages", [])
        print(f"\nCRASH {os.path.basename(f)}  {b.get('exception', {}).get('type')} {b.get('termination', {}).get('indicator')}")
        for fr in th.get("frames", [])[:12]:
            print(f"    {imgs[fr['imageIndex']].get('name', '?') if fr.get('imageIndex') is not None else '?'}  {fr.get('symbol', '?')}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--jetsam":
        jetsam(sys.argv[2])
    elif len(sys.argv) == 2:
        report(sys.argv[1])
    else:
        print(__doc__)
        sys.exit(2)
