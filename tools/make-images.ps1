<#
  make-images.ps1 - Generates the layer diagrams for README.md from kanata.kbd.

  Reads kanata.kbd (defsrc, deflayer, defalias, deftemplate, defchordsv2) and writes:
    images/layer-<name>.svg   one image per layer (light and dark theme)
    images/chords.svg         the chord (combo) map
    images/legend.svg         the colour legend
  and updates the "Text version" blocks in README.md between the
  <!-- text:<name> --> and <!-- /text:<name> --> markers.

  Usage (from the project folder):
    powershell -ExecutionPolicy Bypass -File tools/make-images.ps1
    pwsh -File tools/make-images.ps1

  A bash version with identical output is in tools/make-images.sh.

  What is not in kanata.kbd, and so lives in this script:
    - $WIDTHS: the physical key widths of each defsrc row
    - $KEYNAMES / $ACTIONS: the labels shown for key names and actions
  Unknown keys or actions are shown with their raw name and a warning.
#>
param(
  [string]$Config = (Join-Path $PSScriptRoot '..\kanata.kbd'),
  [string]$OutDir = (Join-Path $PSScriptRoot '..\images'),
  [string]$Readme = (Join-Path $PSScriptRoot '..\README.md')
)

# Key widths in units for each defsrc row (60% layout with split thumb row).
$WIDTHS = @(
  @(1,1,1,1,1,1,1,1,1,1,1,1,1,2),
  @(1.5,1,1,1,1,1,1,1,1,1,1,1,1,1.5),
  @(1.75,1,1,1,1,1,1,1,1,1,1,1,2.25),
  @(2.25,1,1,1,1,1,1,1,1,1,1,2.75),
  @(1.25,1.25,1.25,2.25,1.5,2.5,1.25,1.25,1.25,1.25)
)
# defsrc rows/columns used for the chord image (rows 2-4, columns 2-11 = the letters).
$CHORD_ROWS = 1, 2, 3; $CHORD_COL0 = 1; $CHORD_COLS = 10
$CHORD_STAGGER = 0, 0.25, 0.75

# Labels for kanata key names. Letters, digits, f1-f24 and kp* are derived automatically.
$KEYNAMES = @{
  esc='Esc'; tab='Tab'; caps='Caps'; bspc='Bspc'; ret='Enter'; enter='Enter'; spc='Space'
  grv='`'; lsft='Shift'; rsft='Shift'; lctl='Ctrl'; rctl='Ctrl'; lalt='Alt'; ralt='RAlt'
  lmet='Win'; rmet='Win'; menu='Menu'; del='Del'; ins='Ins'; home='Home'; end='End'
  pgup='PgUp'; pgdn='PgDn'; left='Left'; rght='Right'; right='Right'; up='Up'; down='Down'
  prnt='PrtSc'; slck='ScrLk'; brk='Pause'; pause='Pause'; mute='Mute'; vold='Vol-'; volu='Vol+'
  pp='Play'; next='Next'; prev='Prev'; hmpg='BHome'; bck='BBack'; fwd='BFwd'
  mlft='LClk'; mrgt='RClk'; mmid='MMid'; lrld='Reload'; nlck='NumLk'
}
# Labels for actions (list head). Directions are appended as L/D/U/R.
$ACTIONS = @{
  'mwheel-accel-' = 'Wh'; 'mwheel-' = 'Wh'; 'movemouse-accel-' = 'Ms'; 'movemouse-' = 'Sl'
  'setmouse' = 'Ctr'; 'movemouse-speed' = 'Fast'; 'caps-word' = 'CapsW'
}
# US layout: what Shift + key types (for chords like S-9).
$SHIFTED = @{ '1'='!'; '2'='@'; '3'='#'; '4'='$'; '5'='%'; '6'='^'; '7'='&'; '8'='*'; '9'='('; '0'=')'
  '-'='_'; '='='+'; '['='{'; ']'='}'; '\'='|'; ';'=':'; "'"='"'; ','='<'; '.'='>'; '/'='?'; 'grv'='~' }

# ---------- reading kanata.kbd ----------
function Read-Kbd([string]$path) {
  $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
  $text = [regex]::Replace($text, '(?s)#\|.*?\|#', { param($m) "`n" * ($m.Value.Split("`n").Count - 1) })
  $tokens = New-Object System.Collections.Generic.List[object]
  $lines = $text.Split("`n")
  for ($ln = 0; $ln -lt $lines.Count; $ln++) {
    $line = $lines[$ln]; $c = $line.IndexOf(';;'); if ($c -ge 0) { $line = $line.Substring(0, $c) }
    foreach ($m in [regex]::Matches($line, '[()]|[^\s()]+')) { $tokens.Add(@{ v = $m.Value; line = $ln }) }
  }
  $script:pos = 0
  $forms = @()
  while ($script:pos -lt $tokens.Count) { $forms += ,(Parse-Node $tokens) }
  $forms
}
function Parse-Node($tokens) {
  $t = $tokens[$script:pos]; $script:pos++
  if ($t.v -ne '(') { return @{ atom = $t.v; line = $t.line } }
  $items = @()
  while ($script:pos -lt $tokens.Count -and $tokens[$script:pos].v -ne ')') { $items += ,(Parse-Node $tokens) }
  $script:pos++
  @{ list = $items; line = $t.line }
}
function Rows($items) {
  # Group the atoms of a defsrc/deflayer by source line.
  $rows = @(); $cur = @(); $last = -1
  foreach ($it in $items) {
    if ($last -ge 0 -and $it.line -ne $last) { $rows += ,$cur; $cur = @() }
    $cur += $it.atom; $last = $it.line
  }
  if ($cur.Count) { $rows += ,$cur }
  $rows
}
function Clone-Sub($node, $map) {
  if ($node.ContainsKey('atom')) { if ($map.ContainsKey($node.atom)) { return @{ atom = $map[$node.atom]; line = $node.line } }; return $node }
  @{ list = @($node.list | ForEach-Object { ,(Clone-Sub $_ $map) }); line = $node.line }
}

$forms = Read-Kbd $Config
$SRC = $null; $LAYER_ORDER = @(); $LAYER_ROWS = @{}; $ALIASES = @{}; $TEMPLATES = @{}; $CHORD_DEFS = @()
foreach ($f in $forms) {
  if (-not $f.ContainsKey('list') -or $f.list.Count -eq 0) { continue }
  $head = $f.list[0].atom; $rest = @($f.list | Select-Object -Skip 1)
  switch ($head) {
    'defsrc'      { $SRC = Rows $rest }
    'deflayer'    { $n = $rest[0].atom; $LAYER_ORDER += $n; $LAYER_ROWS[$n] = Rows @($rest | Select-Object -Skip 1) }
    'defalias'    { for ($i = 0; $i + 1 -lt $rest.Count; $i += 2) { $ALIASES[$rest[$i].atom] = $rest[$i + 1] } }
    'deftemplate' { $TEMPLATES[$rest[0].atom] = @{ params = @($rest[1].list | ForEach-Object { $_.atom }); body = $rest[2] } }
    'defchordsv2' { for ($i = 0; $i + 1 -lt $rest.Count; $i += 5) { $CHORD_DEFS += ,@(@($rest[$i].list | ForEach-Object { $_.atom }), $rest[$i + 1]) } }
  }
}
if (-not $SRC) { throw "No defsrc found in $Config" }
$LAYER_TITLES = @{}; foreach ($n in $LAYER_ORDER) { $LAYER_TITLES[$n] = $n.Substring(0,1).ToUpper() + $n.Substring(1) }

# ---------- turning actions into labels ----------
$WARNED = @{}
function Warn([string]$msg) { if (-not $WARNED.ContainsKey($msg)) { $WARNED[$msg] = 1; Write-Warning $msg } }

function Key-Label([string]$k) {
  if ($KEYNAMES.ContainsKey($k)) { return $KEYNAMES[$k] }
  if ($k -cmatch '^[a-z]$') { return $k.ToUpper() }
  if ($k -match '^(f\d+|kp.+)$') { return $k.ToUpper() }
  if ($k.Length -eq 1) { return $k }
  Warn "No label for key '$k'; add it to `$KEYNAMES"; $k
}
function Dir-Suffix([string]$head, [string]$prefix) {
  switch ($head.Substring($prefix.Length)) { 'left' { 'L' } 'right' { 'R' } 'up' { 'U' } 'down' { 'D' } default { '' } }
}
# Returns @(tap, hold) for a node.
function Label($node) {
  if ($node.ContainsKey('atom')) {
    $a = $node.atom
    if ($a -eq '_') { return '--', '' }
    if ($a -eq 'XX') { return 'XX', '' }
    if ($a.StartsWith('@')) {
      $name = $a.Substring(1)
      if (-not $ALIASES.ContainsKey($name)) { Warn "Unknown alias '$a'"; return $a, '' }
      return Label $ALIASES[$name]
    }
    return (Key-Label $a), ''
  }
  $items = $node.list; $head = $items[0].atom; $args = @($items | Select-Object -Skip 1)
  if ($head -like 'tap-hold*') { $t = Label $args[2]; return $t[0], (Hold-Label $args[3]) }
  if ($head -in 'layer-toggle', 'layer-while-held', 'layer-switch') { return '', $LAYER_TITLES[$args[0].atom] }
  if ($head -like 'tap-dance*') {
    $steps = $args[1].list
    $t = Label $steps[0]
    if ($steps | Where-Object { $_.atom -eq 'lrld' }) { $t = @(($t[0] + '*'), $t[1]) }
    return $t
  }
  if ($head -like 'one-shot*') { $m = Hold-Label $args[1]; if ($m -eq 'Shift') { return 'OSS', '' }; return ('OS ' + $m), '' }
  if ($head -eq 't!') {
    $tpl = $TEMPLATES[$args[0].atom]; if (-not $tpl) { Warn "Unknown template '$($args[0].atom)'"; return $head, '' }
    $map = @{}; for ($i = 0; $i -lt $tpl.params.Count; $i++) { $map['$' + $tpl.params[$i]] = $args[$i + 1].atom }
    return Label (Clone-Sub $tpl.body $map)
  }
  if ($head -eq 'macro') { return Label $args[0] }
  if ($head -eq 'unicode') { return $args[0].atom, '' }
  foreach ($p in 'mwheel-accel-', 'movemouse-accel-', 'mwheel-', 'movemouse-') {
    if ($head.StartsWith($p)) { $d = Dir-Suffix $head $p; if ($d) { return ($ACTIONS[$p] + $d), '' } }
  }
  if ($ACTIONS.ContainsKey($head)) { return $ACTIONS[$head], '' }
  Warn "No label for action '$head'; add it to `$ACTIONS"; $head, ''
}
function Hold-Label($node) {
  # A one-shot modifier used as a hold action acts as the plain modifier.
  if ($node.ContainsKey('list') -and $node.list[0].atom -like 'one-shot*') { return Hold-Label $node.list[2] }
  $l = Label $node
  if ($l[1]) { return $l[1] }
  $l[0]
}
function Cell($node) { $l = Label $node; if ($l[1]) { $l[0] + '|' + $l[1] } else { $l[0] } }

# Build the cell grid for each layer, marking the thumb key held to reach it.
$LAYERS_DATA = [ordered]@{}
$baseName = $LAYER_ORDER[0]
foreach ($n in $LAYER_ORDER) {
  $rows = @()
  for ($r = 0; $r -lt $LAYER_ROWS[$n].Count; $r++) {
    $row = @()
    for ($c = 0; $c -lt $LAYER_ROWS[$n][$r].Count; $c++) {
      $cell = Cell @{ atom = $LAYER_ROWS[$n][$r][$c] }
      if ($n -ne $baseName -and $cell -eq '--') {
        $b = Label @{ atom = $LAYER_ROWS[$baseName][$r][$c] }
        if ($b[1] -eq $LAYER_TITLES[$n]) { $cell = 'held' }
      }
      $row += $cell
    }
    $rows += ,$row
  }
  $LAYERS_DATA[$n] = @{ title = "$($LAYER_TITLES[$n]) layer"; rows = $rows }
}

# Chords: place each chord between two neighbouring letter keys.
$CHORDS = @()
for ($i = 0; $i -lt $CHORD_ROWS.Count; $i++) {
  $r = $CHORD_ROWS[$i]
  $keys = @(); for ($c = 0; $c -lt $CHORD_COLS; $c++) { $keys += Key-Label $SRC[$r][$CHORD_COL0 + $c] }
  $CHORDS += @{ keys = $keys; chords = @('') * ($CHORD_COLS - 1); off = $CHORD_STAGGER[$i] }
}
foreach ($cd in $CHORD_DEFS) {
  $k = $cd[0]; $out = $cd[1]; $placed = $false
  if ($out.ContainsKey('atom') -and $out.atom -match '^S-(.+)$') { $sym = $SHIFTED[$Matches[1]] }
  else { $sym = (Label $out)[0] }
  for ($i = 0; $i -lt $CHORD_ROWS.Count -and $k.Count -eq 2; $i++) {
    for ($c = 0; $c -lt $CHORD_COLS - 1; $c++) {
      $a = $SRC[$CHORD_ROWS[$i]][$CHORD_COL0 + $c]; $b = $SRC[$CHORD_ROWS[$i]][$CHORD_COL0 + $c + 1]
      if (($k[0] -eq $a -and $k[1] -eq $b) -or ($k[0] -eq $b -and $k[1] -eq $a)) { $CHORDS[$i].chords[$c] = $sym; $placed = $true }
    }
  }
  if (-not $placed) { Warn "Chord ($($k -join ' ')) is not two neighbouring letter keys; left out of the image" }
}

# ---------- drawing ----------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$inv = [Globalization.CultureInfo]::InvariantCulture
function N($v) { ([double]$v).ToString('0.##', $inv) }
function X([string]$s) { $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;') }

$MODS   = 'Win','Alt','Ctrl','Shift','RAlt','Menu','Caps','OSS'
$LAYERS = @($LAYER_TITLES.Values)
# Nicer labels in the images (non-ASCII written as char codes so this file stays ASCII).
$PRETTY = @{
  'Left'  = [string][char]0x2190; 'Up'   = [string][char]0x2191
  'Right' = [string][char]0x2192; 'Down' = [string][char]0x2193
  'Vol-'  = 'Vol' + [char]0x2212
}
$CROSS = [string][char]0x00D7

$css = (@'
<style>
  .case { fill: #f6f8fa; stroke: #d0d7de; }
  .k    { fill: #ffffff; stroke: #c4cbd3; }
  .k.mod   { fill: #e7f0ff; stroke: #9dbcf2; }
  .k.layer { fill: #fff2e2; stroke: #f0b77a; }
  .k.held  { fill: #ffd8a8; stroke: #e8590c; stroke-width: 1.6; }
  .k.trans { fill: #f1f3f5; stroke: #d8dde3; stroke-dasharray: 3 3; }
  .k.off   { fill: #eceef1; stroke: #d8dde3; }
  .t    { fill: #1f2328; font: 600 13px system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
  .t.mod   { fill: #1a4fb5; }
  .t.layer { fill: #9a4b00; }
  .t.held  { fill: #8a3200; }
  .t.off   { fill: #9aa3ad; font-weight: 400; }
  .h    { font: 500 10px system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
  .h.mod   { fill: #2f6fdf; }
  .h.layer { fill: #c05f00; }
  .cap  { fill: #57606a; font: 400 11px system-ui, -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
  .bub  { fill: #6e40c9; }
  .bt   { fill: #ffffff; font: 700 13px ui-monospace, "Cascadia Mono", Consolas, Menlo, monospace; }
  @media (prefers-color-scheme: dark) {
    .case { fill: #161b22; stroke: #30363d; }
    .k    { fill: #2d333b; stroke: #444c56; }
    .k.mod   { fill: #1c2d4d; stroke: #3d5f9c; }
    .k.layer { fill: #3b2a15; stroke: #8a5a24; }
    .k.held  { fill: #5c3410; stroke: #ff922b; }
    .k.trans { fill: #1c2128; stroke: #373e47; }
    .k.off   { fill: #1c2128; stroke: #373e47; }
    .t    { fill: #e6edf3; }
    .t.mod   { fill: #9cc1ff; }
    .t.layer { fill: #ffb366; }
    .t.held  { fill: #ffd8a8; }
    .t.off   { fill: #6e7681; }
    .h.mod   { fill: #7fadff; }
    .h.layer { fill: #ffa94d; }
    .cap  { fill: #8b949e; }
    .bub  { fill: #8957e5; }
  }
</style>
'@) -replace "`r`n", "`n"

$U = 46; $GAP = 4; $KH = 46; $PITCH = 50; $M = 10

function Key($x, $y, $w, $h, [string]$cell) {
  $p = $cell -split '\|', 2
  $tap = $p[0]; $hold = if ($p.Count -gt 1) { $p[1] } else { '' }
  $cls = ''
  if ($tap -eq '--') { $cls = 'trans'; $tap = '' }
  elseif ($tap -eq 'XX') { $cls = 'off'; $tap = $CROSS }
  elseif ($tap -eq 'held') { $cls = 'held' }
  elseif ($LAYERS -contains $hold) { $cls = 'layer' }
  elseif ($MODS -contains $tap) { $cls = 'mod' }
  if ($PRETTY.ContainsKey($tap)) { $tap = $PRETTY[$tap] }
  $s = '<rect class="k {0}" x="{1}" y="{2}" width="{3}" height="{4}" rx="6"/>' -f $cls, (N $x), (N $y), (N $w), (N $h)
  $cx = $x + $w / 2
  if ($hold) {
    $hc = if ($LAYERS -contains $hold) { 'layer' } else { 'mod' }
    if ($tap) { $s += '<text class="t {0}" x="{1}" y="{2}" text-anchor="middle">{3}</text>' -f $cls, (N $cx), (N ($y + 20)), (X $tap) }
    $s += '<text class="h {0}" x="{1}" y="{2}" text-anchor="middle">{3}</text>' -f $hc, (N $cx), (N ($y + $h - 8)), (X $hold)
  } elseif ($tap) {
    $s += '<text class="t {0}" x="{1}" y="{2}" text-anchor="middle">{3}</text>' -f $cls, (N $cx), (N ($y + $h / 2 + 5)), (X $tap)
  }
  $s
}

function SvgStart($w, $h, [string]$title) {
  ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {0} {1}" width="{0}" height="{1}" role="img" aria-label="{2}"><title>{2}</title>' -f $w, $h, (X $title)) + $css +
  ('<rect class="case" x="0.5" y="0.5" width="{0}" height="{1}" rx="12"/>' -f ($w - 1), ($h - 1))
}

# Text version: a boxed ASCII grid, tap on the first line, hold on the second.
function Grid($rows) {
  $CW = 7
  $border = { param($n) '+' + (('-' * $CW + '+') * $n) }
  $lines = @(); $prev = 0
  foreach ($r in $rows) {
    $cells = @($r | ForEach-Object { $p = $_ -split '\|', 2; ,@($p[0], $(if ($p.Count -gt 1) { $p[1] } else { '' })) })
    $lines += & $border ([Math]::Max($cells.Count, $prev))
    $lines += '|' + (($cells | ForEach-Object { (' ' + $_[0]).PadRight($CW) + '|' }) -join '')
    $lines += '|' + (($cells | ForEach-Object { (' ' + $_[1]).PadRight($CW) + '|' }) -join '')
    $prev = $cells.Count
  }
  $lines += & $border $prev
  $lines -join "`n"
}

# ---------- layer images ----------
foreach ($name in $LAYERS_DATA.Keys) {
  $rows = $LAYERS_DATA[$name].rows
  if ($rows.Count -ne $WIDTHS.Count) { Warn "Layer '$name' has $($rows.Count) rows, expected $($WIDTHS.Count)" }
  $W = 15 * $U - $GAP + 2 * $M
  $H = 5 * $PITCH - ($PITCH - $KH) + 2 * $M
  $b = New-Object System.Text.StringBuilder
  [void]$b.Append((SvgStart $W $H $LAYERS_DATA[$name].title))
  for ($r = 0; $r -lt $rows.Count; $r++) {
    if ($rows[$r].Count -ne $WIDTHS[$r].Count) { Warn "Layer '$name' row $($r + 1) has $($rows[$r].Count) keys, expected $($WIDTHS[$r].Count)" }
    $x = $M; $y = $M + $r * $PITCH
    for ($c = 0; $c -lt $rows[$r].Count; $c++) {
      $w = $WIDTHS[$r][$c] * $U
      [void]$b.Append((Key $x $y ($w - $GAP) $KH $rows[$r][$c]))
      $x += $w
    }
  }
  [void]$b.Append('</svg>')
  [IO.File]::WriteAllText((Join-Path $OutDir "layer-$name.svg"), $b.ToString(), $utf8)
}

# ---------- chord image ----------
$CU = 60; $CK = 44
$W = [int](10.75 * $CU - ($CU - $CK) + 2 * $M + 4)
$H = 3 * $CU - ($CU - $CK) + 2 * $M
$b = New-Object System.Text.StringBuilder
[void]$b.Append((SvgStart $W $H 'Chords: press two neighbouring keys together'))
for ($r = 0; $r -lt $CHORDS.Count; $r++) {
  $y = $M + $r * $CU
  for ($c = 0; $c -lt $CHORD_COLS; $c++) {
    [void]$b.Append((Key ($M + ($CHORDS[$r].off + $c) * $CU) $y $CK $CK $CHORDS[$r].keys[$c]))
  }
  for ($c = 0; $c -lt $CHORD_COLS - 1; $c++) {
    $sym = $CHORDS[$r].chords[$c]; if (-not $sym) { continue }
    $cx = $M + ($CHORDS[$r].off + $c + 1) * $CU - ($CU - $CK) / 2
    $cy = $y + $CK / 2
    [void]$b.Append(('<circle class="bub" cx="{0}" cy="{1}" r="12"/>' -f (N $cx), (N $cy)))
    [void]$b.Append(('<text class="bt" x="{0}" y="{1}" text-anchor="middle">{2}</text>' -f (N $cx), (N ($cy + 4.5)), (X $sym)))
  }
}
[void]$b.Append('</svg>')
[IO.File]::WriteAllText((Join-Path $OutDir 'chords.svg'), $b.ToString(), $utf8)

# ---------- legend image ----------
$items = @(
  @('A|Win', 'Tap / hold'), @('Ctrl', 'Modifier'), @('Space|Nav', 'Layer key'),
  @('held', 'Held thumb key'), @('--', 'Same as base'), @('XX', 'Disabled')
)
$IW = 112
$W = $items.Count * $IW + 2 * $M - 8
$H = 46 + 22 + 2 * $M
$b = New-Object System.Text.StringBuilder
[void]$b.Append((SvgStart $W $H 'Legend for the layer diagrams'))
for ($i = 0; $i -lt $items.Count; $i++) {
  $x = $M + $i * $IW + ($IW - 8 - 62) / 2
  [void]$b.Append((Key $x $M 62 46 $items[$i][0]))
  [void]$b.Append(('<text class="cap" x="{0}" y="{1}" text-anchor="middle">{2}</text>' -f (N ($x + 31)), ($M + 46 + 16), (X $items[$i][1])))
}
[void]$b.Append('</svg>')
[IO.File]::WriteAllText((Join-Path $OutDir 'legend.svg'), $b.ToString(), $utf8)

# ---------- text versions in README.md ----------
if (Test-Path $Readme) {
  $text = [IO.File]::ReadAllText($Readme, [Text.Encoding]::UTF8)
  $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $fence = '`' * 3
  foreach ($name in $LAYERS_DATA.Keys) {
    $block = "<!-- text:$name -->$nl$fence$nl" + ((Grid $LAYERS_DATA[$name].rows) -replace "`n", $nl) + "$nl$fence$nl<!-- /text:$name -->"
    $pattern = "(?s)<!-- text:$name -->.*?<!-- /text:$name -->"
    if ($text -match $pattern) { $text = [regex]::Replace($text, $pattern, { param($m) $block }) }
    else { Write-Warning "No text:$name markers found in README.md (layer '$name' has no text version)" }
  }
  [IO.File]::WriteAllText($Readme, $text, $utf8)
}
Write-Host "Diagrams for layers $($LAYER_ORDER -join ', ') written to $((Resolve-Path $OutDir).Path)"
