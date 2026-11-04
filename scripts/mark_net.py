# Section 3.6: show where a net is in the layout (e.g. an antenna violation).
#   klayout -b -r scripts/mark_net.py -rd gds=<final.gds> -rd defpath=<final.def> \
#           -rd net='u_soc/u_spi/sclk_sync[0]' -rd out=<prefix>
# Draws the routed wires of the net (from the DEF) and the cells it connects,
# and writes <prefix>.png (whole die) and <prefix>_zoom.png (around the net).
import re
import pya

ly = pya.Layout()
ly.read(gds)
top = ly.top_cell()
dbu = ly.dbu
text = open(defpath).read()
units = int(re.search(r"UNITS\s+DISTANCE\s+MICRONS\s+(\d+)", text).group(1))
s = lambda v: int(round(int(v) / units / dbu))

WIRE_L, CELL_L = ly.layer(910, 0), ly.layer(911, 0)

# --- net routing and connections ---
nets = text[text.index("\nNETS"):text.index("END NETS")]
want = net.replace("[", "\\[").replace("]", "\\]")
m = re.search(r"-\s+" + re.escape(want) + r"\s(.*?);", nets, re.S)
if not m:
    raise SystemExit(f"net {net} not found in DEF")
body = m.group(1)
conns = re.findall(r"\(\s*(\S+)\s+(\S+)\s*\)", body.split("+ ROUTED")[0] if "+ ROUTED" in body else body)
region = pya.Region()
for seg in re.split(r"\bNEW\b|\+ ROUTED", body)[1:]:
    toks = re.findall(r"\(\s*(-?\d+|\*)\s+(-?\d+|\*)(?:\s+-?\d+)?\s*\)", seg)
    pts, last = [], None
    for x, y in toks:
        px = last[0] if x == "*" else s(x)
        py = last[1] if y == "*" else s(y)
        last = (px, py)
        pts.append(pya.Point(px, py))
    if len(pts) >= 2:
        path = pya.Path(pts, int(1.0 / dbu))
        top.shapes(WIRE_L).insert(path)
        region.insert(path.polygon())
    elif len(pts) == 1:
        b = pya.Box(pts[0].x - int(0.5 / dbu), pts[0].y - int(0.5 / dbu), pts[0].x + int(0.5 / dbu), pts[0].y + int(0.5 / dbu))
        top.shapes(WIRE_L).insert(b)
        region.insert(b)

comps = text[text.index("COMPONENTS"):text.index("END COMPONENTS")]
for inst, pin in conns:
    if inst == "PIN":
        continue
    cm = re.search(r"-\s+" + re.escape(inst) + r"\s+(\S+).*?\(\s*(-?\d+)\s+(-?\d+)\s*\)", comps, re.S)
    if cm:
        c = ly.cell(cm.group(1))
        x0, y0 = s(cm.group(2)), s(cm.group(3))
        b = pya.Box(x0, y0, x0 + c.bbox().width(), y0 + c.bbox().height())
        top.shapes(CELL_L).insert(b)
        region.insert(b)
        print(f"  {inst.replace(chr(92), '')}/{pin} ({cm.group(1)}) at {x0*dbu:.1f},{y0*dbu:.1f} um")

bb = region.bbox()
print(f"net {net}: bbox {bb.left*dbu:.1f},{bb.bottom*dbu:.1f} - {bb.right*dbu:.1f},{bb.top*dbu:.1f} um")
lbl = pya.Text(f"net {net}", pya.Trans(bb.right + int(5 / dbu), bb.top))
lbl.size = int(10 / dbu)
top.shapes(WIRE_L).insert(lbl)
ly.write(out + ".gds")


def render(path, box):
    lv = pya.LayoutView()
    lv.load_layout(out + ".gds", True)
    lv.max_hier()
    lv.set_config("background-color", "#ffffff")
    it = lv.begin_layers()
    while not it.at_end():
        lp = it.current()
        if lp.source_layer not in (910, 911):
            lp.fill_color = lp.frame_color = 0xC8C8C8
            lp.dither_pattern = 1
        lv.set_layer_properties(it, lp)
        it.next()
    for layer, colour in ((910, 0xFF0000), (911, 0x0050FF)):
        lp = pya.LayerPropertiesNode()
        lp.source = f"{layer}/0@1"
        lp.fill_color = lp.frame_color = colour
        lp.dither_pattern = 0
        lp.width = 3
        lv.insert_layer(lv.end_layers(), lp)
    if box is None:
        lv.zoom_fit()
    else:
        lv.zoom_box(box)
    lv.save_image(path, 1600, 1600)


render(out + ".png", None)
render(out + "_zoom.png", pya.DBox(bb.left * dbu - 20, bb.bottom * dbu - 20, bb.right * dbu + 60, bb.top * dbu + 20))
print("wrote", out + ".png", out + "_zoom.png")
