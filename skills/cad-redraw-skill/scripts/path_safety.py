"""Guard redraw outputs against overwriting inputs or sibling artifacts."""

from collections.abc import Iterable
from pathlib import Path


def _aliases(left: Path, right: Path) -> bool:
    """Return whether two paths resolve to the same file or prospective location."""
    # ponytail: the pre-write check can race a symlink swap; use dirfd/openat if
    # outputs are shared with hostile concurrent writers.
    if left.exists() and right.exists():
        try:
            if left.samefile(right):
                return True
        except OSError:
            pass
    return left.resolve(strict=False) == right.resolve(strict=False)


def ensure_safe_outputs(
    protected_inputs: Iterable[Path], outputs: Iterable[Path]
) -> None:
    """Raise ValueError when an output aliases an input or another output."""
    inputs = [Path(path).expanduser() for path in protected_inputs]
    output_paths = [Path(path).expanduser() for path in outputs]
    for index, output in enumerate(output_paths):
        for protected in inputs:
            if _aliases(output, protected):
                raise ValueError(
                    f"output path '{output}' aliases protected input '{protected}'"
                )
        for other in output_paths[:index]:
            if _aliases(output, other):
                raise ValueError(f"output paths '{other}' and '{output}' alias")
