class_name UiKit
extends RefCounted
## Fabrique de widgets : styles communs, icones d'items, cases d'inventaire.

const BG := Color(0.09, 0.08, 0.13, 0.94)
const BG_SOFT := Color(0.16, 0.15, 0.22, 0.96)
const SLOT := Color(0.22, 0.21, 0.29, 0.95)
const SLOT_HL := Color(0.42, 0.34, 0.62, 1.0)
const ACCENT := Color(0.62, 0.45, 1.0)
const MANA := Color(0.38, 0.55, 1.0)
const LIFE := Color(0.85, 0.25, 0.32)
const TEXT := Color(0.94, 0.93, 0.98)

const SLOT_SIZE := 52

static var _icons: Dictionary = {}
static var _blocks_tex: Texture2D
static var _items_tex: Texture2D


static func panel_style(color := BG, radius := 10, border := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.border_color = Color(0.45, 0.38, 0.62, 0.8)
	s.set_border_width_all(border)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func make_panel(color := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color))
	return p


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func button(text: String, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	var normal := panel_style(BG_SOFT, 8, 2)
	var hover := panel_style(Color(0.26, 0.22, 0.38, 0.98), 8, 2)
	var pressed := panel_style(Color(0.34, 0.27, 0.5, 1.0), 8, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	return b


static func line_edit(placeholder: String, text := "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_stylebox_override("normal", panel_style(Color(0.06, 0.06, 0.1, 0.95), 6, 1))
	e.add_theme_stylebox_override("focus", panel_style(Color(0.10, 0.09, 0.16, 1.0), 6, 2))
	return e


static func item_texture(item_id: int) -> Texture2D:
	if item_id == 0:
		return null
	if _icons.has(item_id):
		return _icons[item_id]
	if _blocks_tex == null:
		_blocks_tex = load("res://assets/textures/blocks.png")
		_items_tex = load("res://assets/textures/items.png")
	var at := AtlasTexture.new()
	var tile := -1
	if Items.is_block(item_id):
		at.atlas = _blocks_tex
		tile = Blocks.face_tile(Items.block_id(item_id), 2)
	else:
		at.atlas = _items_tex
		tile = Items.icon_index(item_id)
	if tile < 0:
		return null
	at.region = Rect2((tile % 16) * 16, (tile / 16) * 16, 16, 16)
	at.filter_clip = true
	_icons[item_id] = at
	return at


static func make_slot(size := SLOT_SIZE) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", panel_style(SLOT, 6, 1))
	var tr := TextureRect.new()
	tr.name = "Icon"
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 5
	tr.offset_top = 5
	tr.offset_right = -5
	tr.offset_bottom = -5
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	var cl := label("", 14)
	cl.name = "Count"
	cl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cl.offset_left = -size + 4
	cl.offset_top = -20
	cl.offset_right = -4
	cl.offset_bottom = -2
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cl)
	var dr := ProgressBar.new()
	dr.name = "Dura"
	dr.show_percentage = false
	dr.custom_minimum_size = Vector2(0, 4)
	dr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dr.offset_left = 4
	dr.offset_right = -4
	dr.offset_top = -8
	dr.offset_bottom = -4
	dr.visible = false
	dr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(dr)
	return p


static func fill_slot(slot: Panel, data: Dictionary, highlight := false) -> void:
	var icon: TextureRect = slot.get_node("Icon")
	var count: Label = slot.get_node("Count")
	var dura: ProgressBar = slot.get_node("Dura")
	var id := int(data.get("id", 0))
	icon.texture = item_texture(id)
	var n := int(data.get("count", 0))
	count.text = str(n) if n > 1 else ""
	var maxd := int(Items.get_def(id).get("durability", 0))
	if id != 0 and maxd > 0:
		dura.visible = true
		dura.max_value = maxd
		dura.value = clampi(int(data.get("dura", maxd)), 0, maxd)
	else:
		dura.visible = false
	slot.add_theme_stylebox_override("panel",
			panel_style(SLOT_HL if highlight else SLOT, 6, 2 if highlight else 1))
	slot.tooltip_text = Items.item_name(id) if id != 0 else ""
