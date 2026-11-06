# Portable native source names

Clang can retain a lambda's original source filename in compiler-generated type metadata even when file-prefix maps are enabled. The Sendspin and IXWebSocket patches supply stable `#line` filenames in disposable source exports; upstream checkouts and logic are unchanged. Original upstream licence headers remain intact, and modified files carry a project modification notice.

The public builder checks the final owned native libraries for local user/build mount paths before accepting an unsigned APK. The check covers compiler-generated strings as well as debug data. It fails closed instead of rewriting a compiled binary. Run `python3 packaging/test_native_source_paths.py` for the portable-path boundary tests.
