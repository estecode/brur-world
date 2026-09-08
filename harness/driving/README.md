# Driving harness

The driving harness is a deliberately small visual fixture for testing production driving behavior without Sweden world streaming, POIs, or native GPS processes.

It uses the production player vehicle scene, vehicle dynamics, player controller, route follower, and camera controller. The rectangular street/avenue grid and outer ring road are presentation-only meter-scale fixture geometry. The fixed route polyline is fixture input at the routing boundary; no alternate router or vehicle implementation exists in the harness.

Use it to judge driving feel, camera follow, route-follow ownership, manual takeover, and state continuity. Objective vehicle/control contracts remain covered by headless tests.
