#!/usr/bin/env python3
"""Package pinned decoder sources without local Git metadata or build products."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'xplayer-decoder-sources-3.7.3'
VLCKIT_COMMIT = '319ed2c0724e3d4c4d34889a62fef1ae269491bc'
VLCKIT_TREE = 'e5ae8d66fd33ca6a56ecdf90784223d80a0f779d'
VLC_COMMIT = '79128878ddb2c280bbb6c89c76a46b31a80ade1c'
VLC_PATCHED_TREE = '651b6d3241f7631684f79310f1f44ad2a9c73969'


def checked_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or any(p in ('..', '.git') for p in path.parts):
        raise ValueError(f'Unsafe archive path: {name}')
    return name


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args]).decode().strip()


def source_entries(root, tree):
    if git(root, 'rev-parse', 'HEAD^{tree}') != tree:
        raise ValueError(f'Unexpected source tree: {root.name}')
    process = subprocess.Popen(['git', '-C', str(root), 'archive', tree], stdout=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=process.stdout, mode='r|') as source:
            for member in source:
                if member.isdir():
                    continue
                checked_name(member.name)
                if member.isfile():
                    yield member.name, member.mode, source.extractfile(member).read(), None
                elif member.issym():
                    checked_name(str(PurePosixPath(member.name).parent / member.linkname))
                    yield member.name, member.mode, b'', member.linkname
                else:
                    raise ValueError(f'Unsupported source entry: {member.name}')
        if process.wait() != 0:
            raise RuntimeError('git archive failed')
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.kill()
            process.wait()


def add_bytes(archive, inventory, name, data, mode=0o644, link=None):
    name = checked_name(f'{PREFIX}/{name}')
    if name in inventory:
        raise ValueError(f'Duplicate archive path: {name}')
    member = tarfile.TarInfo(name)
    member.mode = 0o755 if mode & 0o111 else 0o644
    if link is not None:
        member.type = tarfile.SYMTYPE
        member.linkname = link
        inventory[name] = {'symlink': link}
    else:
        member.size = len(data)
        inventory[name] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    archive.addfile(member, io.BytesIO(data) if link is None else None)


def verify(path):
    actual = {}
    manifest = None
    with tarfile.open(path, 'r:xz') as archive:
        for member in archive:
            checked_name(member.name)
            if not member.name.startswith(PREFIX + '/') or member.name in actual:
                raise ValueError('Invalid or duplicate package member')
            if member.name == f'{PREFIX}/SOURCE-MANIFEST.json':
                if manifest is not None:
                    raise ValueError('Duplicate source manifest')
                manifest = json.load(archive.extractfile(member))
            elif member.isfile():
                actual[member.name] = {'size': member.size, 'sha256': hashlib.file_digest(archive.extractfile(member), 'sha256').hexdigest()}
            elif member.issym():
                checked_name(str(PurePosixPath(member.name).parent / member.linkname))
                actual[member.name] = {'symlink': member.linkname}
            else:
                raise ValueError('Unexpected package member type')
    if not manifest or actual != manifest['files']:
        raise ValueError('Package contents do not match the complete file inventory')
    if (manifest['vlckit_commit'] != VLCKIT_COMMIT or manifest['vlckit_tree'] != VLCKIT_TREE
            or manifest['vlc_base_commit'] != VLC_COMMIT or manifest['vlc_patched_tree'] != VLC_PATCHED_TREE):
        raise ValueError('Incorrect decoder source revisions')
    if manifest['dependencies'].get('unresolved') or not manifest['dependencies'].get('dependencies'):
        raise ValueError('Incomplete dependency inventory')
    for dependency in manifest['dependencies']['dependencies']:
        source = dependency['source']
        entry = actual[f'{PREFIX}/VLCKit/libvlc/vlc/contrib/tarballs/{source["filename"]}']
        if entry['sha256'] != source['sha256']:
            raise ValueError(f'Dependency digest mismatch: {dependency["name"]}')
    required = ['VLCKit/buildMobileVLCKit.sh', 'VLCKit/libvlc/vlc/contrib/src/main.mak', 'VLCKit/libvlc/vlc/src/revision.txt', 'README.md']
    if any(f'{PREFIX}/{name}' not in actual for name in required):
        raise ValueError('Required source or rebuild instructions absent')
    print(f'PASS: {len(actual)} source/package files and all dependency archives verified.')


def package(args):
    dependencies = json.loads(args.manifest.read_text())
    if dependencies.get('unresolved') or not dependencies.get('dependencies'):
        raise ValueError('Dependency inventory is empty or has unresolved entries')
    archives = {}
    for dependency in dependencies['dependencies']:
        source = dependency['source']
        name = source['filename']
        if PurePosixPath(name).name != name:
            raise ValueError('Dependency filename must be a basename')
        recipe = dependency['recipe']
        sums = git(args.vlc, 'show', f'{VLC_PATCHED_TREE}:contrib/src/{recipe}/SHA512SUMS')
        checksums = {parts[1].lstrip('*'): parts[0] for line in sums.splitlines() if len(parts := line.split()) == 2}
        if checksums.get(name) != source.get('sha512'):
            raise ValueError(f'Checksum does not match the pinned VLC recipe: {name}')
        path = args.contrib / name
        for algorithm in ('sha256', 'sha512'):
            if not source.get(algorithm):
                raise ValueError(f'Missing {algorithm}: {name}')
            with path.open('rb') as stream:
                if hashlib.file_digest(stream, algorithm).hexdigest() != source[algorithm]:
                    raise ValueError(f'{algorithm} mismatch: {name}')
        archives[name] = path
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        raise ValueError('Output already exists; choose a new output filename')
    temporary = args.output.with_name(args.output.name + '.partial')
    inventory = {}
    try:
        with tarfile.open(temporary, 'w:xz', preset=6) as archive:
            for root, prefix, tree in [(args.vlckit, 'VLCKit', VLCKIT_TREE), (args.vlc, 'VLCKit/libvlc/vlc', VLC_PATCHED_TREE)]:
                for name, mode, data, link in source_entries(root, tree):
                    add_bytes(archive, inventory, f'{prefix}/{name}', data, mode, link)
            # A Git-free source distribution needs a version stamp for VLC's make rule.
            add_bytes(archive, inventory, 'VLCKit/libvlc/vlc/src/revision.txt', b'79128878+VLCKit-3.7.3-patches\n')
            for name, path in sorted(archives.items()):
                member = tarfile.TarInfo(f'{PREFIX}/VLCKit/libvlc/vlc/contrib/tarballs/{name}')
                member.size = path.stat().st_size
                member.mode = 0o644
                with path.open('rb') as stream:
                    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
                    stream.seek(0)
                    archive.addfile(member, stream)
                inventory[member.name] = {'size': member.size, 'sha256': digest}
            add_bytes(archive, inventory, 'README.md', (ROOT / 'docs/dependency-build.md').read_bytes())
            manifest = {'format_version': 1, 'vlckit_commit': VLCKIT_COMMIT, 'vlckit_tree': VLCKIT_TREE,
                        'vlc_base_commit': VLC_COMMIT, 'vlc_patched_tree': VLC_PATCHED_TREE,
                        'dependencies': dependencies, 'files': dict(sorted(inventory.items()))}
            add_bytes(archive, {}, 'SOURCE-MANIFEST.json', (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode())
        verify(temporary)
        temporary.rename(args.output)
        with args.output.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        args.output.with_name(args.output.name + '.sha256').write_text(f'{digest}  {args.output.name}\n')
        print(f'{digest}  {args.output}')
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path, help='Verify an existing package without extracting it')
    parser.add_argument('--vlckit', type=Path)
    parser.add_argument('--vlc', type=Path)
    parser.add_argument('--contrib', type=Path)
    parser.add_argument('--manifest', type=Path, default=ROOT / 'metadata/dependencies/mobilevlckit-3.7.3.json')
    parser.add_argument('--output', type=Path, default=ROOT / f'build/corresponding-source/{PREFIX}.tar.xz')
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
    elif all((args.vlckit, args.vlc, args.contrib)):
        package(args)
    else:
        parser.error('Packaging requires --vlckit, --vlc, and --contrib source directories')


if __name__ == '__main__':
    main()
