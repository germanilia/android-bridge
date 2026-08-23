# Direct distribution packaging final clarification

The answers now establish these Mac requirements:

- Keep the existing native macOS app.
- Support Apple Silicon initially.
- Do not require a CLI installer.
- Do not use a paid Apple Developer account.
- Accept the resulting first-launch Gatekeeper warning.

One packaging choice remains.

## Question 1
Which direct-download Mac package should GitHub Releases provide as the primary installer?

A) A DMG containing `AndroidBridge.app`, with drag-to-Applications installation and documented Control-click > Open on first launch (recommended)

B) A ZIP containing `AndroidBridge.app`, with manual extraction, drag-to-Applications installation, and documented Control-click > Open on first launch

C) A self-signed PKG installer, which macOS may reject more aggressively without an Apple Developer ID

X) Other (please describe after the [Answer]: tag below)

[Answer]: A
