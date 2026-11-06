# Third-party and asset notices

Project-authored code, documentation, original application artwork and hero media use [MIT](../LICENSE). No songs, private cover artwork, camera images, inference model, credentials or signing keys are included in this distribution.

The app exposes **Settings → Licenses & notices**, with bounded pages for long upstream texts. The [notice index](../app/assets/notices/INDEX.json) and [runtime inventory](../app/assets/notices/RUNTIME-INVENTORY.json) are also available in source. Builds regenerate them for the actual native payloads and resolved Gradle artifacts, then verify every notice hash in the unsigned APK.

| Component | Terms and retained evidence |
| --- | --- |
| Godot 3.6.3 and GDNative headers | MIT project license plus the full upstream Godot copyright/third-party license inventory. The included OpenSL cleanup patch preserves upstream notices. |
| Official AAR C++ shared runtime | Exact original Godot AAR payload, NDK 28.0.13004108. Full matching NDK NOTICE/NOTICE.toolchain and extraction provenance are retained. |
| Source-built engine and native C++ linkage | NDK r26d full notices retained, including C++/libunwind and toolchain component terms. These notices are intentionally conservative rather than stripped to a guessed minimum. |
| Sendspin C++ SDK | Apache-2.0; exact revision in the dependency lock. Local ordered-clear and outbound-only changes carry dated modification notices. |
| ArduinoJson | MIT, exact source revision and full notice pinned. |
| IXWebSocket | BSD-3-Clause. A build-only source-line directive prevents a compiler-generated lambda type name from exposing a workstation path; it changes diagnostic metadata, not networking behavior. |
| micro-flac / micro-ogg-demuxer | Apache-2.0, each upstream notice retained. Opus is disabled in this build. |
| Noise-C and crypto subcomponents | Upstream MIT/public-domain and included subcomponent terms retained through COPYING, x25519 license, crypto README and source copyright headers. The existing object-bounds source patch remains enabled. |
| minimp3 / stb_vorbis | CC0 / MIT-or-public-domain alternatives; full notices retained. |
| DejaVuSans | Unmodified font with Bitstream Vera license and public-domain DejaVu changes. |
| AndroidX, Kotlin and resolved Java runtime dependencies | All 33 module artifact/POM hashes, declared Apache-2.0 terms, the applicable Guava parent POM and available embedded notices are recorded. Dependency or license drift fails the build. |

[Pinned notice sources](../third_party/notice-sources.json) record upstream URLs, revisions and hashes. [The Gradle runtime lock](../third_party/gradle-runtime.lock.json) identifies actual resolved Java artifacts. External build tools, caches and clean dependency checkouts are supplied separately; their binaries are not part of the source repository.

Original generated branding has provenance in [the artwork notes](branding/README.md); original procedural icons and synthetic hero media share the project MIT grant. Separately supplied user music always retains its own terms. Enabling a camera/AI service in Kinegra Cam does not bundle that service or its model into Kinegra Amp.

Upstream licence texts are retained verbatim, including historical URLs.
