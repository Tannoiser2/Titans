class_name UI
extends RefCounted
## Helper grafici condivisi: palette «ferro e pergamena» (acciaio scuro, cuoio, oro antico, rosso sangue),
## titoli in Cinzel Decorative, intestazioni in Cinzel, testi in Crimson Pro (caratteri OFL).

const GOLD := Color("#c9a45a")
const GOLD_L := Color("#f0d48a")
const GOLD_D := Color("#7a5f2c")
const IRON := Color("#14161a")
const IRON_L := Color("#262a31")
const PANEL := Color("#1b1d22")
const LEATHER := Color("#2b2119")
const PAPER := Color("#ecdcb8")
const INK := Color("#2a1d12")
const BLOOD := Color("#8e1c1c")
const BLOOD_L := Color("#c8402f")
const GREEN := Color("#7fc46c")
const TEXT := Color("#ece3d0")
const MUTED := Color("#a9a08d")

static var _tex := {}
static var font_title: Font
static var font_head: Font
static var font_head_b: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	font_title = load("res://assets/fonts/CinzelDecorative-Bold.woff2")
	var cz: FontFile = load("res://assets/fonts/Cinzel-VF.woff2")
	font_head = _var(cz, 500)
	font_head_b = _var(cz, 700)
	var body: FontFile = load("res://assets/fonts/CrimsonPro-VF.woff2")
	font_body = _var(body, 450)
	font_bold = _var(body, 700)
	font_italic = _var(load("res://assets/fonts/CrimsonPro-Italic-VF.woff2"), 450)


static func _var(f: Font, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = f
	if weight > 0:
		fv.variation_opentype = {"wght": weight}
	var ts := TextServerManager.get_primary_interface()
	fv.opentype_features = {ts.name_to_tag("lnum"): 1}
	return fv


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]


static func ncol(nat: String) -> Color:
	return TIData.NATIONS[nat]["color"]


static func nlight(nat: String) -> Color:
	return TIData.NATIONS[nat]["light"]


static func ndark(nat: String) -> Color:
	return TIData.NATIONS[nat]["dark"]


static func banner(nat: String) -> Texture2D:
	return tex("res://assets/segni/stendardo_%s.png" % nat)


static func nation_card_tex(nat: String, i: int) -> Texture2D:
	return tex("res://assets/carte/%s%02d.jpg" % [nat, i])


static func support_tex(i: int) -> Texture2D:
	return tex("res://assets/carte/sup%02d.jpg" % i)


static func order_tex(i: int, adv: bool) -> Texture2D:
	return tex("res://assets/carte/%s%02d.jpg" % ["adv" if adv else "ord", i])


static func panel_style(bg: Color, border: Color, bw := 1, radius := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


static func paper_style(radius := 6) -> StyleBoxFlat:
	var sb := panel_style(PAPER, GOLD_D, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	return sb


static func iron_style(radius := 6, alpha := 0.93) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), GOLD_D, 2, radius)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 8
	return sb


static func label(text: String, size := 20, col := TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := GOLD) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	return l


static func heading(text: String, size := 24, col := GOLD) -> Label:
	init_fonts()
	return label(text, size, col, font_head_b)


static func wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func button(text: String, w := 200.0, h := 50.0, size := 21) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func primary(b: Button) -> Button:
	var n := panel_style(BLOOD, GOLD, 2, 6)
	n.shadow_color = Color(0, 0, 0, 0.45)
	n.shadow_size = 4
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", panel_style(Color("#ad2b25"), GOLD_L, 2, 6))
	b.add_theme_stylebox_override("pressed", panel_style(GOLD, GOLD, 2, 6))
	b.add_theme_color_override("font_color", Color("#fff1d8"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


## Dado disegnato: colore per tipo, pallini pari al valore (0 = faccia vuota).
static var _die_tex := {}


## Facce vere dei dadi speciali (Echi del Passato, Campi di Sangue, Spirito di Guerra), da foto e scansioni.
static func die_face(t: String, v: int, special: bool) -> Texture2D:
	var key := ""
	match t:
		"C": key = "C%d%s" % [v, "s" if special else ""]
		"Q": key = "Q%d" % clampi(v, 0, 2)
		"W": key = "Ws" if special else "W%d" % v
	if key == "":
		return null
	if not _die_tex.has(key):
		var path := "res://assets/dadi/%s.png" % key
		_die_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _die_tex[key]


static func draw_die(ci: CanvasItem, rect: Rect2, t: String, v: int, selected := false, dim := false, skull := false, zero := false) -> void:
	var face := die_face(t, v, skull)
	if face != null:
		ci.draw_texture_rect(face, rect, false, Color(0.55, 0.55, 0.55) if (dim or zero) else Color.WHITE)
		if selected:
			var sbs := StyleBoxFlat.new()
			sbs.draw_center = false
			sbs.set_corner_radius_all(int(rect.size.x * 0.18))
			sbs.border_color = GOLD_L
			sbs.set_border_width_all(4)
			ci.draw_style_box(sbs, rect)
		if t == "W" and skull and v > 0:
			init_fonts()
			ci.draw_string_outline(font_head_b, rect.position + Vector2(0, rect.size.y * 0.98), "+%d" % v, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.95, int(rect.size.x * 0.34), 6, Color(0, 0, 0, 0.9))
			ci.draw_string(font_head_b, rect.position + Vector2(0, rect.size.y * 0.98), "+%d" % v, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x * 0.95, int(rect.size.x * 0.34), GOLD_L)
		return
	var bg: Color = {"F": Color("#e9dcc0"), "K": Color("#c79a5a"), "A": Color("#8f969e"), "T": Color("#7e1f1f"), "C": Color("#5b3a8c"), "Q": Color("#6d7078"), "W": Color("#2aa7ad")}[t]
	var pip: Color = Color("#f6ecd6") if t in ["T", "C", "Q", "W"] else Color("#1d1712")
	if zero:
		bg = bg.darkened(0.35)
	if dim:
		bg = bg.darkened(0.45)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(rect.size.x * 0.18))
	sb.border_color = GOLD_L if selected else Color(0, 0, 0, 0.8)
	sb.set_border_width_all(4 if selected else 2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 3
	ci.draw_style_box(sb, rect)
	var c := rect.get_center()
	var s := rect.size.x
	var r := s * 0.085
	var o := s * 0.24
	var pos := {
		0: [], 1: [Vector2.ZERO], 2: [Vector2(-o, -o), Vector2(o, o)], 3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
	}
	if t == "W" and skull:
		# simbolo dello Spirito di Guerra: disco chiaro con una fiamma
		ci.draw_circle(c + Vector2(s * 0.18, s * 0.18), s * 0.17, Color("#f3efe4"))
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.18, s * 0.06), c + Vector2(s * 0.26, s * 0.24), c + Vector2(s * 0.10, s * 0.24)]), bg)
	if t == "C" and skull:
		# teschio in basso a destra: cranio, occhi e denti
		var k := c + Vector2(s * 0.26, s * 0.26)
		var kr := s * 0.13
		ci.draw_circle(k, kr, Color("#f1e7d2"))
		ci.draw_rect(Rect2(k + Vector2(-kr * 0.6, kr * 0.5), Vector2(kr * 1.2, kr * 0.7)), Color("#f1e7d2"))
		ci.draw_circle(k + Vector2(-kr * 0.4, -kr * 0.05), kr * 0.28, bg)
		ci.draw_circle(k + Vector2(kr * 0.4, -kr * 0.05), kr * 0.28, bg)
		for p in pos.get(v, []):
			ci.draw_circle(c + Vector2(-s * 0.14, -s * 0.14) + p * 0.75, r * 0.9, pip)
	elif v > 4 or (t == "W" and v > 0):
		init_fonts()
		ci.draw_string(font_head_b, c + Vector2(-s * 0.32, s * 0.16), str(v), HORIZONTAL_ALIGNMENT_CENTER, s * 0.64, int(s * 0.5), pip)
	else:
		for p in pos.get(v, []):
			ci.draw_circle(c + p, r, pip)
	# piccola sigla del tipo in alto a sinistra
	init_fonts()
	ci.draw_string(font_head_b, rect.position + Vector2(s * 0.08, s * 0.28), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.2), Color(pip, 0.55))


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 21
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2a2c31")
	sb.border_color = GOLD_D
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#3d3a36")
	sbh.border_color = GOLD
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = GOLD
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#1c1d20")
	sbd.border_color = Color("#3c3a36")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color("#f1e6cc"))
	th.set_color("font_hover_color", "Button", GOLD_L)
	th.set_color("font_pressed_color", "Button", IRON)
	th.set_color("font_disabled_color", "Button", Color("#6f6a60"))
	th.set_font("font", "Button", font_head_b)
	th.set_font_size("font_size", "Button", 20)
	th.set_color("font_color", "Label", TEXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	pn.border_color = Color("#000000")
	pn.set_border_width_all(1)
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 20)
	th.set_font_size("bold_font_size", "RichTextLabel", 20)
	th.set_font_size("italics_font_size", "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", TEXT)
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#0f1013"), GOLD_D, 1, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#0f1013"), GOLD, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 19)
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color("#121317ee")
	tp.border_color = GOLD
	tp.set_border_width_all(1)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	th.set_font("font", "CheckBox", font_head_b)
	th.set_font_size("font_size", "CheckBox", 20)
	th.set_font("font", "OptionButton", font_head_b)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(GOLD_D, 0.8)
	sc.set_corner_radius_all(4)
	th.set_stylebox("grabber", "VScrollBar", sc)
	th.set_stylebox("grabber_highlight", "VScrollBar", sc)
	th.set_stylebox("grabber_pressed", "VScrollBar", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(0, 0, 0, 0.25)
	th.set_stylebox("scroll", "VScrollBar", sct)
	return th
