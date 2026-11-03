# Section 3.6: mark the register file, the ALU and the cycle counter on the
# final layout, using the hierarchical instance names kept by synthesis
# (SYNTH_HIERARCHY_MODE = keep -> u_soc/u_core/u_rf/..., etc.).
#
# KLayout batch script:
#   klayout -b -r scripts/annotate_layout.py -rd gds=<final.gds> -rd defpath=<final.def> -rd out=<prefix>
# Produces <prefix>.png (layout + coloured instance groups), <prefix>_marks.png
# (groups only, over the die outline) and <prefix>.gds (layout with the
# annotation layers 900-903/0, to open in the KLayout GUI).
import re
import pya

GROUPS = [
    # (instance prefix, label, GDS layer, colour)
    ("u_soc/u_core/u_rf/",                "Register file (u_rf)",             900, 0xE6194B),
    ("u_soc/u_core/u_id/u_alu/",          "ALU (u_alu)",                      901, 0x3CB44B),
    ("u_soc/u_periph/u_cycle_counter/",   "Cycle counter (u_cycle_counter)",  902, 0x4363D8),
]
OUTLINE_LAYER = 903

ly = pya.Layout()
ly.read(gds)
top = ly.top_cell()
dbu = ly.dbu

# ---- parse DEF placement ----
text = open(defpath).read()
units = int(re.search(r"UNITS\s+DISTANCE\s+MICRONS\s+(\d+)", text).group(1))
comp_block = text[text.index("COMPONENTS"):text.index("END COMPONENTS")]
comp_re = re.compile(r"-\s+(\S+)\s+(\S+)\s+.*?\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", re.S)

layers = {g[2]: ly.layer(g[2], 0) for g in GROUPS}
outline_l = ly.layer(OUTLINE_LAYER, 0)
counts = {g[1]: 0 for g in GROUPS}
regions = {g[1]: pya.Region() for g in GROUPS}

for entry in comp_block.split(";"):
    m = comp_re.search(entry)
    if not m:
        continue
    name, macro, x, y, orient = m.groups()
    name = name.replace("\\", "")
    for prefix, label, layer, _ in GROUPS:
        if name.startswith(prefix):
            cell = ly.cell(macro)
            if cell is None:
                continue
            bb = cell.bbox()
            w, h = bb.width(), bb.height()
            if orient in ("E", "W", "FE", "FW"):
                w, h = h, w
            x0 = int(round(int(x) / units / dbu))
            y0 = int(round(int(y) / units / dbu))
            box = pya.Box(x0, y0, x0 + w, y0 + h)
            top.shapes(layers[layer]).insert(box)
            regions[label].insert(box)
            counts[label] += 1
            break

die = top.bbox()
top.shapes(outline_l).insert(pya.Path([pya.Point(die.left, die.bottom), pya.Point(die.right, die.bottom),
                                        pya.Point(die.right, die.top), pya.Point(die.left, die.top),
                                        pya.Point(die.left, die.bottom)], int(2 / dbu)))
legend_x = die.right + int(15 / dbu)
for i, (prefix, label, layer, _) in enumerate(GROUPS):
    hull = regions[label].merged().bbox()
    # Legend outside the die (right side), one line per group.
    y = die.top - int((20 + 45 * i) / dbu)
    top.shapes(layers[layer]).insert(pya.Box(legend_x, y, legend_x + int(25 / dbu), y + int(25 / dbu)))
    t = pya.Text(f"{label}: {counts[label]} cells", pya.Trans(legend_x + int(35 / dbu), y + int(4 / dbu)))
    t.size = int(14 / dbu)
    top.shapes(layers[layer]).insert(t)
    print(f"{label}: {counts[label]} cells, bbox {hull.left*dbu:.1f},{hull.bottom*dbu:.1f} - {hull.right*dbu:.1f},{hull.top*dbu:.1f} um")

ly.write(out + ".gds")


def render(path, show_layout):
    lv = pya.LayoutView()
    lv.load_layout(out + ".gds", True)
    lv.max_hier()
    lv.set_config("background-color", "#ffffff")
    lv.set_config("text-font", "0")
    lv.set_config("apply-text-trans", "true")
    it = lv.begin_layers()
    while not it.at_end():
        lp = it.current()
        ann = lp.source_layer in [g[2] for g in GROUPS] + [OUTLINE_LAYER]
        if not ann:
            lp.visible = show_layout
            lp.fill_color = lp.frame_color = 0xB0B0B0
            lp.dither_pattern = 1
            lp.transparent = True
        lv.set_layer_properties(it, lp)
        it.next()
    for prefix, label, layer, colour in GROUPS:
        lp = pya.LayerPropertiesNode()
        lp.source = f"{layer}/0@1"
        lp.fill_color = lp.frame_color = colour
        lp.dither_pattern = 0 if not show_layout else 2
        lp.width = 1
        lv.insert_layer(lv.end_layers(), lp)
    lp = pya.LayerPropertiesNode()
    lp.source = f"{OUTLINE_LAYER}/0@1"
    lp.fill_color = lp.frame_color = 0x000000
    lv.insert_layer(lv.end_layers(), lp)
    lv.zoom_fit()
    lv.save_image(path, 2600, 1800)


render(out + ".png", True)
render(out + "_marks.png", False)
print("wrote", out + ".png", out + "_marks.png", out + ".gds")
