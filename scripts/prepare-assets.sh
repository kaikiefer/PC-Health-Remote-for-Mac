#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/build/ModuleCache"
mkdir -p build Assets/Brand Assets/Assets.xcassets/AppIcon.appiconset
xcrun swiftc -O scripts/MakeIcon.swift -o build/make-icon
./build/make-icon build/AppIcon.iconset Assets/Brand
python3 - <<'PY'
from pathlib import Path
import json, shutil
root=Path('Assets/Assets.xcassets')
images=[]
for size in (16,32,128,256,512):
    for scale in (1,2):
        filename=f'icon_{size}x{size}' + ('@2x' if scale==2 else '') + '.png'
        shutil.copyfile(Path('build/AppIcon.iconset')/filename,root/'AppIcon.appiconset'/filename)
        images.append(dict(filename=filename,idiom='mac',scale=f'{scale}x',size=f'{size}x{size}'))
(root/'Contents.json').write_text(json.dumps(dict(info=dict(author='xcode',version=1)),indent=2)+'\n')
(root/'AppIcon.appiconset/Contents.json').write_text(json.dumps(dict(images=images,info=dict(author='xcode',version=1)),indent=2)+'\n')
PY
printf 'Prepared vector logo exports and Xcode app icon assets.\n'
