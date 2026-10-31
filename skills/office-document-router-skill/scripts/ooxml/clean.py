"""Remove unreferenced files from an unpacked PPTX directory.

Usage: python clean.py <unpacked_dir>

This script removes:
- Orphaned slides (not in sldIdLst) and their relationships
- Unreferenced media, embeddings, charts, diagrams, drawings, ink files
- Unreferenced theme files
- Content-Type overrides for deleted files

It iteratively cleans until no more unreferenced files are found.
"""

import sys
from pathlib import Path

import defusedxml.minidom


def get_slides_in_sldidlst(unpacked_dir: Path) -> set[str]:
    pres_path = unpacked_dir / "ppt" / "presentation.xml"
    pres_rels_path = unpacked_dir / "ppt" / "_rels" / "presentation.xml.rels"

    if not pres_path.exists() or not pres_rels_path.exists():
        return set()

    rels_dom = defusedxml.minidom.parse(str(pres_rels_path))
    rid_to_slide = {}
    for rel in rels_dom.getElementsByTagName("Relationship"):
        rid = rel.getAttribute("Id")
        target = rel.getAttribute("Target")
        rel_type = rel.getAttribute("Type")
        if "slide" in rel_type and target.startswith("slides/"):
            rid_to_slide[rid] = target.replace("slides/", "")

    pres_content = pres_path.read_text(encoding="utf-8")
    import re
    referenced_rids = set(re.findall(r'Id="(rId\d+)"', pres_content))

    referenced_slides = set()
    for rid in referenced_rids:
        if rid in rid_to_slide:
            slide_name = rid_to_slide[rid]
            if slide_name:
                referenced_slides.add(slide_name)

    return referenced_slides


def remove_orphaned_slides(unpacked_dir: Path) -> list[str]:
    slides_dir = unpacked_dir / "ppt" / "slides"
    pres_rels_path = unpacked_dir / "ppt" / "_rels" / "presentation.xml.rels"
    removed = []

    if not slides_dir.exists():
        return []

    referenced_slides = get_slides_in_sldidlst(unpacked_dir)

    for slide_file in slides_dir.glob("slide*.xml"):
        if slide_file.name not in referenced_slides:
            rel_path = slide_file.parent / "_rels" / f"{slide_file.name}.rels"
            slide_file.unlink()
            removed.append(str(slide_file.relative_to(unpacked_dir)))

            if rel_path.exists():
                rel_path.unlink()
                removed.append(str(rel_path.relative_to(unpacked_dir)))

    if removed and pres_rels_path.exists():
        rels_dom = defusedxml.minidom.parse(str(pres_rels_path))
        changed = False

        for rel in list(rels_dom.getElementsByTagName("Relationship")):
            target = rel.getAttribute("Target")
            slide_name = target.replace("slides/", "") if target.startswith("slides/") else None

            if slide_name and slide_name not in referenced_slides:
                if rel.parentNode:
                    rel.parentNode.removeChild(rel)
                    changed = True

        if changed:
            pres_rels_path.write_bytes(rels_dom.toxml(encoding="utf-8"))

    return removed


def remove_trash_directory(unpacked_dir: Path) -> list[str]:
    trash_dir = unpacked_dir / "[trash]"
    removed = []

    if trash_dir.exists() and trash_dir.is_dir():
        for file_path in trash_dir.iterdir():
            removed.append(str(file_path.relative_to(unpacked_dir)))
            file_path.unlink()

        if removed:
            trash_dir.rmdir()

    return removed


def get_slide_referenced_files(unpacked_dir: Path) -> set:
    referenced = set()

    slides_rels_dir = unpacked_dir / "ppt" / "slides" / "_rels"

    if slides_rels_dir.exists():
        rels_dom = defusedxml.minidom.parse(str(slides_rels_dir))

        for rel in rels_dom.getElementsByTagName("Relationship"):
            target = rel.getAttribute("Target")
            if target and not target.startswith(("http", "mailto:")):
                if target.startswith("/"):
                    target_path = unpacked_dir / target.lstrip("/")
                elif slides_rels_dir.name == ".rels":
                    target_path = unpacked_dir / target
                else:
                    base_dir = slides_rels_dir.parent
                    target_path = base_dir / target

                try:
                    target_path = target_path.resolve()
                    if target_path.exists() and target_path.is_file():
                        referenced.add(target_path.relative_to(unpacked_dir))
                except (OSError, ValueError):
                    pass

    return referenced


def remove_orphaned_rels_files(unpacked_dir: Path) -> list[str]:
    slides_rels_dir = unpacked_dir / "ppt" / "slides" / "_rels"

    if not slides_rels_dir.exists():
        return []

    resource_dirs = ["charts", "diagrams", "drawings", "ink"]

    removed = []
    for dir_name in resource_dirs:
        dir_path = slides_rels_dir.parent / dir_name

        if not dir_path.exists():
            continue

        rels_path = dir_path / "_rels"
        if not rels_path.exists():
            continue

        for rels_file in dir_path.glob("*.rels"):
            dom = defusedxml.minidom.parse(str(rels_file))

            for rel in list(dom.getElementsByTagName("Relationship")):
                target = rel.getAttribute("Target")

                if target.startswith("../") or target.startswith("media/"):
                    if target.startswith("../"):
                        target_path = (slides_rels_dir / target[3:]).resolve()
                    else:
                        target_path = (dir_path / target).resolve()

                    try:
                        if target_path.exists() and target_path.is_file():
                            continue
                    except (OSError, ValueError):
                        pass

                    dom.documentElement.removeChild(rel)

            if dom.getElementsByTagName("Relationship"):
                removed.append(str(rels_file.relative_to(unpacked_dir)))
                break

        if removed:
            rels_file.unlink()

    return removed


def remove_orphaned_files(unpacked_dir: Path, referenced: set) -> list:
    removed = []

    resource_dirs = ["media", "embeddings", "charts", "diagrams", "drawings", "ink"]
    theme_dir = unpacked_dir / "ppt" / "theme"

    for dir_name in resource_dirs:
        dir_path = unpacked_dir / "ppt" / dir_name

        if not dir_path.exists():
            continue

        for file_path in dir_path.glob("*"):
            rel_path = file_path.parent / "_rels"
            file_rel = str(file_path.relative_to(unpacked_dir))

            if file_path.is_file():
                if file_path.resolve() not in referenced:
                    file_path.unlink()
                    removed.append(file_rel)

    for file_path in theme_dir.glob("theme*.xml"):
        if file_path.is_file():
            if file_path.resolve() not in referenced:
                file_path.unlink()
                removed.append(str(file_path.relative_to(unpacked_dir)))

    notes_slides_dir = unpacked_dir / "ppt" / "notesSlides"

    if notes_slides_dir.exists():
        for file_path in notes_slides_dir.glob("*.xml"):
            rel_path = file_path.parent / "_rels"

            dom = defusedxml.minidom.parse(str(rel_path))
            found_notes = False

            for rel in dom.getElementsByTagName("Relationship"):
                target = rel.getAttribute("Target")
                if target.startswith("../notesSlides/"):
                    found_notes = True
                    break

            if not found_notes:
                for rel in list(dom.getElementsByTagName("Relationship")):
                    if rel.getAttribute("Target").startswith("../notesSlides"):
                        target_path = (notes_slides_dir / rel.getAttribute("Target")[3:]).resolve()

                        if target_path.exists() and target_path.is_file():
                            file_path.unlink()
                            removed.append(str(target_path.relative_to(unpacked_dir)))
                dom.documentElement.removeChild(rel)

            if dom.getElementsByTagName("Relationship"):
                removed.append(str(rel_path.relative_to(unpacked_dir)))

            rel_path.unlink()

    return removed


def update_content_types(unpacked_dir: Path, removed_files: list[str]) -> None:
    ct_path = unpacked_dir / "[Content_Types].xml"

    if not ct_path.exists():
        return

    dom = defusedxml.minidom.parseString(ct_path.read_text(encoding="utf-8"))

    for removed_file in removed_files:
        for override in list(dom.getElementsByTagName("Override")):
            part_name = override.getAttribute("PartName")

            if part_name == f"/ppt/{removed_file}" or part_name == f"/ppt/slides/{removed_file}":
                if override.parentNode:
                    dom.documentElement.removeChild(override)

    ct_path.write_bytes(dom.toxml(encoding="UTF-8"))


def clean_unused_files(unpacked_dir: Path) -> list[str]:
    all_removed = []

    slides_removed = remove_orphaned_slides(unpacked_dir)
    all_removed.extend(slides_removed)

    trash_removed = remove_trash_directory(unpacked_dir)
    all_removed.extend(trash_removed)

    while True:
        removed_rels = remove_orphaned_rels_files(unpacked_dir)
        all_removed.extend(removed_rels)

        referenced = get_slide_referenced_files(unpacked_dir)
        files_removed = remove_orphaned_files(unpacked_dir, referenced)

        total_removed = removed_rels + files_removed

        if not total_removed:
            break

        if all_removed:
            update_content_types(unpacked_dir, all_removed)

    return all_removed


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python clean.py <unpacked_dir>", file=sys.stderr)
        sys.exit(1)

    unpacked_dir = Path(sys.argv[1])

    if not unpacked_dir.exists():
        print(f"Error: {unpacked_dir} not found", file=sys.stderr)
        sys.exit(1)

    removed = clean_unused_files(unpacked_dir)

    if removed:
        print(f"Removed {len(removed)} unreferenced files:")
        for f in removed:
            print(f"  {f}")
    else:
        print("No unreferenced files found")
