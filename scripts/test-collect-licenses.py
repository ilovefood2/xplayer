#!/usr/bin/env python3
"""Check that required notices survive collection without including source code."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('collector', Path(__file__).parents[1] / 'metadata/dependencies/collect-licenses.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class NoticeTests(unittest.TestCase):
    def test_nested_and_source_notices_survive_with_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = collector.HERE, collector.MANIFEST, collector.RESOURCE
            collector.HERE, collector.MANIFEST, collector.RESOURCE = root, root / 'manifest.json', root / 'notices.txt'
            try:
                source_notice = '/* Copyright 2007 Example. Redistribution and use are permitted. */'
                files = {'package/COPYING': 'Permission is hereby granted.\n',
                         'package/nested/COPYRIGHT': 'Copyright 2008 Another Author.\n',
                         'package/src/library.c': source_notice + '\nint private_implementation = 42;',
                         'package/src/duplicate.h': source_notice}
                path = root / 'fixture.tar.gz'
                with tarfile.open(path, 'w:gz') as archive:
                    for name, text in files.items():
                        data = text.encode()
                        member = tarfile.TarInfo(name)
                        member.size = len(data)
                        archive.addfile(member, io.BytesIO(data))
                data = path.read_bytes()
                dependency = {'name': 'fixture', 'version': '1', 'source': {'url': 'https://example.invalid/fixture.tar.gz',
                    'filename': path.name, 'sha256': hashlib.sha256(data).hexdigest(), 'sha512': hashlib.sha512(data).hexdigest()}}
                manifest = {'dependencies': [dependency], 'unresolved': []}
                collector.collect(manifest, root)
                result = collector.RESOURCE.read_text()
                self.assertIn(files['package/COPYING'], result)
                self.assertIn(files['package/nested/COPYRIGHT'], result)
                self.assertEqual(result.count(source_notice), 1)
                self.assertNotIn('private_implementation', result)
                self.assertEqual(collector.RESOURCE.read_bytes(), collector.render(manifest))
                notice = root / dependency['license_files'][0]['path']
                notice.write_text('tampered')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    collector.render(manifest)
                path.write_bytes(data + b'tampered')
                with self.assertRaisesRegex(ValueError, 'checksum'):
                    collector.collect(manifest, root)
            finally:
                collector.HERE, collector.MANIFEST, collector.RESOURCE = original


if __name__ == '__main__':
    unittest.main()
