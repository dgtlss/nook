# Nook source and artwork provenance

Nook is an independent implementation. The user explicitly required that Ice be
used only as a guide to user-facing functionality. No Ice, Ice 2, IceMelt, Thaw,
or other menu bar manager source or assets were copied into this repository.
The only application package dependency is Sparkle 2.10.0, used for secure
automatic updates. It is pinned in `Package.swift` and `Package.resolved`.
Sparkle's MIT licence and bundled component notices are included as
`Contents/Resources/Sparkle-LICENSE.txt` and accessible from About Nook.
Release publishing uses the AWS SDK for JavaScript as a development tool; it is
not included in Nook.app. Neither dependency is a menu bar manager.

Before this requirement, an Ice 2 checkout was inspected in `/tmp` as part of
planning. It is not part of Nook. This is original implementation, rather than a
claim of a formal clean-room process involving separate research and engineering
teams.

All application Swift and Objective-C sources, tests, build scripts, fixtures,
and the vector menu bar mark were authored for Nook. The macOS visibility bridge
was implemented from runtime API metadata on the installed macOS 27.2 build
(26B5091g), using the original `tools/framework-probe.m` and Apple's `dyld_info`.
Apple selector names and system identifiers are interface facts, not borrowed
menu bar manager implementations. Apple frameworks are linked from macOS; their
binaries are not distributed.

The raster app icon was generated with the built-in image generator, without
reference images or Ice assets. Its untouched original is retained in
`artifacts/app-icon/v1/master.png`. The accompanying packaging script performs
only size conversion and colour-profile assignment for conventional macOS icon
delivery. The original app code and project materials are MIT licensed.

Official API references:

- https://developer.apple.com/documentation/appkit/nsstatusitem
- https://developer.apple.com/documentation/applicationservices/axuielement
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/design/human-interface-guidelines/app-icons

`MenuBarClientCore` is a private, undocumented Apple framework. Nook checks the
required selectors before use and releases requests on error, timeout, sleep and
normal termination. Its process-scoped requests do not write macOS preference
files. Support is not guaranteed on future macOS builds.
