extends PanelContainer
class_name GeoDotTuningPanel

signal tuning_changed(values: Dictionary, changed_key: String, old_value: Variant, new_value: Variant)

var values := {
	"far_density": 1.0,
	"far_pixel_budget": 12000,
	"far_tile_pixels": 5.0,
	"individual_threshold_px": 1.0,
	"full_3d_threshold_px": 4.0,
	"full_3d_distance_m": 3000.0,
	"tall_3d_distance_m": 6000.0,
	"prefetch_scale": 1.35,
	"streaming_ms": 3.0,
	"ram_target_mb": 2048,
	"ram_hard_mb": 2560,
	"resident_cells": 128,
}
var _body: VBoxContainer
var _value_labels: Dictionary = {}

func _ready() -> void:
	name = "GeoDotTuningPanel"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -360; offset_right = -12; offset_top = 180; offset_bottom = 720
	custom_minimum_size = Vector2(348, 0)
	var root := VBoxContainer.new(); add_child(root)
	var header := HBoxContainer.new(); root.add_child(header)
	var title := Label.new(); title.text = "GeoDot Tuning"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	var collapse := Button.new(); collapse.text = "−"; collapse.tooltip_text = "Fäll ihop panelen så att den inte täcker världen."; collapse.pressed.connect(func(): _body.visible = not _body.visible; collapse.text = "−" if _body.visible else "+") ; header.add_child(collapse)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size=Vector2(0,460); root.add_child(scroll)
	_body = VBoxContainer.new(); _body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(_body)
	_add_control("far_density","Far density",0.1,"Hur tydligt tät bebyggelse syns långt bort. Högre = fler/starkare stads-samples och högre kostnad. Lägre = billigare men städer tonar bort tidigare.")
	_add_control("far_pixel_budget","Far pixel budget",1000,"Max antal far-samples som får visas. Högre = mer detalj på hög höjd men mer GPU/CPU/minne. Lägre = billigare.")
	_add_control("far_tile_pixels","Far tile resolution",1.0,"Hur många skärmpixlar en far-tile ungefär ska täcka. Högre = grövre/färre tiles. Lägre = finare/fler tiles.")
	_add_control("individual_threshold_px","Individual building",0.25,"Hur stor en byggnad måste vara på skärmen för att få visas individuellt. Högre tar bort mer jitter långt bort.")
	_add_control("full_3d_threshold_px","Full 3D threshold",0.5,"Hur tydlig en byggnad måste vara innan full 3D används. Lägre = 3D tidigare men dyrare.")
	_add_control("full_3d_distance_m","Full 3D distance",500.0,"Inom detta avstånd garanteras full 3D för vanliga hus. Default 3 km.")
	_add_control("tall_3d_distance_m","Tall-building distance",500.0,"Hur långt bort höga/stora byggnader får behålla 3D när de fortfarande syns. Default 6 km.")
	_add_control("prefetch_scale","Prefetch",0.1,"Hur tidigt nästa detaljnivå förbereds. Högre = mjukare zoom men mer RAM/arbete i förväg.")
	_add_control("streaming_ms","Streaming frame budget",0.5,"Hur många millisekunder per frame världsstreaming får använda. Högre laddar snabbare men kan påverka FPS.")
	_add_control("ram_target_mb","World RAM target",256,"Mjuk RAM-budget för världsrenderingen. När den nås förenklas avlägsen detalj först.")
	_add_control("ram_hard_mb","World RAM hard cap",256,"Hård övre RAM-gräns för rendererägd data. Ska ligga över target.")
	_add_control("resident_cells","Resident budget",16,"Hur många detaljceller som får hållas färdiga samtidigt. Högre = mindre omladdning men mer RAM.")

func _add_control(key: String, caption: String, step: float, help: String) -> void:
	var row := HBoxContainer.new(); _body.add_child(row)
	var label := Label.new(); label.text=caption; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var help_button := Button.new(); help_button.text="?"; help_button.tooltip_text=help; help_button.focus_mode=Control.FOCUS_NONE; row.add_child(help_button)
	var minus := Button.new(); minus.text="−"; minus.focus_mode=Control.FOCUS_NONE; minus.pressed.connect(func(): _change(key,-step)); row.add_child(minus)
	var value_label := Label.new(); value_label.custom_minimum_size=Vector2(72,0); value_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; row.add_child(value_label); _value_labels[key]=value_label
	var plus := Button.new(); plus.text="+"; plus.focus_mode=Control.FOCUS_NONE; plus.pressed.connect(func(): _change(key,step)); row.add_child(plus)
	_update_label(key)

func _change(key: String, delta: float) -> void:
	var old: Variant = values[key]
	var next: Variant = float(old) + delta
	if old is int: next = maxi(0, roundi(float(next)))
	else: next = maxf(0.0, float(next))
	if key == "ram_hard_mb": next = maxi(int(next), int(values.ram_target_mb))
	if key == "ram_target_mb": values.ram_hard_mb = maxi(int(values.ram_hard_mb), int(next))
	values[key] = next; _update_label(key); _update_label("ram_hard_mb")
	tuning_changed.emit(values.duplicate(true), key, old, next)

func _update_label(key: String) -> void:
	if not _value_labels.has(key): return
	var value: Variant = values[key]
	var suffix := ""
	if key.ends_with("_px"): suffix=" px"
	elif key.ends_with("_m"): suffix=" m"
	elif key.ends_with("_mb"): suffix=" MB"
	elif key == "streaming_ms": suffix=" ms"
	_value_labels[key].text = ("%.2f" % float(value) if value is float else str(value)) + suffix

func snapshot() -> Dictionary: return values.duplicate(true)
