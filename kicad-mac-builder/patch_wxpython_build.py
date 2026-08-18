#!/usr/bin/env python3
"""Patch wxpython build.py and setup.py for compatibility."""
import os


def patch_setup_py():
    """Fix wx_copy_file and wx_copy_tree for modern setuptools.
    The dry_run parameter was removed from distutils file_util.copy_file and dir_util.copy_tree."""
    setup_path = 'setup.py'
    if not os.path.exists(setup_path):
        return
    with open(setup_path, 'r') as f:
        content = f.read()
    # copy_file: remove dry_run (8 args -> 7)
    old_copy_file = 'return orig_copy_file(\n            src, dst, preserve_mode, preserve_times, update, link, verbose, dry_run)'
    new_copy_file = 'return orig_copy_file(\n            src, dst, preserve_mode, preserve_times, update, link, verbose)'
    # copy_tree: remove dry_run (8 args -> 7)
    old_copy_tree = 'return orig_copy_tree(\n        src, dst, preserve_mode, preserve_times, 1, update, verbose, dry_run)'
    new_copy_tree = 'return orig_copy_tree(\n        src, dst, preserve_mode, preserve_times, 1, update, verbose)'
    for old, new in [(old_copy_file, new_copy_file), (old_copy_tree, new_copy_tree)]:
        if old in content:
            content = content.replace(old, new)
    with open(setup_path, 'w') as f:
        f.write(content)


def patch_build_py():
    with open('build.py', 'r') as f:
        content = f.read()

    # The wxPython build.py generates a pyproject.toml template like:
    #     [project]
    #     name = "{base}"
    #     [tool.sip.bindings.{base}]
    #
    # Newer sip requires [tool.sip.metadata] with a name key, while also
    # keeping name under [project]. Insert the metadata section after the
    # existing name line rather than before it (which would steal it from
    # [project]).
    old = '[project]\n            name = "{base}"'
    new = '[project]\n            name = "{base}"\n\n            [tool.sip.metadata]\n            name = "{base}"'
    if old in content and '[tool.sip.metadata]' not in content:
        content = content.replace(old, new)

    with open('build.py', 'w') as f:
        f.write(content)

if __name__ == '__main__':
    patch_build_py()
    patch_setup_py()

