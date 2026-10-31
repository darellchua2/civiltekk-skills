# Research: Native Chart Generation — python-pptx Internals

> Pre-implementation research for issue #3 (2026-06-15). The JSON schema,
> chart-type mapping, and examples now live authoritatively in `SKILL.md` and
> `slide_schemas.py`. **This document is kept only for the hard-won
> python-pptx API knowledge and layout/EMU analysis that is not captured
> elsewhere.**

---

## 1. Environment

| Item             | Value                                                                  |
| ---------------- | ---------------------------------------------------------------------- |
| python-pptx      | **1.0.2** (stable release)                                             |
| Python           | 3.12                                                                   |
| Template         | `template.pptx` — 35 layouts, 16:9 widescreen (13.33in × 7.50in)      |
| Chart data class | `CategoryChartData` (supports categories + named series with values)  |
| Chart placement  | `SlideShapes.add_chart(chart_type, x, y, cx, cy, chart_data)`         |

---

## 2. Layout Analysis

### Why Layout [9] `Blank` (not Layout [6] `1_Blank`)

| Layout Index | Name      | Has TITLE? | Usable Chart Area (W × H) |
| ------------ | --------- | ---------- | ------------------------- |
| 6            | `1_Blank` | No         | 13.33in × 7.50in (full)   |
| 9            | `Blank`   | **Yes**    | 11.5in × 4.5in (below title) |

Layout [9] wins because it has a TITLE placeholder (idx=0, type=TITLE) that the
engine's `_find_title_placeholder()` already handles — chart slides get
consistent titles with all other slide types. Footer + Slide Number + Date
placeholders are also preserved.

### Chart Positioning (EMU values)

```
┌─────────────────────────────────────────────────┐  ← 0.0in
│    [TITLE PLACEHOLDER]                          │  ← top: 0.40in, h: 1.45in
├─────────────────────────────────────────────────┤  ← 2.0in
│         [CHART GRAPHIC FRAME]                   │  ← top: 2.0in
│         left: 0.92in  width: 11.5in             │
│         height: 4.5in                           │
├─────────────────────────────────────────────────┤  ← 6.5in
│ [Date]    [Footer]        [Slide #]             │  ← 6.95in (footer area)
└─────────────────────────────────────────────────┘  ← 7.50in
```

| Parameter | Value   | EMU        |
| --------- | ------- | ---------- |
| `x`       | 0.92 in | 840,528    |
| `y`       | 2.0 in  | 1,828,800  |
| `cx`      | 11.5 in | 10,515,600 |
| `cy`      | 4.5 in  | 4,114,800  |

---

## 3. python-pptx Chart API Findings

### 3.1 Chart Data: `CategoryChartData`

```python
from pptx.chart.data import CategoryChartData

chart_data = CategoryChartData()
chart_data.categories = ['2020', '2021', '2022']       # X-axis labels
chart_data.add_series('Market Size', (8.5, 11.2, 14.8)) # Named data series
chart_data.add_series('Forecast',     (9.0, 12.0, 15.5)) # Multiple series supported
```

- `categories` accepts a list/tuple of strings.
- `add_series(name, values, number_format=None)` — `values` is any iterable of numbers.
- Multiple series are fully supported (critical for grouped/stacked bar and multi-series line).

### 3.2 Chart Creation: `SlideShapes.add_chart()`

```python
graphic_frame = slide.shapes.add_chart(
    XL_CHART_TYPE.COLUMN_CLUSTERED,   # chart type enum
    Inches(0.92), Inches(2.0),        # x, y position
    Inches(11.5), Inches(4.5),        # cx, cy size
    chart_data,                        # CategoryChartData
)
chart = graphic_frame.chart  # Access the Chart object for styling
```

- Returns a `GraphicFrame`, NOT a `Chart` directly. Access via `.chart`.
- The chart is a **native PowerPoint chart object** (editable in PowerPoint, not a static image).

### 3.3 Relevant `XL_CHART_TYPE` Values

The 9 chart types used by the engine (single source of truth: `_CHART_TYPE_MAP`
in `ppt_builder.py`):

| Chart Category | XL_CHART_TYPE Enum       | Value | Use Case                          |
| -------------- | ------------------------ | ----- | --------------------------------- |
| **Bar**        | `COLUMN_CLUSTERED`       | 51    | Vertical bars (default)           |
|                | `COLUMN_STACKED`         | 52    | Stacked vertical bars             |
|                | `BAR_CLUSTERED`          | 57    | Horizontal bars                   |
|                | `BAR_STACKED`            | 58    | Stacked horizontal bars           |
| **Pie**        | `PIE`                    | 5     | Standard pie chart                |
|                | `PIE_EXPLODED`           | 69    | Exploded pie                      |
|                | `DOUGHNUT`               | -4120 | Doughnut chart                    |
| **Line**       | `LINE`                   | 4     | Simple line                       |
|                | `LINE_MARKERS`           | 65    | Line with data point markers (recommended) |

### 3.4 Styling Capabilities

**Chart-level:**
| Property                       | Type | Example                          |
| ------------------------------ | ---- | -------------------------------- |
| `chart.has_title`              | bool | `True` / `False`                 |
| `chart.has_legend`             | bool | `True`                           |
| `chart.legend.position`        | enum | `XL_LEGEND_POSITION.BOTTOM`      |
| `chart.legend.include_in_layout` | bool | `False` (overlay, don't shrink plot) |
| `chart.font`                   | Font | `chart.font.size = Pt(12)`       |

**Plot-level (per series group):**
| Property                       | Type | Example                          |
| ------------------------------ | ---- | -------------------------------- |
| `plot.has_data_labels`         | bool | `True`                           |
| `plot.data_labels.font.size`   | Pt   | `Pt(10)`                         |
| `plot.data_labels.position`    | enum | `XL_LABEL_POSITION.OUTSIDE_END`  |
| `plot.data_labels.show_percentage` | bool | `True` (for pie charts)      |
| `plot.data_labels.show_value`  | bool | `True` (for bar/line charts)     |
| `plot.gap_width` (Bar only)    | int  | `150` (gap between bar groups)   |

**Axis-level (CategoryAxis / ValueAxis):**
| Property                           | Type  | Example                      |
| ---------------------------------- | ----- | ---------------------------- |
| `value_axis.minimum_scale`         | float | `0`                          |
| `value_axis.maximum_scale`         | float | `45`                         |
| `value_axis.has_major_gridlines`   | bool  | `True`                       |
| `value_axis.major_unit`            | float | `5`                          |
| `category_axis.tick_label_position`| enum  | `XL_TICK_LABEL_POSITION.LOW` |

### 3.5 Limitations & Gotchas

1. **No Plot class export** — `from pptx.chart.plot import Plot` fails; must use `_BasePlot` or type-specific classes (`BarPlot`, `PiePlot`, `LinePlot`). Access via `chart.plots[0]`.
2. **No Series class export** — `from pptx.chart.series import Series` fails; use `_BaseSeries`. Access via `plot.series[i]`.
3. **Theme color extraction** — python-pptx does NOT expose a simple API to read theme colors from `template.pptx`. The engine works around this by parsing `theme1.xml` directly and extracting `accent1`–`accent6` + `dk2` + `accent3` into `_CHART_COLORS` (see `ppt_builder.py`). This is a custom solution, not a library feature.
4. **Pie chart data label positioning** — `OUTSIDE_END` works for pie charts but may overlap with small slices. `BEST_FIT` is more robust but not always available. This remains a known minor visual issue.
