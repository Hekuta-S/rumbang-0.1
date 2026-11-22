#!/usr/bin/env python3
"""Genera los diagramas ANTES / DESPUÉS del patrón Strategy aplicado a FateDice, y una página HTML
para la exposición con el código antes (errores resaltados) y el código después (correcciones comentadas).

Uso (sin dependencias, solo Python 3):
    python tools/make_strategy_diagrams.py

Salida en docs/strategy/:
    diagrama_antes.svg
    diagrama_despues.svg
    strategy_fatedice.html   <- abrir en el navegador (diagramas + código)

Los bloques de código se leen de:
    docs/strategy/ANTES_fate_dice.gd.txt            (copia del código original con los ⚠ ERROR n)
    scripts/objects/fate_dice.gd                     (apply / apply12 nuevos, comentados)
    scripts/patterns/strategy/fate_outcomes.gd       (las estrategias concretas)
Así la página siempre refleja el código real.
"""
import html
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "strategy")

# ───────────────────────────── paleta ─────────────────────────────
BG = "#14111f"
BOX = "#231d38"
BOX_STROKE = "#7c6bb0"
TEXT = "#f2eefc"
MUTED = "#a99fc9"
RED = "#ff5d5d"
RED_BG = "#4a1a22"
GREEN = "#5ee08a"
GREEN_BG = "#173a27"
GOLD = "#ffd35a"


def esc(s):
    return html.escape(s, quote=True)


class Svg:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.parts = []

    def raw(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, fill=BOX, stroke=BOX_STROKE, sw=2, rx=8, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def text(self, x, y, s, size=14, fill=TEXT, weight="normal", anchor="start", family="Consolas, 'Courier New', monospace", italic=False):
        st = ' font-style="italic"' if italic else ""
        self.raw(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" font-weight="{weight}" '
                 f'text-anchor="{anchor}" font-family="{family}"{st}>{esc(s)}</text>')

    def line(self, x1, y1, x2, y2, stroke=MUTED, sw=2, dash=None, marker=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        m = f' marker-end="url(#{marker})"' if marker else ""
        self.raw(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" stroke-width="{sw}"{d}{m}/>')

    def render(self):
        defs = (
            '<defs>'
            f'<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{MUTED}"/></marker>'
            f'<marker id="arrowred" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{RED}"/></marker>'
            f'<marker id="tri" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="12" markerHeight="12" orient="auto"><path d="M0,0 L12,6 L0,12 z" fill="{BG}" stroke="{GREEN}" stroke-width="1.5"/></marker>'
            f'<marker id="diamond" viewBox="0 0 14 10" refX="1" refY="5" markerWidth="14" markerHeight="10" orient="auto-start-reverse"><path d="M0,5 L7,0 L14,5 L7,10 z" fill="{BG}" stroke="{GOLD}" stroke-width="1.5"/></marker>'
            '</defs>'
        )
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" width="{self.w}" height="{self.h}">'
                f'<rect width="{self.w}" height="{self.h}" fill="{BG}"/>{defs}' + "".join(self.parts) + "</svg>")


def class_box(svg, x, y, w, title, rows, stereotype=None, title_fill=TEXT, stroke=BOX_STROKE, fill=BOX, row_h=24):
    """Caja UML. rows = [(texto, color|None)]. Devuelve (alto, y_filas) para colocar anotaciones."""
    head = 52 if stereotype else 36
    h = head + row_h * len(rows) + 12
    svg.rect(x, y, w, h, fill=fill, stroke=stroke)
    ty = y + 22
    if stereotype:
        svg.text(x + w / 2, ty, f"«{stereotype}»", 12, MUTED, anchor="middle", italic=True)
        ty += 18
    svg.text(x + w / 2, ty, title, 16, title_fill, "bold", anchor="middle")
    svg.line(x, y + head - 4, x + w, y + head - 4, stroke=stroke, sw=1)
    ys = []
    for i, (t, c) in enumerate(rows):
        ry = y + head + 16 + i * row_h
        ys.append(ry)
        svg.text(x + 12, ry, t, 13, c or TEXT)
    return h, ys


def callout(svg, x, y, w, h, lines, color=RED, bg=RED_BG):
    svg.rect(x, y, w, h, fill=bg, stroke=color, sw=2, rx=10, dash="6 4")
    for i, (t, bold) in enumerate(lines):
        svg.text(x + 12, y + 24 + i * 20, t, 13, color if bold else TEXT, "bold" if bold else "normal")


# ───────────────────────────── ANTES ─────────────────────────────
def build_before():
    s = Svg(1180, 640)
    s.text(590, 34, "ANTES — FateDice con dos `match` gigantes y código copiado", 22, RED, "bold", anchor="middle", family="Segoe UI, Arial, sans-serif")

    rows = [
        ("+ apply(v, p, scene, at)", RED),
        ("+ apply12(v, p, scene, at)", RED),
        ("- _ambush(p, scene, enc, survival)", RED),
        ("- _heal_full(p)", None),
        ("- _add_gold(scene, amount)", None),
        ("+ add_mod(stat, value, seconds…)", None),
        ("+ roll() / _resolve() / ask()", None),
        ("  … ~650 líneas: dado 3D, d12, UI…", MUTED),
    ]
    h, ys = class_box(s, 40, 90, 400, "FateDice", rows, stereotype="Node3D · hace TODO", stroke=RED, title_fill=RED)

    # RunEvents
    rrows = [("- _use_shrine(kind)", None), ('  match kind: "fury" → add_mod ×2', RED)]
    class_box(s, 820, 90, 320, "RunEvents", rrows, stereotype="otro archivo")

    # Callouts de errores
    callout(s, 520, 100, 260, 62, [("ERROR 1 · match v  (6 ramas)", True), ("editar apply() por cada cambio", False)])
    callout(s, 520, 180, 260, 62, [("ERROR 2 · match v  (12 ramas)", True), ("apply12 ≈ clon de apply", False)])
    callout(s, 520, 260, 260, 62, [("ERROR 5 · if survival", True), ("dentro de cada rama y _ambush", False)])

    callout(s, 40, 350, 330, 112, [
        ("ERROR 3 · MALDICIÓN ×3", True), ("apply caso 2", False), ("apply12 caso 1", False), ("apply12 caso 3", False)])
    callout(s, 400, 350, 330, 112, [
        ("ERROR 4 · FURIA ×4", True), ("apply caso 4 · apply12 casos 7 y 12", False), ("RunEvents (santuario)", False)])
    callout(s, 760, 350, 380, 112, [
        ("ERRORES 6-7-8 · duplicados", True), ("curar: inline vs _heal_full()", False),
        ("oro: inline vs _add_gold()", False), ("regalo: copiado en 2 sitios", False)])

    # flechas rojas
    s.line(440, ys[0] - 4, 520, 131, stroke=RED, marker="arrowred")
    s.line(440, ys[1] - 4, 520, 211, stroke=RED, marker="arrowred")
    s.line(440, ys[2] - 4, 520, 291, stroke=RED, marker="arrowred")
    s.line(250, 90 + h, 205, 350, stroke=RED, dash="5 4", marker="arrowred")
    s.line(330, 90 + h, 520, 350, stroke=RED, dash="5 4", marker="arrowred")
    s.line(980, 90 + 100, 640, 350, stroke=RED, dash="5 4", marker="arrowred")

    # Consecuencia
    s.rect(40, 500, 1100, 110, fill=BOX, stroke=RED, rx=10)
    s.text(60, 530, "Consecuencia", 16, RED, "bold", family="Segoe UI, Arial, sans-serif")
    msgs = [
        "• Añadir un resultado nuevo obliga a editar FateDice (viola Abierto/Cerrado).",
        "• Un arreglo de «furia» hay que repetirlo en 4 sitios: si se olvida uno, los dados se comportan distinto.",
        "• Dos tablas paralelas (OUTCOMES/OUTCOMES12 y apply/apply12) que deben mantenerse sincronizadas a mano.",
    ]
    for i, m in enumerate(msgs):
        s.text(60, 556 + i * 20, m, 13, TEXT)
    return s.render()


# ───────────────────────────── DESPUÉS ─────────────────────────────
CONCRETES = [
    ("CurseOutcome", "−25% daño/vel"),
    ("FuryOutcome", "furia · bendición · jackpot"),
    ("HealFullOutcome", "vida completa"),
    ("GoldOutcome", "oro (superv.)"),
    ("DungeonGoldOutcome", "oro (mazmorra)"),
    ("AmbushSurvivalOutcome", "anillo de enemigos"),
    ("AmbushDungeonOutcome", "goblins en caverna"),
    ("QueueEliteOutcome", "élite en cola"),
    ("WoundOutcome", "pierde 40% vida"),
    ("MapGiftOutcome", "2 objetos del mapa"),
    ("EquipmentDropOutcome", "pieza de equipo"),
    ("ChestRewardOutcome", "botín de cofre"),
    ("XpRainOutcome", "lluvia de XP"),
]


def build_after():
    s = Svg(1480, 780)
    s.text(740, 34, "DESPUÉS — Strategy: el dado solo elige y ejecuta una FateOutcome", 22, GREEN, "bold", anchor="middle", family="Segoe UI, Arial, sans-serif")

    # Context
    class_box(s, 40, 80, 330, "FateDice", [
        ("+ apply(v, p, scene, at)", GREEN),
        ("+ apply12(v, p, scene, at)", GREEN),
        ("+ roll() / _resolve()", None),
        ("+ add_mod() / stat_total()", None),
    ], stereotype="Context", stroke=GREEN, title_fill=GREEN)

    # FateContext
    class_box(s, 40, 260, 330, "FateContext", [
        ("+ player, scene, at", None),
        ("+ survival, enc, events", None),
        ("+ luck, col", None),
        ("+ make(p, scene, at, col)", None),
    ], stereotype="datos de la tirada")

    # Registro
    class_box(s, 460, 80, 360, "FateOutcomes", [
        ("+ table(faces, survival)", GREEN),
        ("- _build_d6_dungeon()", None),
        ("- _build_d6_survival()", None),
        ("- _build_d12()", None),
    ], stereotype="registro: valor → estrategia")

    # Strategy interface
    class_box(s, 940, 80, 320, "FateOutcome", [("+ apply(ctx: FateContext)", GREEN)],
              stereotype="Strategy (interfaz)", stroke=GREEN, title_fill=GREEN)

    # conexiones superiores
    s.line(370, 135, 460, 135, marker="arrow")                 # FateDice -> registro
    s.text(415, 126, "usa", 11, MUTED, anchor="middle")
    s.line(205, 80 + 164, 205, 260, marker="arrow", dash="5 4")  # FateDice -> contexto
    s.text(215, 250, "crea", 11, MUTED)
    s.line(820, 135, 940, 135, marker="arrow")                 # registro -> interfaz
    s.text(880, 126, "devuelve", 11, MUTED, anchor="middle")

    # Concretas: 2 filas de 7/6 cajas
    bw, bh, gap = 200, 54, 12
    per_row = 7
    x0, y0 = 40, 470
    base_cx, base_bottom = 1100, 80 + 84
    for i, (name, sub) in enumerate(CONCRETES):
        r, c = divmod(i, per_row)
        x = x0 + c * (bw + gap)
        y = y0 + r * (bh + 36)
        s.rect(x, y, bw, bh, fill=GREEN_BG, stroke=GREEN, rx=8)
        s.text(x + bw / 2, y + 22, name, 12, TEXT, "bold", anchor="middle")
        s.text(x + bw / 2, y + 41, sub, 11, MUTED, anchor="middle")
        s.line(x + bw / 2, y, base_cx, 440, stroke=GREEN, sw=1)

    # Línea madre de herencia: bus horizontal hasta el triángulo
    s.line(base_cx, 440, base_cx, base_bottom, stroke=GREEN, sw=2, marker="tri")
    s.text(base_cx + 12, 330, "«extends»  (herencia)", 12, GREEN)

    # Composite
    cy = y0 + 2 * (bh + 36)
    s.rect(40, cy, 420, 80, fill=BOX, stroke=GOLD, rx=10)
    s.text(60, cy + 26, "CompositeOutcome", 14, GOLD, "bold")
    s.text(60, cy + 48, "parts: Array[FateOutcome]  → apply() recorre las partes", 12, TEXT)
    s.text(60, cy + 66, "d12[1] catástrofe · d12[11] bendición · d12[12] jackpot", 12, MUTED)
    s.line(250, cy, 250, cy - 36, stroke=GOLD, marker="diamond", dash="4 3")
    s.text(262, cy - 14, "contiene 1..n estrategias", 11, GOLD)

    # RunEvents reutiliza
    s.rect(520, cy, 420, 80, fill=BOX, stroke=BOX_STROKE, rx=10)
    s.text(540, cy + 26, "RunEvents (santuario de furia)", 14, TEXT, "bold")
    s.text(540, cy + 48, "FateOutcomes.FuryOutcome.stack(…)", 12, GREEN)
    s.text(540, cy + 66, "reutiliza la furia del dado (antes: copia 4 de 4)", 12, MUTED)

    # Resultado
    s.rect(980, cy, 460, 80, fill=GREEN_BG, stroke=GREEN, rx=10)
    s.text(1000, cy + 26, "Beneficios", 14, GREEN, "bold", family="Segoe UI, Arial, sans-serif")
    s.text(1000, cy + 48, "• Resultado nuevo = clase nueva, FateDice no cambia", 12, TEXT)
    s.text(1000, cy + 66, "• Maldición/furia/curar/oro: 1 sola copia cada una", 12, TEXT)
    return s.render()


# ───────────────────────────── código en HTML ─────────────────────────────
def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n").split("\n")


def code_block(lines, classify):
    out = []
    for i, ln in enumerate(lines, 1):
        cls = classify(i, ln)
        out.append(f'<div class="ln {cls}"><span class="n">{i}</span><span class="c">{esc(ln) or "&nbsp;"}</span></div>')
    return "".join(out)


def classify_before(lines):
    region = {"on": False}

    def f(i, ln):
        if re.search(r"⚠ ERROR \d+:", ln) and ln.lstrip().startswith("#") and ln.startswith("#"):
            region["on"] = True
            return "err-head"
        if "⚠ FIN" in ln:
            region["on"] = False
            return "err-head"
        if "⚠ ERROR" in ln:
            return "err-head"
        return "err-body" if region["on"] else ""
    return f


def classify_after(i, ln):
    if re.search(r"CORRIGE|CORRECCIÓN|PATRÓN STRATEGY|ANTES|AHORA", ln):
        return "fix-head"
    return ""


def apply_section():
    src = read("scripts/objects/fate_dice.gd")
    start = next(i for i, l in enumerate(src) if l.startswith("## Aplica el resultado `v` (pública"))
    end = next(i for i, l in enumerate(src) if l.startswith("static func _floor"))
    a = src[start:end]
    start2 = next(i for i, l in enumerate(src) if "resultados del dado de 12" in l)
    end2 = next((i for i, l in enumerate(src[start2:], start2) if "mejoras y castigos temporales" in l), len(src))
    return a + [""] + src[start2:end2]


def build_html(svg_b, svg_a):
    before = read("docs/strategy/ANTES_fate_dice.gd.txt")
    after_fd = apply_section()
    after_out = read("scripts/patterns/strategy/fate_outcomes.gd")
    ctx_lines = read("scripts/patterns/strategy/fate_outcome.gd")
    css = f"""
body{{background:{BG};color:{TEXT};font-family:'Segoe UI',Arial,sans-serif;margin:0;padding:24px 32px}}
h1{{margin:0 0 4px}} h2{{margin:32px 0 8px}} p.sub{{color:{MUTED};margin:0 0 16px}}
.diagram{{overflow:auto;border:1px solid {BOX_STROKE};border-radius:10px;background:{BG}}}
.diagram svg{{display:block;max-width:100%;height:auto}}
.code{{font-family:Consolas,'Courier New',monospace;font-size:13px;background:#0e0b17;border:1px solid {BOX_STROKE};
 border-radius:10px;max-height:560px;overflow:auto;padding:8px 0}}
.ln{{display:flex;white-space:pre;padding:0 12px;line-height:1.45}} .n{{color:#5d5480;width:44px;flex:none;text-align:right;padding-right:12px;user-select:none}}
.err-head{{background:{RED_BG};color:{RED};font-weight:bold}} .err-body{{background:#2a1018}}
.fix-head{{background:{GREEN_BG};color:{GREEN};font-weight:bold}}
.legend span{{display:inline-block;padding:2px 10px;border-radius:6px;margin-right:10px;font-size:13px}}
.grid{{display:grid;grid-template-columns:1fr 1fr;gap:16px}} @media(max-width:1100px){{.grid{{grid-template-columns:1fr}}}}
"""
    def sect(title, sub, body):
        return f"<h2>{title}</h2><p class='sub'>{sub}</p>{body}"
    legend = (f"<div class='legend'><span style='background:{RED_BG};color:{RED}'>rojo = error / problema</span>"
              f"<span style='background:#2a1018'>zona con problema</span>"
              f"<span style='background:{GREEN_BG};color:{GREEN}'>verde = comentario de corrección</span></div>")
    return f"""<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Strategy en FateDice — antes y después</title>
<style>{css}</style></head><body>
<h1>Strategy aplicado a FateDice</h1>
<p class="sub">Dado del destino de Rumbang: de dos <code>match</code> gigantes a una estrategia por resultado.</p>
{legend}
{sect("1 · Diagrama ANTES", "Un solo método por dado con todo el comportamiento y código copiado.", f"<div class='diagram'>{svg_b}</div>")}
{sect("2 · Código ANTES (con los errores marcados)", "Fuente: docs/strategy/ANTES_fate_dice.gd.txt", f"<div class='code'>{code_block(before, classify_before(before))}</div>")}
{sect("3 · Diagrama DESPUÉS", "FateDice (Context) → FateOutcomes (registro) → FateOutcome (Strategy) → estrategias concretas.", f"<div class='diagram'>{svg_a}</div>")}
<div class="grid">
<div>{sect("4 · Código DESPUÉS: FateDice", "scripts/objects/fate_dice.gd — apply y apply12 con comentarios de corrección", f"<div class='code'>{code_block(after_fd, classify_after)}</div>")}</div>
<div>{sect("5 · Código DESPUÉS: estrategias", "scripts/patterns/strategy/fate_outcomes.gd", f"<div class='code'>{code_block(after_out, classify_after)}</div>")}</div>
</div>
{sect("6 · La interfaz Strategy", "scripts/patterns/strategy/fate_outcome.gd", f"<div class='code'>{code_block(ctx_lines, classify_after)}</div>")}
</body></html>"""


def main():
    os.makedirs(OUT, exist_ok=True)
    svg_b = build_before()
    svg_a = build_after()
    for name, content in (("diagrama_antes.svg", svg_b), ("diagrama_despues.svg", svg_a)):
        with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
    with open(os.path.join(OUT, "strategy_fatedice.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(build_html(svg_b, svg_a))
    print("OK ->", OUT)
    for n in ("diagrama_antes.svg", "diagrama_despues.svg", "strategy_fatedice.html"):
        print("  ", n)


if __name__ == "__main__":
    main()
