# Diagram generation

The images in [`../images`](../images) and the text versions under the layer diagrams in the main [`README.md`](../README.md) are generated from [`kanata.kbd`](../kanata.kbd), so you don't have to redraw them by hand. This is only needed when changing the layout itself; most users can ignore it.

Two equivalent scripts are included:

- [`make-images.sh`](make-images.sh) — bash and POSIX `awk`, for Linux and macOS.
- [`make-images.ps1`](make-images.ps1) — PowerShell, for Windows (or `pwsh` anywhere).

Run either one from anywhere; paths are resolved relative to the script:

```bash
bash tools/make-images.sh
pwsh -File tools/make-images.ps1
```

Both read `defsrc`, `deflayer`, `defalias`, `deftemplate` and `defchordsv2` from [`kanata.kbd`](../kanata.kbd), and produce byte-identical output:

- [`images/layer-base.svg`](../images/layer-base.svg), [`layer-nav.svg`](../images/layer-nav.svg), [`layer-num.svg`](../images/layer-num.svg), [`layer-mouse.svg`](../images/layer-mouse.svg) — one per layer, light and dark theme
- [`images/chords.svg`](../images/chords.svg) and [`images/legend.svg`](../images/legend.svg)
- the ASCII text versions in the main [`README.md`](../README.md), between the `<!-- text:<layer> -->` and `<!-- /text:<layer> -->` markers

The options match: `-c`, `-o` and `-r` (bash) / `-Config`, `-OutDir` and `-Readme` (PowerShell) select a different config, output folder or README.

Anything the scripts don't recognise is drawn with its raw name and a warning, and a layer with the wrong number of keys for the physical layout is reported — which catches most copy-paste slips in a new layer. Two things are deliberately part of the scripts rather than the configuration: the physical key widths of each row, and the friendly labels for key names and actions. Extend those when you add something new.

Whitespace and alignment in `kanata.kbd` do not affect the output: the scripts read the key tokens on each line and use the width tables in the scripts for positioning. To change how wide a key appears, edit the width list in both scripts.
