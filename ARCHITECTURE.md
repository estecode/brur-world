# brur-world Architecture

This file defines the architectural rules for `brur-world`.

The goal is to keep gameplay/runtime systems small, isolated, testable, profileable and portable between Godot and native C++ where useful.

Do not introduce frameworks or abstractions only to satisfy this document. Prefer the smallest explicit boundary that solves the current problem.
