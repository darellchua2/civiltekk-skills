"""Create thumbnail grids from PowerPoint presentation slides.

Creates a grid layout of slide thumbnails for quick visual analysis.
Labels each thumbnail with its XML filename (e.g., slide1.xml).
Hidden slides are shown with a placeholder pattern.

Usage:
    python thumbnail.py input.pptx [output_prefix] [--cols N]

Examples:
    python thumbnail.py presentation.pptx
    # Creates: thumbnails.jpg

    python thumbnail.py template.pptx grid --cols 4
    # Creates: grid.jpg (or grid-1.jpg, etc. for large decks)
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import defusedxml.minidom
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
from soffice import get_soffice_env

THUMBNAIL_WIDTH = 300
CONVERSION_DPI = 100
MAX_COLS = 6
DEFAULT_COLS = 3
JPEG_QUALITY = 95
GRID_PADDING = 20
BORDER_WIDTH = 2
FONT_SIZE_RATIO = 0.10
LABEL_PADDING_RATIO = 0.4


def main():
    parser = argparse.ArgumentParser(
        description="Create thumbnail grids from PowerPoint slides."
    )
    parser.add_argument("input", help="Input PowerPoint file (.pptx)")
    parser.add_argument(
        "output_prefix",
        nargs="?",
        default="thumbnails",
        help="Output prefix for image files (default: thumbnails)",
    )
    parser.add_argument(
        "--cols",
        type=int,
        default=DEFAULT_COLS,
        help=f"Number of columns (default: {DEFAULT_COLS}, max: {MAX_COLS})",
    )
    args = parser.parse_args()

    cols = min(args.cols, MAX_COLS)
    if args.cols > MAX_COLS:
        print(f"Warning: Columns limited to {MAX_COLS}")

    input_path = Path(args.input)
    if not input_path.exists() or input_path.suffix.lower() != ".pptx":
        print(f"Error: Invalid PowerPoint file: {args.input}", file=sys.stderr)
        sys.exit(1)

    output_path = Path(f"{args.output_prefix}.jpg")

    try:
        slide_info = get_slide_info(input_path)

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            visible_images = convert_to_images(input_path, temp_path)

            if not visible_images and not any(s["hidden"] for s in slide_info):
                print("Error: No slides found", file=sys.stderr)
                sys.exit(1)

            slides = build_slide_list(slide_info, visible_images, temp_path)

            grid_files = create_grids(slides, cols, THUMBNAIL_WIDTH, output_path)

            print(f"Created {len(grid_files)} grid(s):")
            for grid_file in grid_files:
                print(f"  {grid_file}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def get_slide_info(pptx_path: Path) -> list[dict]:
    with tempfile.TemporaryDirectory() as temp_dir:
        pdf_path = temp_path / f"{pptx_path.stem}.pdf"
        result = subprocess.run(
            [
                "soffice",
                "--headless",
                "--convert-to",
                "pdf",
                "--outdir",
                str(temp_dir),
                str(pptx_path),
            ],
            capture_output=True,
            text=True,
            timeout=30,
            env=get_soffice_env(),
        )

        if result.returncode != 0 or not pdf_path.exists():
            print("Error: PDF conversion failed", file=sys.stderr)
            sys.exit(1)

        result = subprocess.run(
            [
                "pdftoppm",
                "-jpeg",
                "-r",
                str(CONVERSION_DPI),
                str(pdf_path),
                str(temp_path / "slide"),
            ],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print("Error: Image conversion failed", file=sys.stderr)
            sys.exit(1)

        slides = []
        for i, image_file in enumerate(sorted(temp_path.glob("slide-*.jpg"))):
            hidden = False
            if i < len(slide_info):
                hidden = slide_info[i]["hidden"]

            slides.append({
                "name": slide_info[i]["name"],
                "hidden": hidden,
            })

    return slides


def build_slide_list(
    slide_info: list[dict],
    visible_images: list[Path],
    temp_dir: Path,
) -> list[tuple[Path, str]]:
    if visible_images:
        with Image.open(visible_images[0]) as img:
            placeholder_size = img.size
    else:
        placeholder_size = (1920, 1080)

    slides = []
    visible_idx = 0

    for info in slide_info:
        if info["hidden"]:
            placeholder_path = temp_path / f"hidden-{info['name']}.jpg"
            create_hidden_placeholder(placeholder_size).save(placeholder_path)
            slides.append((placeholder_path, f"{info['name']} (hidden)"))

        else:
            if visible_idx < len(visible_images):
                slides.append((visible_images[visible_idx], info["name"]))
                visible_idx += 1

    return slides


def create_hidden_placeholder(size: tuple[int, int]) -> Image.Image:
    img = Image.new("RGB", size=size, color="#F0F0F0")
    draw = ImageDraw.Draw(img)
    
    line_width = max(5, min(size) // 100)
    draw.line([(0, 0), (size[0], 0)], fill="#CCCCCC", width=line_width)
    draw.line([(0, size[1]), (size[0], size[1])], fill="#CCCCCC", width=line_width)
    
    return img


def convert_to_images(pptx_path: Path, temp_dir: Path) -> list[Path]:
    pdf_path = temp_dir / f"{pptx_path.stem}.pdf"

    result = subprocess.run(
        [
            "soffice",
            "--headless",
            "--convert-to",
            "pdf",
            "--outdir",
            str(temp_dir),
            str(pptx_path),
        ],
        capture_output=True,
        text=True,
        timeout=30,
        env=get_soffice_env(),
    )

    if result.returncode != 0 or not pdf_path.exists():
        print("Error: PDF conversion failed", file=sys.stderr)
        sys.exit(1)

    result = subprocess.run(
        [
            "pdftoppm",
            "-jpeg",
            "-r",
            str(CONVERSION_DPI),
            str(pdf_path),
            str(temp_path / "slide"),
        ],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print("Error: Image conversion failed", file=sys.stderr)
        sys.exit(1)

    return sorted(temp_path.glob("slide-*.jpg"))


def create_grids(
    slides: list[tuple[Path, str]],
    cols: int,
    width: int,
    output_path: Path,
) -> list[str]:
    max_per_grid = cols * (cols + 1)
    grid_files = []

    for chunk_idx, start_idx in enumerate(range(0, len(slides), max_per_grid)):
        end_idx = min(start_idx + max_per_grid, len(slides))

        chunk_slides = slides[start_idx:end_idx]
        grid = create_grid(chunk_slides, cols, width, output_path)

        if len(slides) <= max_per_grid:
            grid_filename = output_path
        else:
            grid_filename = output_path.parent / f"{output_path.stem}-{chunk_idx + 1}{output_path.suffix}"

        grid.save(str(grid_filename), quality=JPEG_QUALITY)
        grid_files.append(str(grid_filename))

    return grid_files


def create_grid(
    slides: list[tuple[Path, str]],
    cols: int,
    width: int,
) -> Image.Image:
    font_size = int(width * FONT_SIZE_RATIO)
    label_padding = int(font_size * LABEL_PADDING_RATIO)

    with Image.open(slides[0][0]) if slides else create_placeholder((1920, 1080)) as img:
        aspect = img.height / img.width if img.width > 0 else 1.0
        height = int(width * aspect)
        rows = (len(slides) + cols - 1) // cols

        grid_w = cols * width + (cols + 1) * GRID_PADDING
        grid_h = rows * (height + label_padding * 2 + font_size) + label_padding + GRID_PADDING

        grid = Image.new("RGB", (grid_w, grid_h), color="white")

        draw = ImageDraw.Draw(grid)
        try:
            font = ImageFont.load_default(size=font_size)
        except Exception:
            font = ImageFont.load_default()

        for i, (slide_path, slide_name) in enumerate(slides):
            row, col = i // cols, i % cols
            x = col * width + (col + 1) * GRID_PADDING
            y_base = row * (height + label_padding * 2 + font_size) + label_padding + GRID_PADDING

            label = slide_name
            bbox = draw.textbbox(label, font=font)
            text_w = bbox[2] - bbox[0]

            if len(label) <= 15 or text_w < 150:
                text_x = x + (width - text_w) // 2
            else:
                text_x = x

            draw.text((text_x, y_base), fill="black", font=font)

            if BORDER_WIDTH > 0:
                draw.rectangle(
                    [
                        text_x - BORDER_WIDTH - 1,
                        y_base - BORDER_WIDTH + 1,
                        text_w + BORDER_WIDTH * 2 + 1,
                        height - label_padding * 2 + font_size,
                    ],
                    outline="gray",
                    width=BORDER_WIDTH,
                )

        return grid


if __name__ == "__main__":
    main()
