"""Shared fixtures for the pptx route tests (slide engine + template modifier).

Merged from the former pptx-generate-slide-skill and
pptx-template-modifier-skill per-skill conftests during #680 consolidation:
all engine scripts now live in this single scripts/ tree, so one sys.path
setup serves both suites.
"""
import sys
from pathlib import Path

import pytest

_SCRIPTS_DIR = Path(__file__).resolve().parent.parent   # .../office-document-router-skill/scripts
sys.path.insert(0, str(_SCRIPTS_DIR))

# Shared extraction/contract infra lives in scripts/_common.
_COMMON_SCRIPTS = _SCRIPTS_DIR / "_common"
if str(_COMMON_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_COMMON_SCRIPTS))


@pytest.fixture
def template_path(tmp_path):
    """BT-142 Phase 2.3: synthesize a minimal valid template in tmp_path.

    Previously read ``template/default.pptx`` at the repo root — that bundled
    default is removed per the user's "no bundled default" invariant. The
    fixture now uses ``master_repairer._build_minimal_pptx_bytes(None)`` to
    produce a minimal valid PPTX (one master + one blank layout + minimal
    theme) — the same in-code fallback the production engine uses.
    """
    from master_repairer import _build_minimal_pptx_bytes
    p = tmp_path / "default.pptx"
    p.write_bytes(_build_minimal_pptx_bytes(None))
    return str(p)


@pytest.fixture
def output_path(tmp_path):
    return str(tmp_path / "test_output.pptx")


@pytest.fixture
def bar_chart_data():
    return {
        "slide_type": "chart_slide",
        "title": "Market Growth",
        "chart_type": "bar",
        "categories": ["2020", "2021", "2022", "2023"],
        "series": [
            {"name": "Revenue", "values": [8.5, 11.2, 14.8, 19.5]},
        ],
        "chart_options": {
            "legend_position": "bottom",
            "show_data_labels": True,
            "y_axis_min": 0,
            "y_axis_max": 25,
        },
        "notes": "Revenue growing steadily.",
    }


@pytest.fixture
def pie_chart_data():
    return {
        "slide_type": "chart_slide",
        "title": "Adoption Rates",
        "chart_type": "pie",
        "categories": ["BIM", "IoT", "Drones", "AI"],
        "series": [
            {"name": "Adoption", "values": [68, 45, 52, 28]},
        ],
        "chart_options": {
            "legend_position": "right",
        },
        "notes": "BIM leads adoption.",
    }


@pytest.fixture
def line_chart_data():
    return {
        "slide_type": "chart_slide",
        "title": "Performance Trends",
        "chart_type": "line_markers",
        "categories": ["Q1", "Q2", "Q3", "Q4"],
        "series": [
            {"name": "Cost Savings", "values": [5, 8, 12, 16]},
            {"name": "Efficiency", "values": [3, 6, 10, 14]},
        ],
        "chart_options": {
            "legend_position": "bottom",
            "y_axis_min": 0,
            "y_axis_max": 20,
        },
        "notes": "Both metrics trending up.",
    }


@pytest.fixture
def mixed_deck(bar_chart_data, pie_chart_data, line_chart_data):
    return [
        {"slide_type": "title_slide", "title": "Test Deck", "subtitle": "2026"},
        {"slide_type": "content_slide", "title": "Overview", "body": "**Point A** - desc\n**Point B** - desc"},
        bar_chart_data,
        pie_chart_data,
        line_chart_data,
        {"slide_type": "closing_slide", "title": "Thanks", "subtitle": "Q&A"},
    ]


# ---------------------------------------------------------------------------
# Phase 1 fixtures — image support (#18) / resolver pipeline (#23)
# ---------------------------------------------------------------------------
@pytest.fixture
def sample_image(tmp_path):
    """A real small PNG file on disk (native-picture tests need a real file)."""
    from PIL import Image

    p = tmp_path / "sample.png"
    Image.new("RGB", (320, 240), (60, 120, 200)).save(p)
    return str(p)


@pytest.fixture
def image_slide_data(sample_image):
    return {
        "slide_type": "content_image_slide",
        "title": "Field Example",
        "body": "**Drones** - aerial survey",
        "image_path": sample_image,
        "image_position": "full",
        "notes": "Drones cut survey time.",
    }
