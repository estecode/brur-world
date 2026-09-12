# BRUR Police Event-Chain Research

Status: v0.1 — cross-file evidence-chain layer
Coverage target: Sweden, serious violence in criminal environments
Last research update: 2026-09-12

## Purpose

This file connects the existing BRUR research layers so one real historical event can be followed from the first reported incident through police response, investigation, legal processing and longer-term consequences without duplicating the underlying evidence.

The purpose is to prove **relationships and sequences**, not merely accumulate facts.

It is also the boundary that makes later gameplay abstraction safer: gameplay designers should work from repeated, evidence-backed **chain patterns**, not from one identifiable real incident.

## Canonical relationship model

```text
INCIDENT
  │
  ├──→ GEO_RECORD
  │
  ├──→ THIRD_PARTY_RECORD(S)
  │
  ├──→ POLICE_DISPATCH_EVENT
  │         ↓
  │    POLICE_RESPONSE_RECORD
  │         ↓
  │    INVESTIGATION_EVENT(S)
  │         ↓
  ├──→ LEGAL_CASE
  │         ↓
  │    COURT_DECISION(S)
  │
  ├──→ LINKED_INCIDENT(S)
  │         ↓
  │    CONFLICT_CHAIN
  │
  └──→ POST_INCIDENT_RESPONSE / PREVENTION
```

No file owns the whole truth. Each file owns one evidence dimension and uses stable IDs to link to the others.

## File ownership

| File | Owns |
|---|---|
| `gang_violence_incident_research.md` | central historical incident/person facts |
| `gang_violence_geospatial_research.md` | public location evidence and precision |
| `gang_violence_third_party_research.md` | bystanders, relatives, mistaken targets and other outsiders |
| `police_dispatch_and_command_research.md` | general public dispatch/priority/command model |
| `police_response_research.md` | incident-specific alarm, arrival, scene and immediate investigative response |
| `police_investigation_methods_research.md` | recurring investigative methods and aggregate evidence |
| `police_post_incident_and_prevention_research.md` | reassurance, special command, conflict response and prevention/GVI |
| `legal_case_research.md` | prosecution, courts, appeals and outcomes |
| `gameplay_research_map.md` | abstract patterns only; never raw case adaptation |

## Chain entities

The future database should use explicit link entities rather than implicit text matching.

```text
RESEARCH_CHAIN:
  CHAIN_ID:
  PRIMARY_INCIDENT_ID:
  LINKED_INCIDENT_IDS:
  POLICE_RESPONSE_ID:
  LEGAL_CASE_IDS:
  THIRD_PARTY_IDS:
  GEO_IDS:
  PERSON_IDS:
  CONFLICT_CHAIN_ID:
  CHAIN_STAGES:
  SOURCES:
  CONFIDENCE:
  NOTES:
```

Individual chain stages:

```text
CHAIN_STAGE:
  STAGE_ID:
  CHAIN_ID:
  STAGE_TYPE:
    incident
    alarm
    dispatch
    arrival
    life_saving
    cordon
    search
    witness_work
    forensic_scene
    camera_work
    digital_evidence
    suspect_development
    arrest
    detention
    charge
    trial
    appeal
    reassurance
    retaliation_risk
    linked_incident
    prevention
    exit_support
  START_AT:
  END_AT:
  TIME_PRECISION:
    exact_public
    approximate_public
    date_only
    sequence_only
    unknown
  ACTOR_CATEGORY:
  INPUT_STATE:
  ACTION:
  OUTPUT_STATE:
  SOURCE_IDS:
  EVIDENCE_GRADE:
```

This allows a chain to be queried later as a graph without copying source material into gameplay.

## Evidence-edge model

Every causal or sequential relationship should be typed.

```text
EDGE_TYPE:
  BEFORE
  AFTER
  TRIGGERED
  RECLASSIFIED_AS
  PRODUCED_EVIDENCE
  IDENTIFIED
  LINKED_TO
  LED_TO_ARREST
  LED_TO_CHARGE
  SUPPORTED_CONVICTION
  RETALIATION_HYPOTHESIS
  SAME_CONFLICT
  PREVENTIVE_RESPONSE
```

And every edge carries a confidence status:

```text
EDGE_STATUS:
  PROVEN
  STRONGLY_SUPPORTED
  REPORTED_HYPOTHESIS
  RESEARCH_INFERENCE
  UNRESOLVED
```

Rules:

- `PROVEN` requires direct official/court evidence for the relationship.
- `STRONGLY_SUPPORTED` requires multiple good sources or one detailed authoritative source.
- `REPORTED_HYPOTHESIS` means police/prosecutor/journalism explicitly reported the theory but it was not established as fact.
- `RESEARCH_INFERENCE` may organize chronology but must never be presented as a real-world causal conclusion.
- `UNRESOLVED` preserves conflicts rather than forcing a narrative.

## Time model

Never convert prose into fake timestamps.

```text
TIME_PRECISION:
  EXACT_PUBLIC: 2026-03-23T16:49
  APPROXIMATE_PUBLIC: around 18:00
  RELATIVE_PUBLIC: a few minutes later
  DATE_ONLY: 2023-06-10
  SEQUENCE_ONLY: after forensic examination
  UNKNOWN
```

This matters because chain research must prove order without pretending to know exact duration.

## Generic evidence-backed chain pattern

Brå 2023:4 plus current police incident notices support the following recurring broad sequence:

```text
1. VIOLENT INCIDENT
       ↓
2. ALARM / MULTIPLE CALLERS / POLICE OBSERVATION
       ↓
3. RLC PRIORITIZATION + RESOURCE ALLOCATION
       ↓
4. FIRST PATROL / AMBULANCE
       ↓
5. LIFE SAVING + CORDON + FIRST INTERVIEWS
       ↓
6. PARALLEL TRACKS BEGIN
       ├─ search for perpetrator(s)
       ├─ door knocking / witness identification
       ├─ camera inventory
       ├─ forensic crime-scene work
       └─ initial suspect/vehicle/person controls
       ↓
7. EVIDENCE SYNTHESIS
       ├─ video
       ├─ witness statements
       ├─ DNA / fingerprints / weapon traces
       ├─ telecom / communication material
       └─ linked-case intelligence
       ↓
8. SUSPECT DEVELOPMENT
       ↓
9. ARREST / DETENTION / RELEASE / CONTINUED INVESTIGATION
       ↓
10. PROSECUTOR-LED LEGAL PROCESS
       ↓
11. CHARGE / NO CHARGE
       ↓
12. TRIAL / APPEAL
       ↓
13. LONGER CONSEQUENCES
       ├─ reassurance presence
       ├─ conflict/retaliation response
       ├─ linked investigations
       └─ prevention / GVI / exit support where applicable
```

Stages overlap. For example, searches, interviews and forensics often start while medical care is still ongoing.

## Chain example A — Vår krog och bar, Göteborg, 2015

Primary research ID:
- `SE-2015-0001`

Linked legal research:
- `LEGAL-SE-2015-VARKROG`

Known chain from current BRUR research:

```text
restaurant shooting
  ↓
public emergency calls
  ↓
nearby first patrol arrives within a few minutes after perpetrators leave
  ↓
life-saving care + many injured handled
  ↓
cordon / extensive technical examination / witness work
  ↓
no immediate shooter arrest recorded
  ↓
large long-running investigation
  ├─ surveillance-video analysis
  ├─ witness interviews
  ├─ technical evidence
  ├─ links to other shootings
  └─ drugs/weapons investigations
  ↓
eight-person major prosecution
  ↓
district-court convictions
  ↓
appeal proceedings alter parts of legal responsibility
```

Evidence locations:
- `police_response_research.md` — response/investigation summary;
- `legal_case_research.md` — case numbers, instances and outcomes.

Gameplay-safe pattern derived from multiple cases, not this case alone:

`public multi-victim incident → immediate rescue/scene chaos → very large investigation → separate evidence streams converge → long legal tail`.

## Chain example B — fatal grenade attack, Dimvädersgatan, 2016

Primary research ID:
- `SE-2016-0001`

Known chain:

```text
night-time explosion at residence
  ↓
emergency call
  ↓
police + ambulance response
  ↓
injured child transported to hospital
  ↓
scene secured / cordoned
  ↓
door knocking + neighborhood information collection
  ↓
technical examination establishes hand-grenade attack
  ↓
classification/conflict understanding develops
  ↓
särskild händelse established
  ↓
revenge hypothesis + link to household examined
  ↓
heightened concern about retaliatory violence / harm to relatives
```

Evidence location:
- `police_response_research.md`.

Important edge status:
- `revenge / conflict link` must remain a reported investigative hypothesis unless legal research establishes it.

Gameplay-safe repeated pattern:

`attack on residence → immediate emergency response → forensic clarification → victim/family consequences → wider conflict-risk response`.

## Chain example C — Gränby, Uppsala, 2023

Primary research ID:
- `SE-2023-SUP-0001`

Known chain:

```text
shooting at residence
  ↓
large police response
  ↓
scene secured / victim confirmed dead
  ↓
two people arrested same day
  ↓
detention decisions
  ↓
investigation examines criminal-environment link and retaliation risk
  ↓
additional police reinforcement
  ↓
addresses monitored/protected according to public reporting
```

Evidence location:
- `police_response_research.md`.

Gameplay-safe repeated pattern:

`violence → rapid suspect action + parallel retaliation-risk management`.

## Chain example D — Farsta public-square shooting, 2023

Cross-file identifiers currently available:
- third-party record `TP-SE-2023-0002`;
- legal case `LEGAL-SE-2023-FARSTA`;
- police-response section `Farsta centrum mass shooting, 2023-06-10`.

The central incident file does not yet expose a stable incident ID for this record in all linked files, so this chain deliberately does **not** invent one. A later normalization pass should assign/reuse one canonical incident ID and update all three files.

Current proven broad chain:

```text
public-square shooting with multiple victims
  ↓
large emergency/police response
  ↓
scene + casualty response + search for fleeing suspects
  ↓
intensive vehicle pursuit
  ↓
two arrests same evening
  ↓
suspected getaway vehicle stopped/seized
  ↓
firearms found in vehicle
  ↓
scene/vehicle/firearm/suspect reconstruction
  ↓
later arrests
  ↓
four principal suspects prosecuted
  ↓
district court judgment
  ↓
Svea Court of Appeal judgment
```

Evidence locations:
- `police_response_research.md`;
- `gang_violence_third_party_research.md`;
- `legal_case_research.md`.

This record demonstrates why stable cross-file IDs matter.

## Modern sequence examples — source-only, not yet central incidents

The following 2025–2026 public police notices are retained as **method examples**, not yet promoted into the gang-incident catalogue:

### Alby 2025-02-24

```text
multiple callers
 → injured victim
 → attempted-murder investigation
 → perpetrator search + door knocking + camera inventory
 → forensic scene examination
 → victim dies / reclassification to murder
 → broad controls
 → two arrests / prosecutor detention decision
```

Source:
- https://polisen.se/aktuellt/handelser/2025/februari/24/24-februari-22.35-morddrap-botkyrka/

### Fagersjö 2026-03-07

```text
call about bangs
 → injured victim
 → attempted-murder investigation
 → door knocking + camera inventory + controls
 → forensic examination complete / cordon lifted
 → reassurance/information patrols next day
 → five detained by day three
```

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/7/07-mars-17.22-skottlossning-stockholm/

These examples help test whether older research reflects current publicly visible practice, but they should not be assumed gang-related unless separate evidence establishes that.

## Pattern library for later fiction-safety transformation

Only patterns that recur across independent cases/sources should be promoted toward gameplay research.

### PATTERN-POLICE-01 — Parallel first-hour response

Observed across aggregate Brå data and multiple police notices:

```text
medical response
+ perpetrator search
+ scene protection
+ witness work
+ camera work
+ forensic preparation
```

The important mechanic is concurrency and resource pressure, not exact real staffing.

### PATTERN-POLICE-02 — Information state changes classification

```text
initial uncertain report
 → scene evidence / medical outcome / technical result
 → classification changes
 → investigation priorities and public understanding change
```

### PATTERN-POLICE-03 — Weak traces combine

```text
witness fragment
+ video fragment
+ physical trace
+ digital connection
 → suspect hypothesis
 → targeted lawful investigative action
```

No one trace is automatically decisive.

### PATTERN-POLICE-04 — Early arrest can coexist with long investigation

A suspect can be detained quickly while forensic, digital and legal work continues for months.

### PATTERN-POLICE-05 — Incident becomes conflict chain

```text
incident A
 → retaliation risk / shared actors recognized
 → incident B
 → investigations share information
 → wider conflict picture develops
```

### PATTERN-POLICE-06 — Scene closure is not event closure

```text
cordon lifted
 → police remain visible
 → tips continue
 → evidence analyzed
 → suspects emerge later
 → legal process begins
```

### PATTERN-POLICE-07 — Enforcement and support coexist

GVI and exit-support structures show that institutional response can combine consequences with a route out.

## Chain-to-game firewall

A `RESEARCH_CHAIN` is **not** a mission script.

Forbidden transformation:

```text
real chain A
 → rename people/streets
 → reproduce same sequence in BRUR
```

Required transformation:

```text
many independent research chains
 → identify recurring mechanisms
 → remove unique details
 → combine mechanisms from multiple cases
 → change geography + chronology + relationships + causes + outcomes
 → independently fictional BRUR system/event
```

The game may reproduce a **mechanism**, such as `a witness changes their willingness to talk after police return the next day`, but not an identifiable real chain.

## Future normalization backlog

1. Assign/reconcile one canonical `INCIDENT_ID` for every police-response and legal-case record that currently uses only a prose title.
2. Add `POLICE_RESPONSE_ID` values rather than relying on section headings.
3. Add `SOURCE_ID` registry shared across research files.
4. Add explicit `CHAIN_EDGE` records for incident → police response → evidence → suspect → legal outcome.
5. Preserve contradictory evidence with competing edges/statuses rather than overwriting.
6. Link third-party records and geospatial records by the same central incident ID.
7. Expand 10–20 historically important incidents into detailed public timelines with time precision and source attribution.
8. Promote only repeated cross-case mechanisms into `gameplay_research_map.md` after fiction-safety review.
