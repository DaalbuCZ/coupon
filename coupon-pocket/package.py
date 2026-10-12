"""Package tracked/visible source only; never include local keys or build caches."""
from pathlib import Path
import hashlib
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
project = root / 'coupon-pocket'
dist = project / 'dist'
dist.mkdir(exist_ok=True)
names = subprocess.check_output(
    ['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'coupon-pocket/'],
    cwd=root,
).decode('utf-8').split('\0')
excluded = {'.local', 'build', 'dist', '.gradle', '.dart_tool', '.idea', '.vscode', '.pub-cache', '.pub', 'Pods', '.symlinks', 'ephemeral'}
private_names = {'local.properties', 'key.properties', 'Generated.xcconfig', 'flutter_export_environment.sh', '.flutter-plugins-dependencies'}
source = dist / 'coupon-pocket-source.zip'
with zipfile.ZipFile(source, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(set(filter(None, names))):
        path = Path(name)
        if excluded.intersection(path.parts) or path.name in private_names or path.suffix.lower() in {'.p12', '.jks', '.keystore'}:
            continue
        file = root / path
        if file.is_file() and not file.is_symlink():
            archive.write(file, name.replace('\\', '/'))
web = project / 'flutter' / 'build' / 'web'
artifacts = [source]
if web.is_dir() and (web / 'main.dart.js').is_file():
    output = dist / 'coupon-pocket-web.zip'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(web.rglob('*')):
            if path.is_file() and not path.is_symlink():
                archive.write(path, path.relative_to(web).as_posix())
    artifacts.append(output)
apk = dist / 'coupon-pocket-dev.apk'
if apk.is_file():
    artifacts.append(apk)  # Existing Java APK; never silently replace it with another build.
(dist / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in sorted(artifacts)
), encoding='ascii')
print('Packaged:', ', '.join(path.name for path in artifacts))
