# Source snapshot integrity

`SOURCE-MANIFEST.json` lists the tracked publication source by file mode and SHA-256, excluding the manifest itself. `python3 review/check_source.py` checks the distribution, retained dependency notices and source/resource boundaries. The GitHub publication candidate begins at a fresh initial commit; private development history, signing material, runtime state and local audit logs are excluded.

Generated audio and fictional covers are created only in isolated host fixtures. They are not Android release inputs. The README hero is a labelled synthetic desktop capture; its source driver is included in `review/`. [Demo provenance](../docs/DEMO.md).
