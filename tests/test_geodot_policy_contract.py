from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
policy = (ROOT / "scripts/geodot_streaming_policy.gd").read_text()
renderer = (ROOT / "scripts/geodot_world_renderer.gd").read_text()

assert "ceili(max_point.x / size) - 1" in policy
assert "ceili(max_point.y / size) - 1" in policy
assert "cell_range_for_bounds" in renderer
assert "candidates[index][\"cell\"] as Vector2i" not in renderer
print("geodot policy static contract: OK")
