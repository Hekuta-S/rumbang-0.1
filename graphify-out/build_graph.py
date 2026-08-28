# Regenera el grafo de graphify para este proyecto Godot.
# Uso:  python build_graph.py
# Genera: graphify-out/graph.json, GRAPH_REPORT.md, graph.html, .graphify_analysis.json
import io, sys, json, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
from pathlib import Path

ROOT = Path.cwd().resolve()
OUT = ROOT / "graphify-out"
OUT.mkdir(parents=True, exist_ok=True)


def make_id(*parts) -> str:
    joined = "_".join(p.strip("_.") for p in parts if p)
    joined = joined.casefold()
    joined = re.sub(r"[^\w]+", "_", joined, flags=re.UNICODE)
    joined = re.sub(r"_+", "_", joined)
    return joined.strip("_")


FILES = sorted(ROOT.rglob("*.gd"))
FILE_ID = {}
for f in FILES:
    rel = f.relative_to(ROOT)
    FILE_ID[f] = make_id(rel.with_suffix("").as_posix().replace("/", "_"))

RES_MAP = {}
for f in ROOT.rglob("*"):
    if f.suffix.lower() in (".gd", ".tscn", ".tres"):
        RES_MAP["res://" + f.relative_to(ROOT).as_posix()] = f


def norm_sf(p: Path) -> str:
    try:
        return str(p.relative_to(ROOT))
    except ValueError:
        return str(p).replace("\\", "/")


def load_target(res: str):
    res = res.strip().strip('"').strip("'")
    if not res.startswith("res://"):
        return None
    t = RES_MAP.get(res)
    if t is None:
        return None
    if t.suffix == ".gd":
        return FILE_ID.get(t)
    if t.suffix in (".tscn", ".tres"):
        gd = t.with_suffix(".gd")
        return FILE_ID.get(gd)
    return None


NODES, EDGES = [], []
CONF = "EXTRACTED"

for f in FILES:
    sf = norm_sf(f)
    fid = FILE_ID[f]
    text = f.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    NODES.append({
        "id": fid, "label": f.name, "source_file": sf, "file_type": "code",
        "summary": re.sub(r"\s+", " ", text[:2000]), "line_count": len(lines),
        "_origin": "ast",
    })
    m = re.search(r"^\s*class_name\s+(\w+)", text, re.M)
    if m:
        cid = make_id(fid, m.group(1))
        NODES.append({"id": cid, "label": m.group(1), "source_file": sf,
                      "file_type": "code", "kind": "class",
                      "source_location": f"{sf}:{text[:m.start()].count(chr(10))+1}", "_origin": "ast"})
        EDGES.append({"source": fid, "target": cid, "relation": "defines", "confidence": CONF, "source_file": sf})
    m = re.search(r"^\s*extends\s+([\w.]+)", text, re.M)
    if m:
        ext = m.group(1).strip()
        eid = make_id("godot", ext.replace(".", "_"))
        NODES.append({"id": eid, "label": ext, "source_file": f"godot:{ext}",
                      "file_type": "concept", "kind": "builtin", "_origin": "ast"})
        EDGES.append({"source": fid, "target": eid, "relation": "extends", "confidence": CONF, "source_file": sf})
    for m in re.finditer(r"^\s*signal\s+(\w+)", text, re.M):
        sid = make_id(fid, m.group(1))
        NODES.append({"id": sid, "label": m.group(1), "source_file": sf, "file_type": "code",
                      "kind": "signal", "source_location": f"{sf}:{text[:m.start()].count(chr(10))+1}", "_origin": "ast"})
        EDGES.append({"source": fid, "target": sid, "relation": "defines", "confidence": CONF, "source_file": sf})
    for m in re.finditer(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", text, re.M):
        fnid = make_id(fid, m.group(1))
        NODES.append({"id": fnid, "label": m.group(1), "source_file": sf, "file_type": "code",
                      "kind": "function", "params": re.sub(r"\s+", " ", m.group(2)).strip(),
                      "source_location": f"{sf}:{text[:m.start()].count(chr(10))+1}", "_origin": "ast"})
        EDGES.append({"source": fid, "target": fnid, "relation": "defines", "confidence": CONF, "source_file": sf})
    # Intra-file function call edges: find each func's body, collect callee names
    func_ranges = []
    for m in re.finditer(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", text, re.M):
        start = m.start()
        body_start = text.find("{", start) if "{" in text[start:] else None
        func_ranges.append((m.group(1), start, body_start))
    # Simple scan: from each func header to the next header (or EOF), find local calls
    headers = [m for m in re.finditer(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", text, re.M)]
    for i, h in enumerate(headers):
        caller = h.group(1)
        cid = make_id(fid, caller)
        end = headers[i + 1].start() if i + 1 < len(headers) else len(text)
        body = text[h.end():end]
        for name in set(re.findall(r"(?<![\w.])\b(\w+)\s*\(", body)):
            tid = make_id(fid, name)
            if tid != cid and any(n["id"] == tid and n.get("kind") == "function" for n in NODES):
                EDGES.append({"source": cid, "target": tid, "relation": "calls",
                              "confidence": "INFERRED", "source_file": sf})
    for m in re.finditer(r'\b(?:preload|load)\s*\(\s*"([^"]+)"\s*\)', text):
        tgt = load_target(m.group(1))
        if tgt and tgt != fid:
            EDGES.append({"source": fid, "target": tgt, "relation": "imports",
                          "confidence": "INFERRED", "source_file": sf})
    for m in re.finditer(r"(\w+)\s*\.\s*(\w+)\s*\.\s*connect\s*\(\s*(\w+)\s*[,)]", text):
        _, _, handler = m.groups()
        hid = make_id(fid, handler)
        if any(n["id"] == hid for n in NODES):
            EDGES.append({"source": fid, "target": hid, "relation": "handles_signal",
                          "confidence": "INFERRED", "source_file": sf})

seen, dedup = set(), []
for e in EDGES:
    k = (e["source"], e["target"], e["relation"])
    if k not in seen:
        seen.add(k); dedup.append(e)
nseen, ndedup = set(), []
for n in NODES:
    if n["id"] not in nseen:
        nseen.add(n["id"]); ndedup.append(n)

extraction = {"nodes": ndedup, "edges": dedup, "hyperedges": [],
              "input_tokens": 0, "output_tokens": 0}
(OUT / ".graphify_extract.json").write_text(json.dumps(extraction, ensure_ascii=False), encoding="utf-8")

from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate
from graphify.export import to_json, to_html

G = build_from_json(extraction, root=str(ROOT), directed=False)
if G.number_of_nodes() == 0:
    print("ERROR: Graph is empty"); raise SystemExit(1)

communities = cluster(G)
cohesion = score_all(G, communities)
gods = god_nodes(G)
surprises = surprising_connections(G, communities)

# Labels heuristic: dominant class/kind per community
byname = {}
for n in ndedup:
    byname[n["id"]] = n.get("kind", "") + " " + n.get("label", "")
labels = {}
for cid, members in communities.items():
    kinds = [n.split(" ")[0] for n in members if n in byname]
    from collections import Counter
    top = Counter(k for k in kinds if k).most_common(1)
    labels[cid] = f"Community {cid} ({top[0][0] if top else 'mixed'})"

questions = suggest_questions(G, communities, labels)
detection = {"total_files": len(ndedup), "total_words": sum(len(n.get("summary", "").split()) for n in ndedup)}
report = generate(G, communities, cohesion, labels, gods, surprises, detection,
                  {"input": 0, "output": 0}, str(ROOT), suggested_questions=questions)
(OUT / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")
(OUT / ".graphify_labels.json").write_text(json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding="utf-8")
analysis = {"communities": {str(k): v for k, v in communities.items()},
            "cohesion": {str(k): v for k, v in cohesion.items()},
            "gods": gods, "surprises": surprises, "questions": questions}
(OUT / ".graphify_analysis.json").write_text(json.dumps(analysis, indent=2, ensure_ascii=False), encoding="utf-8")
wrote = to_json(G, communities, str(OUT / "graph.json"), community_labels=labels)
to_html(G, communities, str(OUT / "graph.html"), community_labels=labels)
print(f"Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(communities)} communities")
print(f"Outputs: graphify-out/graph.json, GRAPH_REPORT.md, graph.html")
