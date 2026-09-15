from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "pr_check_local.sh"


def test_geodot_handoff_requires_objective_completion_marker():
    text = SCRIPT.read_text(encoding="utf-8")
    objective = text.index("PR_CHECK=GEODOT_OBJECTIVE_OK")
    ready = text.index("PR_CHECK=HANDOFF_READY objective=geodot")
    visual = text.index("PR_CHECK=VISUAL_REVIEW pr=")
    assert objective < ready < visual


def test_objective_stages_emit_begin_ok_and_fail_diagnostics():
    text = SCRIPT.read_text(encoding="utf-8")
    assert "PR_CHECK=STAGE_BEGIN" in text
    assert "PR_CHECK=STAGE_OK" in text
    assert "PR_CHECK=STAGE_FAIL" in text
    assert 'else status=$?' in text


def test_sweden_pbf_discovery_skips_missing_search_directories():
    text = SCRIPT.read_text(encoding="utf-8")
    assert 'for dir in "$root/syndicate/data" "$root/data"' in text
    assert '[[ -d "$dir" ]] || continue' in text
    assert "tail -n1 || true" in text


def test_geodot_visual_handoff_fails_closed_without_resolved_gpkg():
    text = SCRIPT.read_text(encoding="utf-8")
    assert "refusing GeoDot visual handoff without completed GeoDot objective state" in text
