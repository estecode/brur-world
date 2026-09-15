# #342 seamless HLOD invariants

The GeoDot presentation follows `ARCHITECTURE.md`: authoritative GPKG/world coordinates remain unchanged; HLOD is derived presentation acceleration only.

- Visible building coverage never becomes empty while a better representation is loading.
- A geographic region has exactly one visible presentation owner.
- A replacement becomes visible only after it is READY; the previous owner remains WARM for immediate reverse zoom.
- RAM pressure evicts warm/speculative quality before visible/base coverage.
- Gameplay presentation is gated on mandatory base HLOD coverage.
- Detail streaming may improve quality after presentation, but never determines whether the world exists.
- Screen-space policy selects desired quality; ownership/readiness determines what may be shown.
