# the router's `slides` route — reference

Dense code patterns, schema tables, and format internals for SKILL.md. Read on demand; SKILL.md carries the workflow and critical rules.

## Full field reference

| Field | Required | Slide Type | Description |
|-------|----------|------------|-------------|
| `slide_type` | Yes | All | One of: `title_slide`, `content_slide`, `section_header_slide`, `two_content_slide`, `comparison_slide`, `content_image_slide`, `chart_slide`, `closing_slide` |
| `title` | Yes | All | Main heading text |
| `subtitle` | No | `title_slide`, `closing_slide` | Subheading. On `closing_slide`, omit — the `End` layout's built-in sign-off block shows by default. |
| `body` | No | `content_slide`, `content_image_slide` | `\n` = new paragraph. Format: `**Title** — Description` |
| `body_left` / `body_right` | No | `two_content_slide`, `comparison_slide` | Left/right column body (same body format) |
| `chart_type` | Yes | `chart_slide` | See chart type table |
| `categories` | Yes | `chart_slide` | Array of category labels (X-axis or pie slice labels) |
| `series` | Yes | `chart_slide` | Array of `{name, values}`; multiple series supported for bar/line |
| `chart_options` | No | `chart_slide` | Styling options (table below) |
| `image_path` | No | `content_image_slide` + any | Local file path embedded as a native, editable picture |
| `image_position` | No | any slide with `image_path` | `full`, `half-left`, `half-right`, `below-title` (default) |
| `image_size` | No | any slide with `image_path` | `{"width": inches, "height": inches}` override of the preset box |
| `data_query` | No | `chart_slide` | Resource placeholder — resolver fills `categories`/`series` with sourced numbers |
| `data_hint` | No | `chart_slide` | Optional expected shape for `data_query` |
| `notes` | Yes | All | Full presenter script (~120–180 words), four-part structure (SKILL.md) |
| `presenter_name` | No | `closing_slide` | Sign-off name; omit on first generation (engine removes the placeholder) |
| `presenter_email` | No | `closing_slide` | Sign-off email; same lifecycle as `presenter_name` |

## Chart types (`chart_slide`)

Native PowerPoint charts via `python-pptx` `add_chart()` — editable in PowerPoint, never images. Charts use the `Blank` layout (TITLE placeholder + free space).

| `chart_type` | XL_CHART_TYPE | Description |
|---|---|---|
| `bar` | COLUMN_CLUSTERED | Vertical bars (default) |
| `bar_stacked` | COLUMN_STACKED | Stacked vertical bars |
| `bar_horizontal` | BAR_CLUSTERED | Horizontal bars |
| `bar_horizontal_stacked` | BAR_STACKED | Stacked horizontal bars |
| `pie` | PIE | Standard pie chart |
| `pie_exploded` | PIE_EXPLODED | Exploded pie chart |
| `doughnut` | DOUGHNUT | Doughnut chart |
| `line` | LINE | Simple line chart |
| `line_markers` | LINE_MARKERS | Line with data point markers (recommended) |

## Chart options

All fields inside `chart_options` are optional with defaults:

| Option | Type | Default | Description |
|---|---|---|---|
| `legend_position` | string | `"bottom"` | `"bottom"`, `"right"`, `"top"`, `"left"`, `"none"` |
| `show_data_labels` | bool | `true` | Show value/percentage labels |
| `value_format` | string | `"#,##0.0"` | Number format for bar/line data labels |
| `y_axis_format` | string | `"#,##0.0"` | Y-axis tick label format |
| `y_axis_min` / `y_axis_max` | float | auto | Y-axis scale bounds |
| `y_axis_major_unit` | float | auto | Major gridline interval |
| `y_axis_title` / `x_axis_title` | string | `""` | Axis title text |

Theme styling: colors from theme accents (`accent1`–`accent6` + `dk2`), `Calibri` text, gridlines `#E7E6E6` 0.75pt, axis text `#44546A`.

## Chart JSON examples

```json
{"slide_type": "chart_slide", "title": "Market (USD Billion)", "chart_type": "bar",
 "categories": ["2020","2021","2022","2023","2024","2025","2026"],
 "series": [{"name": "Market Size", "values": [8.5, 11.2, 14.8, 19.5, 25.1, 31.7, 39.4]}],
 "chart_options": {"legend_position": "bottom", "show_data_labels": true, "y_axis_min": 0, "y_axis_max": 45},
 "notes": "KEY MESSAGE: Market growing to 39.4B by 2026."}

{"slide_type": "chart_slide", "title": "Technology Adoption Rate", "chart_type": "pie",
 "categories": ["BIM","IoT","Drones","AI & ML","Robotics","Cloud"],
 "series": [{"name": "Adoption %", "values": [68, 45, 52, 28, 15, 72]}],
 "chart_options": {"legend_position": "right"},
 "notes": "KEY MESSAGE: Cloud and BIM lead adoption."}

{"slide_type": "chart_slide", "title": "Improvement (%)", "chart_type": "line_markers",
 "categories": ["2019","2020","2021","2022","2023","2024","2025"],
 "series": [
   {"name": "Cost Savings",       "values": [5, 8, 12, 16, 20, 25, 30]},
   {"name": "Schedule Reduction", "values": [3, 6, 10, 14, 19, 24, 28]},
   {"name": "Safety Improvement", "values": [2, 4,  8, 12, 18, 22, 27]}],
 "chart_options": {"legend_position": "bottom", "y_axis_min": 0, "y_axis_max": 35},
 "notes": "KEY MESSAGE: All three metrics improve consistently."}
```

## Image placement presets

| Preset | Region |
|--------|--------|
| `full` | Below title, full width (~11.5" × 4.5") |
| `below-title` | Same as `full` (default) |
| `half-left` | Left half (~5.75" × 4.5") |
| `half-right` | Right half (~5.75" × 4.5") |

```json
{"slide_type": "content_image_slide", "title": "Drone Surveying in Action",
 "body": "**Aerial scans** - cut survey time by 60%",
 "image_path": "output/site_photo.png", "image_position": "full", "notes": "KEY MESSAGE: ..."}
```

Images are embedded (not linked) — self-contained PPTX. A PICTURE placeholder (e.g. `content_image_slide` → `Picture with Caption`) is filled when present; otherwise the preset box is used.

## Execution patterns

```bash
# Full render (library API)
python -c "
import json, sys
sys.path.insert(0, 'scripts')
from ppt_builder import generate_ppt_from_data, DEFAULT_OUTPUT_DIR
slide_data = <JSON_ARRAY>
result = generate_ppt_from_data(
    slide_data,
    output_path=str(DEFAULT_OUTPUT_DIR / 'report.pptx'),
    target_size=None,  # '4:3' / '16:9' / '1:1' / {'width_in':..,'height_in':..} or None (native)
)
print(result)  # absolute path
"

# Capability check — which slide types a template can serve
python -c "
import sys, json; sys.path.insert(0,'scripts')
from ppt_builder import servable_slide_types, get_render_contract
print(json.dumps(servable_slide_types(get_render_contract('template/default.pptx')), indent=2))
"
# → e.g. {"content_slide": {"available": true, "layout": "Content Page", "content_area_in2": 42.1}, ...}
#   Layout NAME may differ from the default — fingerprint matching still resolves it.

# Schema validation probe
python -c "
import sys; sys.path.insert(0,'scripts')
from schema_validator import validate_slide_data_list
res = validate_slide_data_list(<JSON_ARRAY>, strict=True, density_mode='standard')
print('VALID' if res.is_valid else 'INVALID')
for m in res.error_messages() + res.warning_messages(): print('-', m)
"

# Density probe
python -c "
import sys; sys.path.insert(0,'scripts')
from density_mode import DENSITY_BUDGETS, count_slide_words, validate_density
print(DENSITY_BUDGETS)   # {'concise': (0, 10), 'standard': (30, 50), 'text-heavy': (75, 150)}
print(validate_density(<JSON_ARRAY>, 'standard'))  # [] when all in budget
"

# Resource resolution (before rendering)
python -c "
import sys; sys.path.insert(0,'scripts')
from resolvers import resolve_slide_data_list
resolved = resolve_slide_data_list(<JSON_ARRAY>)   # uses resolver.config.json
"

# Read 2-3 notes from the newest output deck (house-style verification)
python -c "
import sys, glob, os; sys.stdout.reconfigure(encoding='utf-8')
sys.path.insert(0,'scripts')
from pptx import Presentation
fs = sorted(glob.glob('output/*.pptx'), key=os.path.getmtime, reverse=True)
if fs:
    prs = Presentation(fs[0]); slides = list(prs.slides)
    for i in range(min(3, len(slides))):
        print('===== S%d =====' % i, slides[i].notes_slide.notes_text_frame.text)
"
```

User-supplied template end-to-end: set `TPL=~/my_company_template.pptx`, run the capability check above against `'$TPL'`, then `generate_ppt_from_data(slide_data, template_path='$TPL', output_path=…)` — the output uses the user template's own layouts, theme, and master.

## Error handling table

| Scenario | Behavior |
|----------|----------|
| `slide_data_list` not a JSON array | Raise `ValidationError` (fatal, clear message) |
| Structural schema violation (strict mode) | Raise `ValidationError` with slide index + field path |
| Unknown `slide_type` | Log warning, skip, continue |
| Missing placeholder | Log warning, skip field, continue |
| Single slide fails | Log error, skip slide, continue |
| Template file missing | Raise `FileNotFoundError` (fatal) |
| Severe template problems | Raise `TemplateError` (fatal) |
| Unknown `chart_type` | Default to `bar`, log warning |
| Missing `categories` or `series` | Skip chart, log warning |
| Invalid `chart_options` field | Ignore, use default |
| `image_path` file not found | Skip image, log warning |
| Unknown `image_position` | Default to `below-title`, log warning |
| Resolver provider unconfigured / fetch failed | Skip asset, log warning (non-fatal) |
| Slide over/under density budget | Validation warning (non-fatal, never blocks, even in strict mode) |

## Speaker notes — GOOD example

```
KEY MESSAGE: BIM catches clashes on screen — not on site.
"Hold the slide for a second — let them take in the model."
"BIM gives every discipline one shared digital model, so clashes are caught on screen, weeks before anyone pours concrete."
Pause. Let the number land.
"In our pilots, automated clash detection cut rework by up to thirty percent."
TRANSITION: "Now let's take this same data out onto the construction site."
COACHING: Matter-of-fact tone, don't over-sell. Be ready for: "Does BIM work with non-IFC models?" — we ingest seven formats.
```
