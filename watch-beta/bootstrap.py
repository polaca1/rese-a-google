"""Apply the reviewed changes only to the pinned upstream dependencies."""
import pathlib, subprocess
root = pathlib.Path(__file__).resolve().parents[1]
for name in ['SideSign', 'minimuxer']:
    directory = root / 'Dependencies' / name
    patch = root / 'watch-beta' / 'patches' / (name + '.patch')
    result = subprocess.run(['git', '-C', str(directory), 'apply', '--reverse', '--check', str(patch)], capture_output=True)
    if result.returncode == 0:
        print(name + ': patch already applied')
        continue
    subprocess.run(['git', '-C', str(directory), 'apply', '--check', str(patch)], check=True)
    subprocess.run(['git', '-C', str(directory), 'apply', str(patch)], check=True)
