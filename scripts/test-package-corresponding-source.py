#!/usr/bin/env python3
"""Focused checks for source package integrity and reproducible output."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('package-corresponding-source.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageTests(unittest.TestCase):
    def test_reproducibility_and_rejected_corruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'docs').mkdir()
            (root / 'docs/dependency-build.md').write_text('Rebuild instructions\n')
            originals = packager.ROOT, packager.VLCKIT_TREE, packager.VLC_PATCHED_TREE
            packager.ROOT = root
            try:
                for name, filename in [('kit', 'buildMobileVLCKit.sh'), ('vlc', 'contrib/src/main.mak')]:
                    repo = root / name
                    repo.mkdir()
                    source = repo / filename
                    source.parent.mkdir(parents=True, exist_ok=True)
                    source.write_text('source fixture\n')
                    if name == 'vlc':
                        sums = repo / 'contrib/src/fixture/SHA512SUMS'
                        sums.parent.mkdir()
                        sums.write_text(hashlib.sha512(b'complete dependency source fixture').hexdigest() + '  dependency.tar.gz\n')
                    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
                    subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
                    subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@localhost', 'commit', '-qm', 'fixture'], check=True)
                packager.VLCKIT_TREE = packager.git(root / 'kit', 'rev-parse', 'HEAD^{tree}')
                packager.VLC_PATCHED_TREE = packager.git(root / 'vlc', 'rev-parse', 'HEAD^{tree}')
                contrib = root / 'contrib'
                contrib.mkdir()
                data = b'complete dependency source fixture'
                dependency = contrib / 'dependency.tar.gz'
                dependency.write_bytes(data)
                manifest = root / 'manifest.json'
                manifest.write_text(json.dumps({'dependencies': [{'name': 'fixture', 'recipe': 'fixture', 'source': {
                    'filename': dependency.name,
                    'sha256': hashlib.sha256(data).hexdigest(),
                    'sha512': hashlib.sha512(data).hexdigest(),
                }}], 'unresolved': []}))
                args = SimpleNamespace(manifest=manifest, vlckit=root / 'kit', vlc=root / 'vlc', contrib=contrib, output=root / 'first.tar.xz')
                packager.package(args)
                first = args.output.read_bytes()
                args.output = root / 'second.tar.xz'
                packager.package(args)
                self.assertEqual(first, args.output.read_bytes())
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    packager.package(args)
                incomplete = json.loads(manifest.read_text())
                incomplete['unresolved'] = ['unknown component']
                manifest.write_text(json.dumps(incomplete))
                args.output = root / 'incomplete.tar.xz'
                with self.assertRaisesRegex(ValueError, 'unresolved'):
                    packager.package(args)
                incomplete['unresolved'] = []
                manifest.write_text(json.dumps(incomplete))
                dependency.write_bytes(data + b'tampered')
                args.output = root / 'corrupt.tar.xz'
                with self.assertRaisesRegex(ValueError, 'sha256 mismatch'):
                    packager.package(args)
                self.assertFalse(args.output.exists())
            finally:
                packager.ROOT, packager.VLCKIT_TREE, packager.VLC_PATCHED_TREE = originals

    def test_unsafe_paths_are_rejected(self):
        for name in ['/absolute', '../parent', 'source/../../outside', 'source/.git/config']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                packager.checked_name(name)


if __name__ == '__main__':
    unittest.main()
