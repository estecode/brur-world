# Police foot pursuit and search model

## Purpose

This documents the deliberately small, game-focused model used for issue #20. It extends BRUR's existing shared police observation model to targets on foot without granting police live access to the player's transform after contact is lost.

## Knowledge flow

```text
PoliceObservationStore
    -> PoliceLastKnownTargetState
    -> PoliceFootSearchArea
    -> PoliceFootSearchTask
    -> PoliceOfficerFootAI
    -> PersonMovementIntent
    -> generic Person
```

Only explicitly published observations update police knowledge. If the player changes direction, enters a vehicle, taxi, bus, train, tram or metro without a new observation being published, police knowledge does not move with the player.

## Search abstraction

When an observation is no longer current, the last observed position and timestamp are frozen. A local search radius grows deterministically with observation age and a conservative plausible on-foot speed. The first implementation samples a small set of points around that radius and lets an injected local-space owner reject non-traversable points.

The search is intentionally free-roam rather than pedestrian-graph constrained: traversable roads can remain plausible target space. The police module does not own or duplicate world/routing truth.

## Realism boundary

This is not an operational police-search model. It encodes no real deployment patterns, containment tactics, surveillance methods, identification systems, or evasion thresholds. It exists only to preserve the gameplay invariant that police act on observations and uncertainty rather than omniscient player state.
