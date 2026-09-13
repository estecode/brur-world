# Police speeding model

Issue #9 starts traffic-offence detection with clear speeding only.

## Public rule basis

Transportstyrelsen describes C31 `Hastighetsbegränsning` as a prohibition on driving faster than the speed shown on the sign:

- https://www.transportstyrelsen.se/sv/vagtrafik/trafikregler-och-vagmarken/vagmarken/forbudsmarken/hastighetsbegransning/

Transportstyrelsen also states that vehicle speed must be adapted to road, terrain, weather, visibility, vehicle condition/load and surrounding traffic:

- https://www.transportstyrelsen.se/sv/vagtrafik/trafikregler-och-vagmarken/trafikregler/generella-trafikregler/hastighet/

The underlying Swedish rule is Traffic Ordinance (1998:1276), including chapter 3 sections 14–15:

- https://www.riksdagen.se/sv/dokument-och-lagar/dokument/svensk-forfattningssamling/trafikforordning-19981276_sfs-1998-1276/

## Gameplay simplification

`SpeedingOffenceDetector` does **not** model fines, evidentiary measurement rules, camera/radar tolerances, licence consequences or Swedish police operational procedure. It only creates the first-playable trigger for an observing patrol.

The detector requires observed speed to exceed the authoritative explicit road speed limit by more than **3 km/h**. This 3 km/h margin is a gameplay/measurement-jitter guard, **not a claim that Swedish law grants a 3 km/h legal tolerance**. The legal rule represented by the game remains that the posted maximum speed must not be exceeded.

Detection is additionally gated by `PoliceObservationPolicy`: range, field of view and caller-provided line-of-sight state. A non-observing patrol receives no privileged player speed update.
