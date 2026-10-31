# the router's `pdf` route — reference

Dense code patterns, JSON schemas, and CLI catalogs for SKILL.md. Read on demand; SKILL.md carries the workflow and critical rules.

## pypdf basics (merge / split / rotate / metadata / encrypt)

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("document.pdf")
print(f"Pages: {len(reader.pages)}")          # indices are 0-based
text = "".join(page.extract_text() for page in reader.pages)
meta = reader.metadata                         # .title .author .subject .creator

# Merge
writer = PdfWriter()
for pdf_file in ["doc1.pdf", "doc2.pdf"]:
    for page in PdfReader(pdf_file).pages:
        writer.add_page(page)
with open("merged.pdf", "wb") as f: writer.write(f)

# Split to single pages
for i, page in enumerate(reader.pages):
    w = PdfWriter(); w.add_page(page)
    with open(f"page_{i+1}.pdf", "wb") as f: w.write(f)

# Rotate
page = reader.pages[0]; page.rotate(90)        # 90° clockwise
w = PdfWriter(); w.add_page(page)
with open("rotated.pdf", "wb") as f: w.write(f)

# Encrypt / decrypt
w.encrypt("userpassword", "ownerpassword")     # after copying pages in
# reading encrypted input:
r = PdfReader("encrypted.pdf")
if r.is_encrypted: r.decrypt("password")       # wrap in try/except
```

## pdfplumber extraction (text / words / tables)

```python
import pdfplumber
import pandas as pd

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()             # layout-aware
        words = page.extract_words()           # char-level coordinates
# Coordinates: (x0, top, x1, bottom), y=0 at TOP of page

with pdfplumber.open("document.pdf") as pdf:
    all_tables = []
    for page in pdf.pages:
        for table in page.extract_tables():
            if table:
                all_tables.append(pd.DataFrame(table[1:], columns=table[0]))
if all_tables:
    pd.concat(all_tables, ignore_index=True).to_excel("extracted_tables.xlsx", index=False)
# complex layouts: adjust page.snap_tolerance / intersection_tolerance
```

## reportlab creation

```python
# Raw canvas (one-off drawing only)
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
c = canvas.Canvas("hello.pdf", pagesize=letter)
width, height = letter
c.drawString(100, height - 100, "Hello World!")
c.line(100, height - 140, 400, height - 140)
c.save()

# Platypus (multi-page documents — preferred)
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import getSampleStyleSheet
doc = SimpleDocTemplate("report.pdf", pagesize=letter)
styles = getSampleStyleSheet()
story = [
    Paragraph("Report Title", styles['Title']), Spacer(1, 12),
    Paragraph("Body text. " * 20, styles['Normal']), PageBreak(),
    Paragraph("Page 2", styles['Heading1']), Paragraph("Content", styles['Normal']),
]
doc.build(story)
```

**Sub/superscripts — never Unicode ₀₁₂/⁰¹² (black boxes in built-in fonts):**

```python
Paragraph("H<sub>2</sub>O", styles['Normal'])
Paragraph("x<super>2</super> + y<super>2</super>", styles['Normal'])
# canvas text: manually adjust font size and position instead
```

## Watermark

```python
watermark = PdfReader("watermark.pdf").pages[0]
reader, writer = PdfReader("document.pdf"), PdfWriter()
for page in reader.pages:
    page.merge_page(watermark); writer.add_page(page)
with open("watermarked.pdf", "wb") as f: writer.write(f)
```

## OCR (scanned PDFs)

```python
import pytesseract
from pdf2image import convert_from_path

images = convert_from_path('scanned.pdf')
text = "\n\n".join(
    f"Page {i+1}:\n{pytesseract.image_to_string(img)}"
    for i, img in enumerate(images)
)
```

## CLI catalogs

```bash
# pdftotext (poppler-utils)
pdftotext input.pdf output.txt               # plain
pdftotext -layout input.pdf output.txt       # preserve layout
pdftotext -f 1 -l 5 input.pdf output.txt     # pages 1-5

# qpdf
qpdf --empty --pages file1.pdf file2.pdf -- merged.pdf
qpdf input.pdf --pages . 1-5 -- pages1-5.pdf
qpdf input.pdf output.pdf --rotate=+90:1     # rotate page 1
qpdf --password=mypassword --decrypt encrypted.pdf decrypted.pdf
qpdf --check corrupted.pdf                   # diagnose
qpdf --fix-qdf damaged.pdf repaired.pdf      # repair

# pdfimages (poppler-utils)
pdfimages -j input.pdf output_prefix         # → prefix-000.jpg, prefix-001.jpg, …
```

## Form JSON schemas

**`field_values.json` (fillable, 2A):**

```json
[
  {"field_id": "last_name", "description": "The user's last name", "page": 1, "value": "Simpson"},
  {"field_id": "Checkbox12", "description": "Checked if user is 18 or over", "page": 1, "value": "/On"}
]
```

`field_id`/`page` must match `field_info.json`; checkboxes use `checked_value`/`unchecked_value`; radio groups use one of `radio_options[].value`.

**`fields.json` (non-fillable, Approach A — PDF points):**

```json
{
  "pages": [{"page_number": 1, "pdf_width": 612, "pdf_height": 792}],
  "form_fields": [{
    "page_number": 1, "description": "Last name entry field",
    "field_label": "Last Name",
    "label_bounding_box": [43, 63, 87, 73],
    "entry_bounding_box": [92, 63, 260, 79],
    "entry_text": {"text": "Smith", "font_size": 10}
  }]
}
```

**`fields.json` (Approach B — image pixels):** same shape, but `pages` uses `{"page_number": 1, "image_width": 1700, "image_height": 2200}` and pixel coordinates refined by cropping (`magick page.png -crop WxH+X+Y +repage`), with crop offsets added back to in-crop coordinates.

## Performance

- Large PDFs: stream/process pages individually, chunk very large files
- Plain text: `pdftotext -bbox-layout` is fastest
- Images: `pdfimages` is much faster than rendering pages
