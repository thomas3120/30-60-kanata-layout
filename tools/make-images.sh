#!/usr/bin/env bash
#
# make-images.sh - Generates the layer diagrams for README.md from kanata.kbd.
#
# Reads kanata.kbd (defsrc, deflayer, defalias, deftemplate, defchordsv2) and writes:
#   images/layer-<name>.svg   one image per layer (light and dark theme)
#   images/chords.svg         the chord (combo) map
#   images/legend.svg         the colour legend
# and updates the "Text version" blocks in README.md between the
# <!-- text:<name> --> and <!-- /text:<name> --> markers.
#
# Usage (from the project folder):
#   bash tools/make-images.sh [-c kanata.kbd] [-o images] [-r README.md]
#
# Needs only bash and a POSIX awk (gawk, mawk, BSD/macOS awk or busybox awk).
# A PowerShell version with identical output is in tools/make-images.ps1.
#
# What is not in kanata.kbd, and so lives in this script:
#   - WIDTHS: the physical key widths of each defsrc row
#   - KEYNAMES / actions in label(): the labels shown for key names and actions
# Unknown keys or actions are shown with their raw name and a warning.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$DIR/../kanata.kbd"
OUTDIR="$DIR/../images"
README="$DIR/../README.md"

while getopts "c:o:r:h" opt; do
  case "$opt" in
    c) CONFIG="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    r) README="$OPTARG" ;;
    *) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
  esac
done

[ -f "$CONFIG" ] || { echo "Config not found: $CONFIG" >&2; exit 1; }
mkdir -p "$OUTDIR"
README_TMP=""
if [ -f "$README" ]; then README_TMP="$README.tmp.$$"; trap 'rm -f "$README_TMP"' EXIT; fi

read -r -d '' PROG <<'AWK' || true
# ======================================================================
#  Configuration that is not in kanata.kbd
# ======================================================================
function setup(   i, n, kv, p) {
  # Key widths in units for each defsrc row (60% layout with split thumb row).
  NWR = split("1 1 1 1 1 1 1 1 1 1 1 1 1 2|1.5 1 1 1 1 1 1 1 1 1 1 1 1 1.5|1.75 1 1 1 1 1 1 1 1 1 1 1 2.25|2.25 1 1 1 1 1 1 1 1 1 1 2.75|1.25 1.25 1.25 3 3.25 1.25 1.25 1.25 1.25", WROWS, "|")
  for (i = 1; i <= NWR; i++) WCNT[i - 1] = split(WROWS[i], tmp, " ") + 0
  for (i = 1; i <= NWR; i++) { n = split(WROWS[i], tmp, " "); for (p = 1; p <= n; p++) WID[i - 1, p - 1] = tmp[p] + 0 }

  # defsrc rows/columns used for the chord image (rows 2-4, columns 2-11 = the letters).
  CHORD_NROWS = 3; CHORD_ROW[0] = 1; CHORD_ROW[1] = 2; CHORD_ROW[2] = 3
  CHORD_COL0 = 1; CHORD_COLS = 10
  STAGGER[0] = 0; STAGGER[1] = 0.25; STAGGER[2] = 0.75

  # Labels for kanata key names. Letters, digits, f1-f24 and kp* are derived automatically.
  n = split("esc=Esc tab=Tab caps=Caps bspc=Bspc ret=Enter enter=Enter spc=Space grv=` lsft=Shift rsft=Shift lctl=Ctrl rctl=Ctrl lalt=Alt ralt=RAlt lmet=Win rmet=Win menu=Menu del=Del ins=Ins home=Home end=End pgup=PgUp pgdn=PgDn left=Left rght=Right right=Right up=Up down=Down prnt=PrtSc slck=ScrLk brk=Pause pause=Pause mute=Mute vold=Vol- volu=Vol+ pp=Play next=Next prev=Prev hmpg=BHome bck=BBack fwd=BFwd mlft=LClk mrgt=RClk mmid=MMid lrld=Reload nlck=NumLk", kv, " ")
  for (i = 1; i <= n; i++) { p = index(kv[i], "="); KEYNAMES[substr(kv[i], 1, p - 1)] = substr(kv[i], p + 1) }

  # US layout: what Shift + key types (for chords like S-9).
  n = split("1 ! 2 @ 3 # 4 $ 5 % 6 ^ 7 & 8 * 9 ( 0 ) - _ = + [ { ] } ; : , < . > / ? grv ~", kv, " ")
  for (i = 1; i < n; i += 2) SHIFTED[kv[i]] = kv[i + 1]
  SHIFTED["\\"] = "|"; SHIFTED["'"] = "\""

  n = split("Win Alt Ctrl Shift RAlt Menu Caps OSS", kv, " "); for (i = 1; i <= n; i++) ISMOD[kv[i]] = 1
  PRETTY["Left"] = "←"; PRETTY["Up"] = "↑"; PRETTY["Right"] = "→"; PRETTY["Down"] = "↓"; PRETTY["Vol-"] = "Vol−"
  CROSS = "×"

  CSS = "<style>\n" \
    "  .case { fill: #f6f8fa; stroke: #d0d7de; }\n" \
    "  .k    { fill: #ffffff; stroke: #c4cbd3; }\n" \
    "  .k.mod   { fill: #e7f0ff; stroke: #9dbcf2; }\n" \
    "  .k.layer { fill: #fff2e2; stroke: #f0b77a; }\n" \
    "  .k.held  { fill: #ffd8a8; stroke: #e8590c; stroke-width: 1.6; }\n" \
    "  .k.trans { fill: #f1f3f5; stroke: #d8dde3; stroke-dasharray: 3 3; }\n" \
    "  .k.off   { fill: #eceef1; stroke: #d8dde3; }\n" \
    "  .t    { fill: #1f2328; font: 600 13px system-ui, -apple-system, \"Segoe UI\", Helvetica, Arial, sans-serif; }\n" \
    "  .t.mod   { fill: #1a4fb5; }\n" \
    "  .t.layer { fill: #9a4b00; }\n" \
    "  .t.held  { fill: #8a3200; }\n" \
    "  .t.off   { fill: #9aa3ad; font-weight: 400; }\n" \
    "  .h    { font: 500 10px system-ui, -apple-system, \"Segoe UI\", Helvetica, Arial, sans-serif; }\n" \
    "  .h.mod   { fill: #2f6fdf; }\n" \
    "  .h.layer { fill: #c05f00; }\n" \
    "  .cap  { fill: #57606a; font: 400 11px system-ui, -apple-system, \"Segoe UI\", Helvetica, Arial, sans-serif; }\n" \
    "  .bub  { fill: #6e40c9; }\n" \
    "  .bt   { fill: #ffffff; font: 700 13px ui-monospace, \"Cascadia Mono\", Consolas, Menlo, monospace; }\n" \
    "  @media (prefers-color-scheme: dark) {\n" \
    "    .case { fill: #161b22; stroke: #30363d; }\n" \
    "    .k    { fill: #2d333b; stroke: #444c56; }\n" \
    "    .k.mod   { fill: #1c2d4d; stroke: #3d5f9c; }\n" \
    "    .k.layer { fill: #3b2a15; stroke: #8a5a24; }\n" \
    "    .k.held  { fill: #5c3410; stroke: #ff922b; }\n" \
    "    .k.trans { fill: #1c2128; stroke: #373e47; }\n" \
    "    .k.off   { fill: #1c2128; stroke: #373e47; }\n" \
    "    .t    { fill: #e6edf3; }\n" \
    "    .t.mod   { fill: #9cc1ff; }\n" \
    "    .t.layer { fill: #ffb366; }\n" \
    "    .t.held  { fill: #ffd8a8; }\n" \
    "    .t.off   { fill: #6e7681; }\n" \
    "    .h.mod   { fill: #7fadff; }\n" \
    "    .h.layer { fill: #ffa94d; }\n" \
    "    .cap  { fill: #8b949e; }\n" \
    "    .bub  { fill: #8957e5; }\n" \
    "  }\n" \
    "</style>"

  U = 46; GAP = 4; KH = 46; PITCH = 50; M = 10
}

# ======================================================================
#  Reading kanata.kbd
# ======================================================================
function warn(msg) { if (!(msg in WARNED)) { WARNED[msg] = 1; print "WARNING: " msg > "/dev/stderr" } }

# Collect tokens line by line, skipping ;; comments and #| ... |# blocks.
{
  line = $0; sub(/\r$/, "", line); out = ""
  while (line != "") {
    if (INBLOCK) {
      p = index(line, "|#"); if (!p) { line = ""; break }
      line = substr(line, p + 2); INBLOCK = 0; continue
    }
    p = index(line, "#|"); c = index(line, ";;")
    if (c && (!p || c < p)) { out = out substr(line, 1, c - 1); line = ""; break }
    if (p) { out = out substr(line, 1, p - 1) " "; line = substr(line, p + 2); INBLOCK = 1; continue }
    out = out line; line = ""
  }
  while (match(out, /[()]|[^ \t()]+/)) {
    NTOK++; TOK[NTOK] = substr(out, RSTART, RLENGTH); TLINE[NTOK] = NR
    out = substr(out, RSTART + RLENGTH)
  }
}

# Parse tokens into nodes: NT = "A" (atom) or "L" (list), NV = atom text,
# NC = number of children, CH[id, i] = child, NL = source line.
function parse(   id, t, c) {
  t = TOK[POS]; id = ++NN; NL[id] = TLINE[POS]; POS++
  if (t != "(") { NT[id] = "A"; NV[id] = t; return id }
  NT[id] = "L"; NC[id] = 0
  while (POS <= NTOK && TOK[POS] != ")") { c = parse(); CH[id, NC[id]] = c; NC[id]++ }
  POS++
  return id
}
function head(id) { return (NT[id] == "L" && NC[id] > 0 && NT[CH[id, 0]] == "A") ? NV[CH[id, 0]] : "" }

# Store the atoms of a defsrc/deflayer as rows, grouped by source line.
function rows(name, id, start,   i, r, c, last) {
  r = -1; last = -1
  for (i = start; i < NC[id]; i++) {
    if (NL[CH[id, i]] != last) { r++; c = 0; RC[name, r] = 0 }
    ROW[name, r, RC[name, r]] = NV[CH[id, i]]; RC[name, r]++
    last = NL[CH[id, i]]
  }
  RN[name] = r + 1
}

function clone(id,   n, i) {
  n = ++NN; NT[n] = NT[id]; NL[n] = NL[id]
  if (NT[id] == "A") { NV[n] = (NV[id] in SUBST) ? SUBST[NV[id]] : NV[id]; return n }
  NC[n] = NC[id]
  for (i = 0; i < NC[id]; i++) CH[n, i] = clone(CH[id, i])
  return n
}

# ======================================================================
#  Turning actions into labels: label() sets LT (tap) and LH (hold)
# ======================================================================
function keylabel(k) {
  if (k in KEYNAMES) return KEYNAMES[k]
  if (k ~ /^[a-z]$/) return toupper(k)
  if (k ~ /^(f[0-9]+|kp.+)$/) return toupper(k)
  if (length(k) == 1) return k
  warn("No label for key '" k "'; add it to KEYNAMES")
  return k
}
function dirsuffix(h, prefix,   d) {
  d = substr(h, length(prefix) + 1)
  if (d == "left") return "L"; if (d == "right") return "R"
  if (d == "up") return "U"; if (d == "down") return "D"
  return ""
}
function labelatom(a,   name) {
  if (a == "_") { LT = "--"; LH = ""; return }
  if (a == "XX") { LT = "XX"; LH = ""; return }
  if (substr(a, 1, 1) == "@") {
    name = substr(a, 2)
    if (!(name in ALIAS)) { warn("Unknown alias '" a "'"); LT = a; LH = ""; return }
    label(ALIAS[name]); return
  }
  LT = keylabel(a); LH = ""
}
function label(id,   h, t, hl, steps, i, tpl, m, d, n, pfx, np, k) {
  if (NT[id] == "A") { labelatom(NV[id]); return }
  h = head(id)
  if (h ~ /^tap-hold/) { label(CH[id, 3]); t = LT; hl = holdlabel(CH[id, 4]); LT = t; LH = hl; return }
  if (h == "layer-toggle" || h == "layer-while-held" || h == "layer-switch") { LT = ""; LH = TITLE[NV[CH[id, 1]]]; return }
  if (h ~ /^tap-dance/) {
    steps = CH[id, 2]
    label(CH[steps, 0])
    for (i = 0; i < NC[steps]; i++) if (NT[CH[steps, i]] == "A" && NV[CH[steps, i]] == "lrld") { LT = LT "*"; break }
    return
  }
  if (h ~ /^one-shot/) { m = holdlabel(CH[id, 2]); LT = (m == "Shift") ? "OSS" : "OS " m; LH = ""; return }
  if (h == "t!") {
    k = NV[CH[id, 1]]
    if (!(k in TPL)) { warn("Unknown template '" k "'"); LT = h; LH = ""; return }
    split("", SUBST)
    for (i = 0; i < TPLN[k]; i++) SUBST["$" TPLP[k, i]] = NV[CH[id, i + 2]]
    label(clone(TPL[k])); return
  }
  if (h == "macro") { label(CH[id, 1]); return }
  if (h == "unicode") { LT = NV[CH[id, 1]]; LH = ""; return }
  np = split("mwheel-accel-=Wh movemouse-accel-=Ms mwheel-=Wh movemouse-=Sl", pfx, " ")
  for (i = 1; i <= np; i++) {
    n = index(pfx[i], "="); k = substr(pfx[i], 1, n - 1)
    if (substr(h, 1, length(k)) == k) { d = dirsuffix(h, k); if (d != "") { LT = substr(pfx[i], n + 1) d; LH = ""; return } }
  }
  if (h == "setmouse") { LT = "Ctr"; LH = ""; return }
  if (h == "movemouse-speed") { LT = "Fast"; LH = ""; return }
  if (h == "caps-word") { LT = "CapsW"; LH = ""; return }
  warn("No label for action '" h "'; add it to label()")
  LT = h; LH = ""
}
function holdlabel(id) {
  # A one-shot modifier used as a hold action acts as the plain modifier.
  if (head(id) ~ /^one-shot/) return holdlabel(CH[id, 2])
  label(id)
  return (LH != "") ? LH : LT
}
function cellof(a) { labelatom(a); return (LH != "") ? LT "|" LH : LT }

# ======================================================================
#  Drawing
# ======================================================================
function N(v,   s) { s = sprintf("%.2f", v); sub(/0+$/, "", s); sub(/\.$/, "", s); if (s == "-0") s = "0"; return s }
function X(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }

function key(x, y, w, h, cell,   p, tap, hold, cls, s, cx, hc) {
  p = index(cell, "|")
  if (p) { tap = substr(cell, 1, p - 1); hold = substr(cell, p + 1) } else { tap = cell; hold = "" }
  cls = ""
  if (tap == "--") { cls = "trans"; tap = "" }
  else if (tap == "XX") { cls = "off"; tap = CROSS }
  else if (tap == "held") cls = "held"
  else if (hold in ISLAYER) cls = "layer"
  else if (tap in ISMOD) cls = "mod"
  if (tap in PRETTY) tap = PRETTY[tap]
  s = sprintf("<rect class=\"k %s\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"6\"/>", cls, N(x), N(y), N(w), N(h))
  cx = x + w / 2
  if (hold != "") {
    hc = (hold in ISLAYER) ? "layer" : "mod"
    if (tap != "") s = s sprintf("<text class=\"t %s\" x=\"%s\" y=\"%s\" text-anchor=\"middle\">%s</text>", cls, N(cx), N(y + 20), X(tap))
    s = s sprintf("<text class=\"h %s\" x=\"%s\" y=\"%s\" text-anchor=\"middle\">%s</text>", hc, N(cx), N(y + h - 8), X(hold))
  } else if (tap != "") {
    s = s sprintf("<text class=\"t %s\" x=\"%s\" y=\"%s\" text-anchor=\"middle\">%s</text>", cls, N(cx), N(y + h / 2 + 5), X(tap))
  }
  return s
}
function svgstart(w, h, title) {
  return sprintf("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %s %s\" width=\"%s\" height=\"%s\" role=\"img\" aria-label=\"%s\"><title>%s</title>", N(w), N(h), N(w), N(h), X(title), X(title)) \
    CSS sprintf("<rect class=\"case\" x=\"0.5\" y=\"0.5\" width=\"%s\" height=\"%s\" rx=\"12\"/>", N(w - 1), N(h - 1))
}
function writefile(path, s) { printf "%s", s > path; close(path) }
function border(n,   s, i) { s = "+"; for (i = 0; i < n; i++) s = s "-------+"; return s }

# Text version of a layer: a boxed ASCII grid, tap on the first line, hold on the second.
function grid(name,   r, c, n, prev, s, l1, l2, cell, p, tap, hold) {
  s = ""; prev = 0
  for (r = 0; r < RN[name]; r++) {
    n = RC[name, r]
    s = s border(n > prev ? n : prev) "\n"
    l1 = "|"; l2 = "|"
    for (c = 0; c < n; c++) {
      cell = CELL[name, r, c]; p = index(cell, "|")
      if (p) { tap = substr(cell, 1, p - 1); hold = substr(cell, p + 1) } else { tap = cell; hold = "" }
      l1 = l1 sprintf("%-7s|", " " tap); l2 = l2 sprintf("%-7s|", " " hold)
    }
    s = s l1 "\n" l2 "\n"; prev = n
  }
  return s border(prev)
}

# ======================================================================
#  Main
# ======================================================================
END {
  setup()
  POS = 1; NCD = 0; NLAY = 0
  while (POS <= NTOK) { f = parse(); FORMS[++NF_] = f }
  for (i = 1; i <= NF_; i++) {
    f = FORMS[i]; h = head(f)
    if (h == "defsrc") { rows("__src", f, 1); HAVESRC = 1 }
    else if (h == "deflayer") { n = NV[CH[f, 1]]; LORD[NLAY++] = n; rows(n, f, 2) }
    else if (h == "defalias") { for (j = 1; j + 1 < NC[f]; j += 2) ALIAS[NV[CH[f, j]]] = CH[f, j + 1] }
    else if (h == "deftemplate") {
      n = NV[CH[f, 1]]; TPL[n] = CH[f, 3]; p = CH[f, 2]; TPLN[n] = NC[p]
      for (j = 0; j < NC[p]; j++) TPLP[n, j] = NV[CH[p, j]]
    }
    else if (h == "defchordsv2") { for (j = 1; j + 1 < NC[f]; j += 5) { CKEYS[NCD] = CH[f, j]; COUT[NCD] = CH[f, j + 1]; NCD++ } }
  }
  if (!HAVESRC) { print "No defsrc found in " CONFIG > "/dev/stderr"; exit 1 }
  for (i = 0; i < NLAY; i++) { n = LORD[i]; TITLE[n] = toupper(substr(n, 1, 1)) substr(n, 2); ISLAYER[TITLE[n]] = 1 }

  # Cells for each layer, marking the thumb key held to reach it.
  base = LORD[0]
  for (i = 0; i < NLAY; i++) {
    n = LORD[i]
    for (r = 0; r < RN[n]; r++) for (c = 0; c < RC[n, r]; c++) {
      cell = cellof(ROW[n, r, c])
      if (n != base && cell == "--") { labelatom(ROW[base, r, c]); if (LH == TITLE[n]) cell = "held" }
      CELL[n, r, c] = cell
    }
  }

  # Layer images.
  W = 15 * U - GAP + 2 * M; H = 5 * PITCH - (PITCH - KH) + 2 * M
  for (i = 0; i < NLAY; i++) {
    n = LORD[i]
    if (RN[n] != NWR) warn("Layer '" n "' has " RN[n] " rows, expected " NWR)
    s = svgstart(W, H, TITLE[n] " layer")
    for (r = 0; r < RN[n]; r++) {
      if (RC[n, r] != WCNT[r]) warn("Layer '" n "' row " (r + 1) " has " RC[n, r] " keys, expected " WCNT[r])
      x = M; y = M + r * PITCH
      for (c = 0; c < RC[n, r]; c++) { w = WID[r, c] * U; s = s key(x, y, w - GAP, KH, CELL[n, r, c]); x += w }
    }
    writefile(OUTDIR "/layer-" n ".svg", s "</svg>")
  }

  # Chords: place each chord between two neighbouring letter keys.
  for (ci = 0; ci < CHORD_NROWS; ci++) for (c = 0; c < CHORD_COLS - 1; c++) CSYM[ci, c] = ""
  for (d = 0; d < NCD; d++) {
    kn = CKEYS[d]; o = COUT[d]; placed = 0
    if (NT[o] == "A" && substr(NV[o], 1, 2) == "S-") sym = SHIFTED[substr(NV[o], 3)]
    else { label(o); sym = LT }
    if (NC[kn] == 2) {
      k1 = NV[CH[kn, 0]]; k2 = NV[CH[kn, 1]]
      for (ci = 0; ci < CHORD_NROWS; ci++) for (c = 0; c < CHORD_COLS - 1; c++) {
        a = ROW["__src", CHORD_ROW[ci], CHORD_COL0 + c]; b = ROW["__src", CHORD_ROW[ci], CHORD_COL0 + c + 1]
        if ((k1 == a && k2 == b) || (k1 == b && k2 == a)) { CSYM[ci, c] = sym; placed = 1 }
      }
    }
    if (!placed) {
      ks = ""; for (j = 0; j < NC[kn]; j++) ks = ks (j ? " " : "") NV[CH[kn, j]]
      warn("Chord (" ks ") is not two neighbouring letter keys; left out of the image")
    }
  }
  CU = 60; CK = 44
  W = int(10.75 * CU - (CU - CK) + 2 * M + 4); H = 3 * CU - (CU - CK) + 2 * M
  s = svgstart(W, H, "Chords: press two neighbouring keys together")
  for (ci = 0; ci < CHORD_NROWS; ci++) {
    y = M + ci * CU
    for (c = 0; c < CHORD_COLS; c++) s = s key(M + (STAGGER[ci] + c) * CU, y, CK, CK, keylabel(ROW["__src", CHORD_ROW[ci], CHORD_COL0 + c]))
    for (c = 0; c < CHORD_COLS - 1; c++) {
      sym = CSYM[ci, c]; if (sym == "") continue
      cx = M + (STAGGER[ci] + c + 1) * CU - (CU - CK) / 2; cy = y + CK / 2
      s = s sprintf("<circle class=\"bub\" cx=\"%s\" cy=\"%s\" r=\"12\"/>", N(cx), N(cy))
      s = s sprintf("<text class=\"bt\" x=\"%s\" y=\"%s\" text-anchor=\"middle\">%s</text>", N(cx), N(cy + 4.5), X(sym))
    }
  }
  writefile(OUTDIR "/chords.svg", s "</svg>")

  # Legend image.
  NIT = split("A|Win;Tap / hold;Ctrl;Modifier;Space|Nav;Layer key;held;Held thumb key;--;Same as base;XX;Disabled", it, ";") / 2
  IW = 112; W = NIT * IW + 2 * M - 8; H = 46 + 22 + 2 * M
  s = svgstart(W, H, "Legend for the layer diagrams")
  for (i = 0; i < NIT; i++) {
    x = M + i * IW + (IW - 8 - 62) / 2
    s = s key(x, M, 62, 46, it[2 * i + 1])
    s = s sprintf("<text class=\"cap\" x=\"%s\" y=\"%s\" text-anchor=\"middle\">%s</text>", N(x + 31), N(M + 46 + 16), X(it[2 * i + 2]))
  }
  writefile(OUTDIR "/legend.svg", s "</svg>")

  # Text versions in README.md.
  if (READMEOUT != "") {
    nl = "\n"; nlines = 0
    while ((getline ln < README) > 0) { RL[++nlines] = ln; if (ln ~ /\r$/) nl = "\r\n" }
    close(README)
    for (i = 0; i < NLAY; i++) FOUND[LORD[i]] = 0
    out = ""; skip = ""
    for (j = 1; j <= nlines; j++) {
      ln = RL[j]; sub(/\r$/, "", ln)
      if (skip != "") { if (index(ln, "<!-- /text:" skip " -->")) skip = ""; continue }
      for (i = 0; i < NLAY; i++) {
        n = LORD[i]
        if (index(ln, "<!-- text:" n " -->")) {
          g = "<!-- text:" n " -->\n```\n" grid(n) "\n```\n<!-- /text:" n " -->"
          gsub(/\n/, nl, g); out = out g nl; FOUND[n] = 1; skip = n; break
        }
      }
      if (skip == "") out = out ln nl
    }
    for (i = 0; i < NLAY; i++) if (!FOUND[LORD[i]]) warn("No text:" LORD[i] " markers found in README.md (layer '" LORD[i] "' has no text version)")
    printf "%s", out > READMEOUT; close(READMEOUT)
  }
  layers = ""; for (i = 0; i < NLAY; i++) layers = layers (i ? ", " : "") LORD[i]
  print "Diagrams for layers " layers " written to " OUTDIR
}
AWK

LC_ALL=C awk -v CONFIG="$CONFIG" -v OUTDIR="$OUTDIR" -v README="$README" -v READMEOUT="$README_TMP" "$PROG" "$CONFIG"

if [ -n "$README_TMP" ]; then mv "$README_TMP" "$README"; fi
