from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path.cwd()
with tempfile.TemporaryDirectory(prefix="crew-flutter-scaffold-") as temp:
    scaffold = Path(temp) / "project"
    import os
    command = [
        "flutter", "create", "--platforms=android,windows",
        "--org", "dev.crew", "--project-name", "crew", str(scaffold)
    ]
    if os.name == "nt":
        command = ["cmd", "/c", *command]
    subprocess.run(command, check=True)
    for platform in ("android", "windows"):
        source = scaffold / platform
        target = ROOT / platform
        if not source.exists():
            continue
        for path in source.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            if relative.as_posix() in {
                "local.properties", ".DS_Store"
            }:
                continue
            destination = target / relative
            if destination.exists():
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
    print("Merged missing Android/Windows Flutter scaffold files.")
