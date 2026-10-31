"""pptx_validate.py — post-build validation gate for generated/promoted PPTX files.

python-pptx and lxml stay silent on defects that make PowerPoint show the
"needs repair" dialog. This script is the gate: it runs static OOXML checks,
optionally auto-fixes the two safe classes (--fix), and optionally performs
the authoritative open test in real PowerPoint via COM (--com, Windows only).

Usage:
    python pptx_validate.py file.pptx [--fix] [--com]

Exit code 0 = clean (or fully fixed), 1 = defects remain.

Checks:
  1. zip integrity
  2. XML well-formedness of every .xml/.rels part
  3. [Content_Types].xml coverage for every part
  4. broken relationship targets (rel -> missing part)
  5. dangling r:* references (XML refs an rId its part's .rels doesn't define)
  6. rel-type mismatch: r:embed/r:link pointing at a structural rel
     (slideMaster/slideLayout/notesSlide) instead of image/media/video
  7. empty r:id="" attributes
  8. duplicate sldLayoutId ids across masters, and overlap with sldMasterIds
     (PowerPoint treats these as one presentation-wide uniqueness space)

--fix repairs (in place): (7) empty r:id removal, (8) id renumbering.
Dangling refs / type mismatches (5, 6) must be fixed at generation time —
see designer_promoter._remap_shape_rels.
"""

import posixpath
import re
import sys
import zipfile
from lxml import etree

P_NS = "http://schemas.openxmlformats.org/presentationml/2006/main"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS = {"p": P_NS}

STRUCTURAL_REL_SUFFIXES = ("/slideMaster", "/slideLayout", "/notesSlide", "/slide")


def _parts(z):
    return [n for n in z.namelist() if not n.endswith("/")]


def check_zip(path):
    try:
        z = zipfile.ZipFile(path)
    except Exception as e:
        return None, [f"zip open failed: {e}"]
    bad = z.testzip()
    return z, ([] if bad is None else [f"corrupt zip member: {bad}"])


def check_xml(z):
    errs = []
    for n in _parts(z):
        if n.endswith((".xml", ".rels")):
            try:
                etree.fromstring(z.read(n))
            except Exception as e:
                errs.append(f"XML parse fail {n}: {e}")
    return errs


def check_content_types(z, names):
    ct = z.read("[Content_Types].xml").decode()
    overrides = set(re.findall(r'PartName="([^"]+)"', ct))
    defaults = set(re.findall(r'Extension="([^"]+)"', ct))
    return [
        f"no content-type for {n}"
        for n in names
        if "/" + n not in overrides and n.rsplit(".", 1)[-1] not in defaults
    ]


def _defined_rids(z, relpath, names):
    if relpath not in names:
        return {}, set()
    root = etree.fromstring(z.read(relpath))
    rels = {r.get("Id"): r for r in root}
    return rels, set(rels)


def check_rels(z, names):
    """Broken targets, dangling refs, type mismatches, empty r:id."""
    broken, dangling, mismatch, empty = [], [], [], []
    for n in names:
        if n.endswith(".rels"):
            base = posixpath.dirname(posixpath.dirname(n))
            for rel in etree.fromstring(z.read(n)):
                if rel.get("TargetMode") == "External":
                    continue
                p = posixpath.normpath(posixpath.join(base, rel.get("Target")))
                if p not in names:
                    broken.append(f"{n}: missing target {rel.get('Target')}")
        m = re.match(r"(ppt/[\w]+)/([^/]+\.xml)$", n)
        if not m:
            continue
        relpath = posixpath.join(m.group(1), "_rels", m.group(2) + ".rels")
        rels, defined = _defined_rids(z, relpath, names)
        root = etree.fromstring(z.read(n))
        for e in root.iter():
            for a, v in e.attrib.items():
                if not a.startswith("{" + R_NS + "}"):
                    continue
                if v == "":
                    empty.append(f"{n}: empty r:id on <{etree.QName(e).localname}>")
                elif v not in defined:
                    dangling.append(f"{n}: dangling ref {v} on <{etree.QName(e).localname}>")
                elif a.endswith(("}embed", "}link")):
                    rt = rels[v].get("Type", "")
                    if rt.endswith(STRUCTURAL_REL_SUFFIXES):
                        mismatch.append(
                            f"{n}: {v} ({etree.QName(e).localname}) points at structural rel {rt}"
                        )
    return broken, dangling, mismatch, empty


def _layout_ids(z, names):
    """(master_part_name, element) pairs + presentation sldMasterId values."""
    masters = []
    for n in names:
        if re.match(r"ppt/slideMasters/slideMaster\d+\.xml$", n):
            root = etree.fromstring(z.read(n))
            ids = [int(e.get("id")) for e in root.findall(".//p:sldLayoutId", NS)]
            masters.append((n, ids))
    pres = etree.fromstring(z.read("ppt/presentation.xml"))
    master_ids = [int(e.get("id")) for e in pres.findall(".//p:sldMasterId", NS)]
    return masters, master_ids


def check_ids(z, names):
    masters, master_ids = _layout_ids(z, names)
    all_lids = [i for _, ids in masters for i in ids]
    dups = sorted({i for i in all_lids if all_lids.count(i) > 1})
    overlap = sorted(set(master_ids) & set(all_lids))
    errs = [f"duplicate sldLayoutId {i} across masters" for i in dups]
    errs += [f"sldLayoutId {i} collides with a sldMasterId" for i in overlap]
    return errs


def fix_file(path):
    """In-place: renumber colliding layout ids, drop empty r:id attrs."""
    tmp = path + ".fixed"
    zin = zipfile.ZipFile(path)
    names = zin.namelist()
    out = {}
    # --- renumber ids (presentation-wide uniqueness) ---
    masters, master_ids = _layout_ids(zin, names)
    all_lids = [i for _, ids in masters for i in ids]
    used = set(all_lids) | set(master_ids)
    bad = {i for i in all_lids if all_lids.count(i) > 1} | (set(master_ids) & set(all_lids))
    nxt = max(used) + 1 if used else 2147483648
    for n, _ in masters:
        root = etree.fromstring(zin.read(n))
        dirty = False
        for e in root.findall(".//p:sldLayoutId", NS):
            if int(e.get("id")) in bad:
                while nxt in used:
                    nxt += 1
                e.set("id", str(nxt))
                used.add(nxt)
                dirty = True
        if dirty:
            out[n] = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
    # --- empty r:id removal ---
    for n in names:
        if n in out or not n.endswith(".xml"):
            continue
        root = etree.fromstring(zin.read(n))
        dirty = False
        for e in root.iter():
            for a in list(e.attrib):
                if a.startswith("{" + R_NS + "}") and e.attrib[a] == "":
                    del e.attrib[a]
                    dirty = True
        if dirty:
            out[n] = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
    if out:
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
            for item in names:
                z.writestr(item, out.get(item, zin.read(item)))
        zin.close()
        import shutil

        shutil.move(tmp, path)
    zin.close() if not out else None
    return len(out)


def com_open_test(path):
    """Authoritative gate: open in real PowerPoint via COM (pywin32).

    PowerPoint hard-fails COM open on repair-worthy files while python-pptx
    stays silent. Kill lingering POWERPNT.EXE after a failure before retesting
    (a hidden modal blocks later opens). HRESULT 0x80070070 is PowerPoint's
    generic open-failure code here, not an actual disk-full condition.
    """
    import win32com.client

    ppt = win32com.client.Dispatch("PowerPoint.Application")
    try:
        pres = ppt.Presentations.Open(path, ReadOnly=True, WithWindow=False)
        info = (pres.Slides.Count, pres.Designs.Count)
        pres.Close()
        return True, f"opened OK (slides={info[0]}, designs={info[1]})"
    except Exception as e:
        return False, f"PowerPoint refused to open: {e}"
    finally:
        ppt.Quit()


def main(argv):
    import os

    path = argv[1]
    do_fix = "--fix" in argv
    do_com = "--com" in argv
    if do_fix:
        n = fix_file(path)
        print(f"--fix: rewrote {n} parts")
    z, errs = check_zip(path)
    if z is None:
        print("\n".join(errs))
        return 1
    names = set(_parts(z))
    errs += check_xml(z)
    errs += check_content_types(z, names)
    broken, dangling, mismatch, empty = check_rels(z, names)
    errs += broken + dangling + mismatch + empty
    errs += check_ids(z, names)
    for e in errs:
        print("DEFECT:", e)
    if do_com:
        ok, msg = com_open_test(os.path.abspath(path))
        print(("COM PASS: " if ok else "COM FAIL: ") + msg)
        if not ok:
            errs.append(msg)
    print(f"{os.path.basename(path)}: {'CLEAN' if not errs else f'{len(errs)} defect(s)'}")
    return 0 if not errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
