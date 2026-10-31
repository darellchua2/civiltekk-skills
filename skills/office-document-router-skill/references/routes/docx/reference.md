# the router's `docx` route — reference

Dense code patterns and XML reference for SKILL.md. Read on demand; SKILL.md carries the workflow and critical rules.

## docx-js setup

```javascript
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun,
        Header, Footer, AlignmentType, PageOrientation, LevelFormat, ExternalHyperlink,
        InternalHyperlink, Bookmark, FootnoteReferenceRun, PositionalTab,
        PositionalTabAlignment, PositionalTabRelativeTo, PositionalTabLeader,
        TabStopType, TabStopPosition, Column, SectionType,
        TableOfContents, HeadingLevel, BorderStyle, WidthType, ShadingType,
        VerticalAlign, PageNumber, PageBreak } = require('docx');

const doc = new Document({ sections: [{ children: [/* content */] }] });
Packer.toBuffer(doc).then(buffer => fs.writeFileSync("doc.docx", buffer));
```

## Page size / margins / landscape

```javascript
sections: [{
  properties: {
    page: {
      size: { width: 12240, height: 15840 },           // US Letter, DXA (1440 = 1")
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } // 1" margins
    }
  },
  children: [/* content */]
}]
```

| Paper | Width | Height | Content width (1" margins) |
|---|---|---|---|
| US Letter | 12,240 | 15,840 | 9,360 |
| A4 (docx-js default) | 11,906 | 16,838 | 9,026 |

Landscape: pass PORTRAIT dimensions (`width: 12240, height: 15840`) + `orientation: PageOrientation.LANDSCAPE` — docx-js swaps internally; content width uses the long edge.

## Styles (override built-in headings)

```javascript
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 24 } } }, // 12pt
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 32, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 240, after: 240 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial" },
        paragraph: { spacing: { before: 180, after: 180 }, outlineLevel: 1 } },
    ]
  },
  sections: [{ children: [
    new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Title")] }),
  ]}]
});
```

## Lists

```javascript
const doc = new Document({
  numbering: { config: [
    { reference: "bullets",
      levels: [{ level: 0, format: LevelFormat.BULLET, text: "*", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    { reference: "numbers",
      levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
  ]},
  sections: [{ children: [
    new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun("Bullet item")] }),
    new Paragraph({ numbering: { reference: "numbers", level: 0 }, children: [new TextRun("Numbered item")] }),
  ]}]
});
// same reference = continues (1,2,3 → 4,5,6); different reference = restarts
```

## Tables

```javascript
const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };

new Table({
  width: { size: 9360, type: WidthType.DXA },   // US Letter content width: 12240 - 2880
  columnWidths: [4680, 4680],                   // must sum to table width
  rows: [ new TableRow({ children: [
    new TableCell({
      borders,
      width: { size: 4680, type: WidthType.DXA },           // per-cell width too
      shading: { fill: "D5E8F0", type: ShadingType.CLEAR }, // CLEAR, never SOLID
      margins: { top: 80, bottom: 80, left: 120, right: 120 },
      children: [new Paragraph({ children: [new TextRun("Cell")] })]
    })
  ]})]
})
```

## Images / page breaks / hyperlinks / TOC / headers-footers

```javascript
new Paragraph({ children: [new ImageRun({
  type: "png",                                              // REQUIRED
  data: fs.readFileSync("image.png"),
  transformation: { width: 200, height: 150 },
  altText: { title: "Title", description: "Desc", name: "Name" } // all three
})]})

new Paragraph({ children: [new PageBreak()] })               // inside Paragraph, always
new Paragraph({ pageBreakBefore: true, children: [new TextRun("New page")] })

new Paragraph({ children: [new ExternalHyperlink({
  children: [new TextRun({ text: "Click here", style: "Hyperlink" })],
  link: "https://example.com" })]})
// internal: Bookmark({ id: "chapter1", ... }) + InternalHyperlink({ anchor: "chapter1" })

new TableOfContents("Table of Contents", { hyperlink: true, headingStyleRange: "1-3" })

// headers/footers per section:
headers: { default: new Header({ children: [new Paragraph({ children: [new TextRun("Header")] })] }) },
footers: { default: new Footer({ children: [new Paragraph({
  children: [new TextRun("Page "), new TextRun({ children: [PageNumber.CURRENT] })] })] }) }
```

## XML editing reference

**Schema compliance:** `<w:pPr>` child order = `<w:pStyle>`, `<w:numPr>`, `<w:spacing>`, `<w:ind>`, `<w:jc>`, `<w:rPr>` last · `xml:space="preserve"` on `<w:t>` with edge whitespace · RSIDs are 8-digit hex.

**Tracked changes:**

```xml
<w:ins w:id="1" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:t>inserted text</w:t></w:r>
</w:ins>
<w:del w:id="2" w:author="Claude" w:date="2025-01-01T00:00:00Z">
  <w:r><w:delText>deleted text</w:delText></w:r>   <!-- delText inside w:del, never w:t -->
</w:del>
```

**Comments** — range markers are SIBLINGS of `<w:r>`, never inside it:

```xml
<w:commentRangeStart w:id="0"/>
<w:r><w:t>text</w:t></w:r>
<w:commentRangeEnd w:id="0"/>
<w:r><w:rPr><w:rStyle w:val="CommentReference"/></w:rPr><w:commentReference w:id="0"/></w:r>
```

**Images (4 steps):** file → `word/media/` · relationship → `word/_rels/document.xml.rels` (`<Relationship Id="rId5" Type=".../image" Target="media/image1.png"/>`) · content type → `[Content_Types].xml` (`<Default Extension="png" ContentType="image/png"/>`) · reference in document.xml:

```xml
<w:drawing><wp:inline>
  <wp:extent cx="914400" cy="914400"/>   <!-- EMUs: 914400 = 1 inch -->
  <a:graphic><a:graphicData uri=".../picture"><pic:pic>
    <pic:blipFill><a:blip r:embed="rId5"/></pic:blipFill>
  </pic:pic></a:graphicData></a:graphic>
</wp:inline></w:drawing>
```

## Typography and per-type aesthetics

| Element | Styling |
|---|---|
| Title | 28–36pt Bold, accent color or black |
| Heading 1 | 20–24pt Bold, accent color |
| Heading 2 | 16–18pt Bold, dark gray |
| Body | 11–12pt Regular, black |
| Captions | 9–10pt Italic, medium gray |
| Table headers | 10–11pt Bold, white on colored fill |

| Document type | Style | Characteristics |
|---|---|---|
| Financial report | Corporate minimal | clean tables, blue/dark-gray palette, precise alignment |
| Technical spec | Swiss/International | grid-based, monospace code, restrained color |
| Marketing brief | Modern professional | accent colors, pull quotes, varied density |
| Legal/contract | Formal traditional | generous margins, serif feel, numbered sections |
| Proposal | Confident & bold | strong hierarchy, branded accents |

## Troubleshooting

- **Won't open after edit** → check `<w:pPr>` element order; `xml:space="preserve"`; re-run `validate.py`
- **Tables wrong in Google Docs** → DXA not percentage; `columnWidths` sum = table width; per-cell widths set
- **Images broken** → all 4 steps above present; `r:embed` matches relationship Id
