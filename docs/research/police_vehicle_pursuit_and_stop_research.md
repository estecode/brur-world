# BRUR Police Vehicle Pursuit and Stop Research

Status: v0.1 — public, high-level pursuit/vehicle-stop research
Coverage target: Sweden, current public rules with historical oversight evidence
Last research update: 2026-09-13

## Purpose

This file records publicly documented Swedish police practice around attempts to stop vehicles, vehicle pursuits, risk assessment, regulated stop measures and the transition from a moving pursuit to a roadside or post-stop police intervention.

The purpose is to understand **state transitions and recurring decision factors** that may later inform fictional BRUR police behavior after the normal research-fiction transformation. It is not a tactical manual.

Do not use this research to catalogue current patrol coverage, exploitable pursuit thresholds, local response gaps, exact deployment procedures, device-placement practice, covert radio procedures or methods for escaping police.

## Public legal basis

### Police authority to stop a vehicle

Section 22 of the Swedish Police Act (`polislagen`, 1984:387) allows a police officer to stop a vehicle or other means of transport in several broad circumstances, including when:

- there is reason to believe someone travelling in the vehicle has committed an offence;
- stopping is necessary for another lawful intervention against a person in the vehicle;
- stopping is necessary to conduct a lawful search of the vehicle; or
- stopping is necessary for traffic regulation or a legally prescribed vehicle/driver/load control.

Section 10 of the Police Act also contains the general legal framework for proportionate police use of force in, among other things, a lawful vehicle stop.

Research implication: a police vehicle stop is not one single event type. It can begin as an ordinary traffic control, a criminal-investigation intervention, an arrest attempt or part of an acute response.

Source:
- Sveriges riksdag, `Polislag (1984:387)`, especially §§ 10 and 22: https://www.riksdagen.se/sv/dokument-och-lagar/dokument/svensk-forfattningssamling/polislag-1984387_sfs-1984-387/

## Normal stop signal → pursuit transition

Polismyndigheten's public traffic guidance states that a driver is required to stop when police signal a vehicle to stop. If the driver continues instead, police may begin what the authority publicly calls a **förföljande**.

The same public guidance describes the broad purpose of a pursuit as stopping the driver's continued travel. Police may use sound and/or light signals to make clear that the driver must stop.

This supports the following high-level state model:

```text
POLICE_IDENTIFIES_VEHICLE
        ↓
STOP_SIGNAL_GIVEN
        ↓
┌──────────────────────┐
│ driver stops         │ → ROADSIDE_STOP
└──────────────────────┘
        or
┌──────────────────────┐
│ driver does not stop │ → PURSUIT
└──────────────────────┘
```

Source:
- Polismyndigheten, `Trafikregler för polisen`: https://polisen.se/lagar-och-regler/trafik-och-fordon/regler-for-polisen-i-trafiken/

## Meaning of `förföljande`

A 2022 open Polismyndigheten oversight report is particularly useful because it explains a terminology change.

Older rules distinguished:

- **förföljande** — following a fleeing vehicle with the purpose of stopping it; and
- **efterföljande** — following in order to establish where the fleeing vehicle went and intervene later when appropriate.

The report says the two concepts were frequently confused in urgent situations. `Efterföljande` was therefore removed as a separate term and the meaning of `förföljande` broadened.

For research, this means historical sources that use `efterföljande` should not automatically be treated as describing a completely different modern police subsystem.

It also means the gameplay abstraction should not assume that every pursuit is a constant close-contact chase. A broader police effort to maintain or regain knowledge of a fleeing vehicle can exist inside the public concept, but the exact real operational methods are outside this research scope.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, tillsynsrapport 2022:3: https://polisen.se/SysSiteAssets/dokument/tillsynsrapporter/2022_3-rapport---tillampningen-av-atgarder-och-hjalpmedel-for-att-stoppa-fordon.pdf

## Pursuit is a changing risk decision, not a fixed script

The public oversight material repeatedly emphasizes proportionality and risk. The decision to continue or use a more forceful stop measure is not presented as `offence X = tactic Y`.

Publicly documented factors include, at a high level:

```text
PURSUIT_RISK_STATE:
  reason_for_stop
  seriousness_of_suspected_offence
  immediate_danger_created_by_vehicle
  danger_to_public
  traffic_conditions
  road_environment
  weather_and_road_surface
  time_of_day
  surrounding_environment
  available_information
  changing_event_state
```

For special technical stop measures, the oversight report explicitly notes that the purpose of the measure must be weighed against risks to the pursued driver, passengers and people in or near the area. Road characteristics, weather, road surface, traffic intensity, time of day and buildings along the road are examples of publicly identified considerations.

This is useful for BRUR because pursuit logic should eventually be a **risk/state system**, not a speed race with a guaranteed police response.

Do not convert these factors into real-world thresholds or formulas.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.

## Broad stop-method categories

Polismyndigheten's open rules and oversight material show that police have several broad categories of measures for stopping vehicles.

For research purposes they can safely be represented as:

```text
STOP_METHOD:
  voluntary_stop_after_signal
  coordinated_police_stop
  physical_blocking_measure
  controlled_vehicle_contact
  tire_deflation_device
  fixed_barrier_measure
  vehicle_stops_after_collision_or_breakdown
  driver_stops_or_abandons_vehicle
  other_publicly_documented_method
```

The Swedish regulatory vocabulary includes measures commonly described as:

- **stängning**;
- **prejning**;
- **spikmatta**; and
- **fast hinder**.

These are regulated coercive/special measures rather than interchangeable tricks. Their use requires legal authority and a risk/proportionality assessment.

This file deliberately does **not** describe exact positioning, approach geometry, device deployment, interception timing or other tactical mechanics.

Sources:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.
- Polismyndigheten, `Polismyndighetens författningssamling`: https://polisen.se/lagar-och-regler/polismyndighetens-forfattningssamling/

## Controlled vehicle contact / `prejning`

The public oversight report treats `prejning` as one of the regulated measures for stopping a vehicle and identifies historical uncertainty within the organization about when it is justified, what method is appropriate, when in an event it should be considered and who should make the decision.

The report records an average of roughly **145 reported prejningar per year during 2019–2021**.

The research significance is not the physical technique. It is that:

- it is materially more forceful than a normal stop signal;
- it is relatively uncommon compared with ordinary vehicle stops;
- its use is subject to proportionality, risk and decision-accountability concerns; and
- police oversight found a need for clearer, more consistent practice.

This should later be represented in gameplay, if at all, as a high-risk escalation state rather than a routine move.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.

## `Stängning`

The same oversight material records `stängning` as a special vehicle-stopping measure and reports an average of about **9 reported stängningar per year during 2019–2021**.

For BRUR research, store only that it represents an active physical stopping intervention requiring a higher level of justification and risk assessment than an ordinary signal-to-stop event.

Do not store or reconstruct exact manoeuvre geometry.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.

## Tire-deflation devices and fixed barriers

The open oversight report confirms that `spikmatta` and fixed barriers are regulated tools for stopping vehicles. The report emphasizes balancing the purpose of the stop against the risk created by the measure.

For a safe research model:

```text
TECHNICAL_STOP_MEASURE:
  TYPE:
    tire_deflation_device
    fixed_barrier
  PURPOSE:
  LEGAL_BASIS_PUBLICLY_KNOWN:
  AUTHORIZATION_PUBLICLY_KNOWN:
  RISK_ASSESSMENT_PUBLICLY_DESCRIBED:
  RESULT:
  SOURCE:
```

Do not collect deployment placement, setup timing, evasion characteristics or local availability.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.

## Continuation, change or termination of a pursuit

A pursuit is not one immutable state. Public oversight discussion shows that police must continually deal with the question of whether a pursuit should continue, change form or be broken off.

The 2022 report specifically identified organizational ambiguity around what it means when a commanding officer orders a pursuit to be ended: whether the entire effort ends or whether police should continue trying to establish where the vehicle goes through a less direct form of follow-up.

For research, use neutral outcome states:

```text
PURSUIT_OUTCOME:
  vehicle_stopped
  driver_stopped_voluntarily
  special_stop_measure_used
  collision_or_vehicle_failure
  police_pursuit_ended
  police_contact_lost
  vehicle_later_located
  occupants_later_identified
  unknown
```

Do not turn `police_pursuit_ended` or `contact_lost` into an evasion mechanic derived from real thresholds.

Source:
- Polismyndigheten, `Tillämpningen av åtgärder och hjälpmedel för att stoppa fordon`, 2022:3.

## Public incident examples

Polismyndigheten's public incident notices provide useful evidence for **observable sequence**, although they are preliminary summaries rather than final investigative records.

### Stockholm, 2026-05-20

Public sequence:

```text
traffic violation observed
  ↓
patrol wants to stop vehicle
  ↓
driver does not stop
  ↓
pursuit begins
  ↓
vehicle later stopped
  ↓
driver checked
  ↓
possible offences assessed
```

The public notice says a patrol attempted to stop a driver after a red-light violation in Farsta, a pursuit followed on Nynäsvägen, and the vehicle was eventually stopped near Skogskyrkogården. The driver then underwent an alcohol breath test.

Source:
- Polismyndigheten, `20 maj 17.35, Trafikbrott, Stockholm`, 2026: https://polisen.se/aktuellt/handelser/2026/maj/20/20-maj-17.35-trafikbrott-stockholm/

### Gotland, 2026-07-02

Public sequence:

```text
stop signal
  ↓
no stop
  ↓
pursuit
  ↓
vehicle collision
  ↓
driver arrested
  ↓
vehicle seized
  ↓
multiple offence suspicions recorded
```

The public notice reports no personal injury and later suspicion concerning traffic/drug-related offences. The vehicle was seized.

Source:
- Polismyndigheten, `2 juli 18.20, Olovlig körning, Gotlands län`, 2026: https://polisen.se/aktuellt/handelser/2026/juli/2/2-juli-18.20-olovlig-korning-gotlands-lan/

### Landskrona/E6, 2026-05-26

Public sequence:

```text
patrol selects vehicle for control
  ↓
vehicle does not stop
  ↓
pursuit
  ↓
vehicle stopped shortly afterward
  ↓
occupants controlled
  ↓
medical/evidentiary testing follows
```

This example shows that a pursuit can begin from an ordinary control rather than a serious known offence.

Source:
- Polismyndigheten, `26 maj 03.16, Rattfylleri, Landskrona`, 2026: https://polisen.se/aktuellt/handelser/2026/maj/26/26-maj-03.16-rattfylleri-landskrona/

### Solna, 2026-08-21

A public notice records a pursuit of a stolen vehicle that ended in a collision with another car and injuries to several people. Later suspicions included serious traffic offences and unlawful use/taking of the vehicle.

Research significance: pursuits can create serious third-party consequences and should never be modeled purely as a contest between police and the fleeing driver.

Source:
- Polismyndigheten, `21 augusti 07.44, Övrigt, Solna`, 2026: https://polisen.se/aktuellt/handelser/2026/augusti/21/21-augusti-07.44-ovrigt-solna/

## What happens after the vehicle stops

Public incident reporting and the Police Act support a broad post-stop sequence, but exact actions depend on the legal basis and event.

Safe research abstraction:

```text
VEHICLE_STOP_COMPLETED
        ↓
scene made safe
        ↓
identity / driver / occupants established as legally relevant
        ↓
reason for stop continues to be investigated
        ↓
possible lawful checks / samples / searches / seizure
        ↓
possible arrest or other legal measure
        ↓
vehicle disposition
        ├─ released
        ├─ parked/recovered
        ├─ seized
        └─ other lawful disposition
        ↓
incident report / investigation continues
```

Not every stop contains every stage.

Examples in current police public notices include alcohol/drug testing, arrest, and seizure of a vehicle after a pursuit.

## Relationship to gang-violence incidents

A gang-related police pursuit should not be treated as a unique pursuit type merely because the occupants are suspected of gang affiliation.

The meaningful inputs are instead evidence and event state, for example:

```text
LINKED_INCIDENT_STATE:
  vehicle linked to recent serious violence?
  occupants sought for arrest?
  weapon or dangerous conduct reported?
  immediate public danger?
  vehicle identity confidence?
  current legal basis for intervention?
```

The research chain can then link:

```text
SERIOUS_VIOLENCE_INCIDENT
   ↓ LINKED_TO
SUSPECT_VEHICLE
   ↓ IDENTIFIED
STOP_ATTEMPT
   ↓
PURSUIT
   ↓
VEHICLE_STOP
   ↓ PRODUCED_EVIDENCE / LED_TO_ARREST
INVESTIGATION
   ↓
LEGAL_CASE
```

Each link must have its own source and evidence status. Do not infer that a pursued vehicle belongs to a criminal network merely from the pursuit itself.

## Suggested future record schema

```text
POLICE_VEHICLE_EVENT:
  VEHICLE_EVENT_ID:
  INCIDENT_ID:
  DATE:
  REGION:

  INITIAL_CONTACT:
    OBSERVATION_REASON:
    LEGAL_BASIS_PUBLICLY_KNOWN:
    STOP_SIGNAL_PUBLICLY_CONFIRMED:

  VEHICLE_RESPONSE:
    STOPPED:
    FAILED_TO_STOP:
    PURSUIT_INITIATED:

  PURSUIT:
    START_TIME:
    END_TIME:
    TIME_PRECISION:
    PUBLIC_REASON_FOR_PURSUIT:
    RISK_FACTORS_PUBLICLY_REPORTED:
    COMMAND_CHANGE_PUBLICLY_REPORTED:

  STOP:
    METHOD_CATEGORY:
    SPECIAL_MEASURE_PUBLICLY_REPORTED:
    RESULT:
    THIRD_PARTY_HARM:

  POST_STOP:
    PERSONS_CONTROLLED:
    PERSONS_ARRESTED:
    TESTING_PUBLICLY_REPORTED:
    SEARCH_PUBLICLY_REPORTED:
    VEHICLE_SEIZED:
    OTHER_OBJECTS_SEIZED:

  LINKS:
    POLICE_RESPONSE_ID:
    RESEARCH_CHAIN_ID:
    LEGAL_CASE_IDS:

  SOURCES:
  RESEARCH_CONFIDENCE:
  NOTES:
```

Unknown fields remain unknown. Do not infer tactical detail.

## Evidence-chain edge types

Add these edge types to the wider `police_event_chain_research.md` vocabulary when needed:

```text
STOP_SIGNAL_ISSUED
FAILED_TO_STOP
PURSUIT_INITIATED
PURSUIT_ENDED
STOP_METHOD_USED
VEHICLE_STOPPED
VEHICLE_COLLISION
VEHICLE_SEIZED
OCCUPANT_ARRESTED
VEHICLE_LINKED_TO_INCIDENT
```

These are descriptive relationships, not gameplay commands.

## Reusable research patterns

### PATTERN-POLICE-VEHICLE-01 — ordinary stop can become pursuit

```text
control / intervention reason
  ↓
stop signal
  ↓
non-compliance
  ↓
pursuit state
```

### PATTERN-POLICE-VEHICLE-02 — pursuit risk changes over time

```text
initial reason + environment
  ↓
changing vehicle conduct / traffic / public danger
  ↓
risk reassessment
  ↓
continue / change / end response
```

Do not attach real thresholds.

### PATTERN-POLICE-VEHICLE-03 — stopping measure is separate from pursuit itself

```text
pursuit
  ↓
need to end continued travel
  ↓
regulated stop option considered
  ↓
risk / proportionality decision
  ↓
stop outcome
```

### PATTERN-POLICE-VEHICLE-04 — stop creates a new investigation state

```text
vehicle stopped
  ↓
occupants / vehicle examined under lawful basis
  ↓
new observations or evidence
  ↓
possible arrest / seizure / new suspicion
```

### PATTERN-POLICE-VEHICLE-05 — third parties matter

```text
pursuit
  ↓
public traffic environment
  ↓
collision / danger / disruption possible
  ↓
police risk decision and later consequences
```

This is important for BRUR's anti-glorification design: fleeing from police is not merely a skill challenge; it can create consequences for unrelated road users.

## Gameplay abstraction boundary

This research may later support fictional systems such as:

```text
police decides to stop vehicle
        ↓
player/NPC response
        ↓
abstract pursuit state
        ↓
dynamic public-risk state
        ↓
police persistence / escalation / disengagement decisions
        ↓
stop, loss of contact or later investigation
        ↓
consequences
```

But the fiction layer must not copy real operational thresholds, exact police tactics or identified real events.

A fictional pursuit system should be built from **multiple broad patterns**, fictional geography and fictional parameters.

## Operational-safety boundary

Do not add:

- exact current decision thresholds for breaking off a pursuit;
- advice on how to cause police to terminate a pursuit;
- exact placement or deployment procedure for stop devices;
- known weaknesses of particular police vehicle types;
- current local staffing or pursuit-unit coverage;
- live radio/talgroup identifiers used for pursuits;
- police interception geometry or manoeuvre instructions;
- guidance for defeating vehicle stops or checkpoints;
- real-world escape-route analysis.

Historical/public material can establish that a capability or decision factor exists without converting it into an evasion guide.

## Source hierarchy

1. Swedish law and current Polismyndigheten regulations.
2. Polismyndigheten open oversight/tillsyn reports.
3. Polismyndigheten public incident notices for event sequences.
4. Court/JO material for legal review of particular historical events.
5. Established journalism for details not available in primary sources.

## Research backlog

1. Locate and index the current consolidated FAP provisions governing vehicle-stop aids, while storing only high-level legal/decision rules.
2. Add selected historical JO/court reviews where they clarify proportionality and accountability without exposing tactical vulnerabilities.
3. Cross-link vehicle pursuit records to existing BRUR serious-violence incidents where a vehicle pursuit is already publicly documented.
4. Add a small sample across urban, motorway and rural environments to distinguish robust patterns from one-off circumstances.
5. Separate `pursuit resulted in arrest` from `pursuit produced evidence that later supported arrest` in future chain records.
6. Track historical terminology (`förföljande`, former `efterföljande`) by source date.
