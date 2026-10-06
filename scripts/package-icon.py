"""Package the original master into conventional macOS icon sizes. No art edits."""
from pathlib import Path
from PIL import Image, ImageCms
import subprocess

root = Path(__file__).resolve().parent.parent
master = Image.open(root / "artifacts/app-icon/v1/master.png")
profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
assert master.width == master.height, "The icon master must be square"
assert master.width >= 1024, "Keep at least a 1024px master"
output = root / "build/Nook.iconset"
output.mkdir(parents=True, exist_ok=True)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        suffix = "@2x" if scale == 2 else ""
        master.convert("RGB").resize((size * scale, size * scale), Image.Resampling.LANCZOS).save(output / f"icon_{size}x{size}{suffix}.png", icc_profile=profile)
subprocess.run(["iconutil", "-c", "icns", str(output), "-o", str(root / "Resources/Nook.icns")], check=True)
master.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS).save(root / "artifacts/app-icon/v1/macos-1024.png", icc_profile=profile)
preview = Image.new("RGB", (410, 150), "#E8ECEB")
for x, size in ((18, 96), (145, 60), (237, 40), (317, 29), (377, 16)):
    preview.paste(master.convert("RGB").resize((size, size), Image.Resampling.LANCZOS), (x, (150-size)//2))
preview.save(root / "artifacts/app-icon/v1/small-size-preview.png")
print("Packaged Resources/Nook.icns and small-size preview")
