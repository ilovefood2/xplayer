#!/usr/bin/env python3
"""Collect verbatim notices from the checksum-pinned decoder source archives."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
MANIFEST = HERE / 'mobilevlckit-3.7.3.json'
RESOURCE = ROOT / 'XPlayer/Resources/ThirdPartyLicenses.txt'
HEADER = '''Third-party copyright and license notices

MobileVLCKit includes the libraries listed below. These notices are reproduced
from their exact corresponding source archives, including notices for optional
source components and development tools. Those additional texts do not mean
that every source component is included in the app. The upstream build disables
GPL and GNUv3 contrib selections.
The app's MIT license does not replace any dependency's terms.

FreeType acknowledgement: Portions of this software are based in part on the
work of the FreeType Team (https://freetype.org/).

This product includes software developed by Niels Provos.
This software is based in part on the work of the Independent JPEG Group.

Matching sources, patches and build instructions:
https://github.com/ilovefood2/xplayer/releases/tag/ios-v4.11.143
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def render(manifest):
    blocks = [HEADER]
    for dependency in manifest['dependencies']:
        blocks.append(f"\n=== {dependency['name']} {dependency['version']} ===\n")
        blocks.append('Source: ' + dependency['source']['url'] + '\n')
        for notice in dependency['license_files']:
            data = (HERE / notice['path']).read_bytes()
            if digest(data) != notice['sha256']:
                raise ValueError('Notice checksum differs: ' + notice['path'])
            blocks.append('\n--- ' + notice['source_path'] + ' ---\n')
            blocks.append(data.decode('utf-8'))
    return ('\n'.join(blocks) + '\n').encode('utf-8')


def collect(manifest, archives):
    for dependency in manifest['dependencies']:
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', dependency['name']):
            raise ValueError('Invalid dependency name')
        source = dependency['source']
        if Path(source['filename']).name != source['filename']:
            raise ValueError('Invalid dependency archive name')
        archive_path = archives / source['filename']
        for algorithm in ('sha256', 'sha512'):
            with archive_path.open('rb') as stream:
                if hashlib.file_digest(stream, algorithm).hexdigest() != source[algorithm]:
                    raise ValueError('Archive checksum differs: ' + source['filename'])
        notices = []
        contents = []
        seen = set()
        with tarfile.open(archive_path, 'r|*') as archive:
            for member in archive:
                if not member.isfile():
                    continue
                name = Path(member.name).name
                named = re.match(r'^(COPYING|COPYRIGHT|LICEN[CS]E|NOTICE|PATENTS|AUTHORS|FTL\.TXT)', name, re.I)
                named = named or (dependency['name'] == 'freetype' and member.name.endswith(('/src/bdf/README', '/src/pcf/README')))
                is_source = Path(name).suffix.lower() in ('.c', '.h', '.cpp', '.hpp', '.cc', '.m', '.s', '.asm')
                if not named and not is_source:
                    continue
                raw = archive.extractfile(member).read()
                if b'\0' in raw:
                    continue
                # Upstream legacy notices use Latin-1 in a few author names.
                try:
                    text = raw.decode('utf-8')
                except UnicodeDecodeError:
                    text = raw.decode('latin-1')
                if named:
                    candidates = [('complete-file', text)]
                else:
                    candidates = [('source-comment', match.group()) for match in re.finditer(
                        r'/\*[\s\S]*?\*/|(?://[^\n]*(?:\n|$))+', text)
                        if re.search(r'copyright|permission is hereby|redistribution and use', match.group(), re.I)]
                for kind, notice in candidates:
                    data = notice.encode('utf-8')
                    checksum = digest(data)
                    if checksum in seen:
                        continue
                    seen.add(checksum)
                    contents.extend(['\n--- ' + member.name + ' ---\n', notice])
                    notices.append({'sha256': checksum, 'source_path': member.name,
                                    'kind': kind})
        if not notices:
            raise ValueError('No license notices found: ' + dependency['name'])
        relative = f"licenses/{dependency['name']}.txt"
        target = HERE / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        collected = ('\n'.join(contents) + '\n').encode('utf-8')
        target.write_bytes(collected)
        dependency['license_files'] = [{'path': relative, 'sha256': digest(collected),
                                       'source_path': source['filename'] + ' (collected notices)'}]
        dependency['notice_sources'] = notices
        print(f"Collected {dependency['name']}: {len(notices)} notices, {len(collected)} bytes", flush=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n')
    RESOURCE.write_bytes(render(manifest))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archives', type=Path, help='Regenerate from the pinned source archive directory')
    parser.add_argument('--check', action='store_true', help='Verify collected notice hashes and bundled text')
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    if manifest.get('unresolved') or not manifest.get('dependencies'):
        raise ValueError('Dependency inventory is incomplete')
    if args.archives:
        collect(manifest, args.archives)
    elif args.check:
        if RESOURCE.read_bytes() != render(manifest):
            raise ValueError('Bundled dependency licenses differ from the collected notices')
        print(f"PASS: {len(manifest['dependencies'])} dependency notice sets match their manifest and app resource.")
    else:
        parser.error('Specify --archives or --check')


if __name__ == '__main__':
    main()
