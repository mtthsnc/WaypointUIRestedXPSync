"""Build an installable ZIP using an explicit list of public addon files."""
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent
NAME = "WaypointUIRestedXPSync"
FILES = ("RestedXP.lua", "Sync.lua", f"{NAME}.toc", "README.md", "CHANGELOG.md")

def build():
    toc = (ROOT / f"{NAME}.toc").read_text(encoding="utf-8")
    version = re.search(r"^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$", toc, re.M).group(1)
    target = ROOT / "dist" / f"{NAME}-{version}.zip"
    target.parent.mkdir(exist_ok=True)
    with ZipFile(target, "w", compression=ZIP_DEFLATED) as archive:
        for name in FILES:
            entry = ZipInfo(f"{NAME}/{name}", date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            archive.writestr(entry, (ROOT / name).read_bytes())
    with ZipFile(target) as archive:
        assert archive.testzip() is None
        assert archive.namelist() == [f"{NAME}/{name}" for name in FILES]
    print(target)
    return target

if __name__ == "__main__":
    build()
