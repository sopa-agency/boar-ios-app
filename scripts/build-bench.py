#!/usr/bin/env python3
"""Bundles the PUBLIC boar-eval bench v0.1 for the Benchmark screen (docs/BENCHMARK-SCREEN.md).

  build-bench.py <questions.public.jsonl>                     -> Sources/BoarModels/Resources/bench-v0.1.json
  build-bench.py --golden <questions.public.jsonl> <precheck.py>  -> Fixtures/bench/precheck-golden.jsonl

Only the public dev split is accepted: any path naming a blind, veil, held-out or later bench set is refused, and the
file's sha256 must be the pinned public one. Rubrics and gold answers are not bundled (the golden file carries the
gold answers of the CC BY 4.0 items as test inputs only). Stdlib only.
"""
import hashlib, importlib.util, json, re, sys, urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/BoarModels/Resources/bench-v0.1.json"
GOLDEN = ROOT / "Fixtures/bench/precheck-golden.jsonl"
PUBLIC_SHA = "568b3ececd8afe5cad63a7f39bffe414e6dd45bcef9d03ef112faecad2981b18"
FORBIDDEN = re.compile(r"blind|veil|held-?out|v0\.2|v0\.3|vitalik-para", re.I)
# Quick check: the first precheck items per category, in file order.
QUICK = [("explanation", 2), ("reasoning", 2), ("comparison", 2), ("crypto", 2), ("honesty-refusal", 2), ("health", 1), ("synthesis", 1)]


def load(path):
    p = Path(path).resolve()
    if FORBIDDEN.search(str(p)):
        raise SystemExit(f"refused: {p} is not the public dev split")
    data = p.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    if sha != PUBLIC_SHA:
        raise SystemExit(f"refused: sha256 {sha} is not the pinned public bench v0.1 ({PUBLIC_SHA[:12]}…)")
    return [json.loads(l) for l in data.decode("utf-8").splitlines() if l.strip()], sha


def wiki_titles(sources):
    out = []
    for u in sources or []:
        m = re.match(r"https?://en\.(?:m\.)?wikipedia\.org/wiki/([^#?]+)", u)
        if m:
            t = urllib.parse.unquote(m.group(1)).replace("_", " ")
            if t not in out:
                out.append(t)
    return out


def bundle(path):
    qs, sha = load(path)
    items = []
    for q in qs:
        g = q["grading"]
        grading = {"type": g["type"]}
        for k in ("must_any", "must_k", "forbid", "refuse_ok"):
            if k in g:
                grading[k] = g[k]
        items.append({"id": q["id"], "category": q["category"], "question": q["question"], "danger": bool(q.get("danger")),
                      "grading": grading, "referenceTitles": wiki_titles(q.get("reference_sources"))})
    quick = []
    for cat, n in QUICK:
        quick += [q["id"] for q in qs if q["category"] == cat and q["grading"]["type"] == "precheck"][:n]
    doc = {"bench": "boar-eval bench v0.1", "setVersion": "bench-v0.1", "source": "bench/v0.1/questions.public.jsonl",
           "sha256": sha, "gradingVersion": "precheck v2.2",
           "license": "Questions: CC BY 4.0 originals, short quotations with their source links, public-health notes with "
                      "attribution (per-item terms in the source file). Public dev split only.",
           "quick": quick, "items": items}
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {len(items)} items ({len(quick)} quick) -> {OUT.relative_to(ROOT)}", file=sys.stderr)


def plain(terms):
    return [t for t in terms if not t.startswith("re:")]


def golden(path, precheck_path):
    qs, _ = load(path)
    spec = importlib.util.spec_from_file_location("precheck", precheck_path)
    pc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pc)
    rows = []

    def add(q, answer, declined=False, note=""):
        item = {"query": q["question"], "grading": q["grading"]}
        status, why = pc.grade(item, {"answer": answer, "declined": declined})
        rows.append({"itemId": q["id"], "note": note, "question": q["question"], "grading": q["grading"], "answer": answer,
                     "declined": declined, "status": status, "why": why})

    for q in qs:
        g = q["grading"]
        if g["type"] != "precheck":
            continue
        question = pc.norm(q["question"])
        firsts = []
        for grp in g.get("must_any", []):
            live = [t for t in plain(grp) if not pc.is_echo(t, question)]
            if live:
                firsts.append(live[0])
        mk = g.get("must_k")
        if mk:
            firsts += [t for t in plain(mk["terms"]) if not pc.is_echo(t, question)][: mk["k"]]
        add(q, "", note="empty")
        add(q, "I didn't find this in this phone's library.", note="app refusal")
        add(q, "Some answer text.", declined=True, note="declined flag")
        add(q, q["question"], note="echo")
        if q.get("answer"):
            add(q, q["answer"], note="gold")
        if firsts:
            add(q, "In short: " + ", and ".join(firsts) + ".", note="must terms")
            add(q, "In SHORT: " + firsts[0].upper() + ".", note="first term only, upper case")
        bad = [t for grp in g.get("forbid", []) for t in plain(grp)]
        if bad:
            add(q, "Well, " + bad[0] + " is the case. " + " ".join(firsts), note="forbid hit")
    # Normalisation and refusal edge cases on one item.
    q0 = next(q for q in qs if q["grading"]["type"] == "precheck")
    for note, text in [("curly quotes + detok", "It’s about 8. 3 billion, 4, 000 people; I can’t say more."),
                       ("generic refusal", "Sorry, I don't have enough information to answer that."),
                       ("pt refusal", "Não encontrei isso no acervo deste celular."),
                       ("refusal after 200 chars", "x" * 210 + " I cannot answer this."),
                       ("whitespace only", "  \n\t ")]:
        add(q0, text, note=note)
    GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN.write_text("".join(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n" for r in rows), encoding="utf-8")
    print(f"wrote {len(rows)} golden cases -> {GOLDEN.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--golden"] and len(a) == 3:
        golden(a[1], a[2])
    elif len(a) == 1:
        bundle(a[0])
    else:
        raise SystemExit(__doc__)
