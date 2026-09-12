# BRUR Police Investigation Methods Research

Status: v0.1 — public, non-sensitive investigation-method research
Coverage target: Sweden, gang-related shootings/explosions and other serious violence
Last research update: 2026-09-12

## Purpose

This file records publicly documented investigative methods and recurring work phases used after serious violent incidents in criminal environments. It complements:

- `police_dispatch_and_command_research.md` — alarm, RLC, priority, resource allocation and command;
- `police_response_research.md` — incident-specific historical response records;
- `legal_case_research.md` — prosecution, court decisions and appeals;
- `police_event_chain_research.md` — cross-file evidence chains and causal sequencing.

This is descriptive research. It must not become a catalogue of current police weaknesses, covert techniques, surveillance gaps, protected infrastructure, tactical thresholds or evasion opportunities.

## Strongest aggregate source

Brå report 2023:4, `Utredning och uppklaring av dödligt våld i kriminell miljö`, is the central aggregate source for this layer. The study reviewed all 113 police investigations of firearm homicides in criminal environments from 2017–2019, interviewed 19 investigators and 5 prosecutors, and obtained case-specific questionnaires from investigators.

Source:
- https://bra.se/rapporter/arkiv/2023-03-07-utredning-och-uppklaring-av-dodligt-vald-i-kriminell-miljo

The report is especially valuable because it distinguishes recurring investigative practice from anecdotes in one individual case.

## High-level investigation chain

```text
violent incident
      ↓
first alarm / first patrol
      ↓
life-saving measures + scene control
      ↓
initial documentation
      ↓
cordon + first interviews
      ↓
forensic scene examination
      ↓
door-to-door enquiries + witness identification
      ↓
camera inventory / video collection
      ↓
searches / vehicle and secondary-scene examinations
      ↓
forensic analysis + digital/telecom material
      ↓
suspect development
      ↓
coordinated interviews / coercive measures / arrests where lawful
      ↓
case synthesis with prosecutor / intelligence / NFC
      ↓
charge decision or continued investigation
```

This is a research abstraction, not an exact operational checklist. Individual cases vary and steps overlap heavily in time.

## Initial response and scene preservation

Brå's 2017–2019 homicide sample found that the first patrol normally arrived rapidly after the alarm. Median time from alarm to police arrival was six minutes in the studied cases.

Recurring first-response tasks in the report:

- life-saving actions where needed;
- cordon / protection of the crime scene;
- initial interviews with people on or near the scene;
- initial scene documentation before rescue activity changes the scene;
- waiting for / handing over to forensic personnel.

The first patrol's documentation can be uniquely important because injured or deceased people may already have been moved by ambulance before forensic personnel arrive. Brå found initial documentation by still images, video or notes in six of ten studied investigations.

Research fields:

```text
INITIAL_SCENE:
  FIRST_POLICE_AT:
  LIFE_SAVING_ACTIONS:
  CORDON_STARTED:
  INITIAL_DOCUMENTATION:
    still_image | video | notes | none_found | unknown
  FIRST_INTERVIEWS:
  RESCUE_ACTIVITY_CHANGED_SCENE:
```

## Forensic crime-scene work

A formal crime-scene examination was conducted in every investigation in Brå's sample. Median time from first police arrival to forensic personnel arrival was just under two hours.

Common public/aggregate actions include:

- scene description and photography;
- visual search of the area;
- securing cartridge cases, bullets and fragments;
- collection of biological traces for DNA analysis;
- fingerprints where obtainable;
- examination of vehicles;
- examination of secondary locations such as places where vehicles or objects were abandoned.

Dog teams participated in the initial scene work in all but one of the studied investigations.

Important evidence distinction:

```text
TRACE_FOUND != TRACE_IDENTIFIED != TRACE_LINKED_TO_SUSPECT
```

Brå found DNA in most investigations, but much of it belonged to unidentified or unrelated people. The evidential value increased significantly when a suspect's DNA could be tied to a murder weapon.

## Weapons and ballistic evidence

In all but one case in Brå's sample, traces of firearm use were secured, including cartridge cases, bullets or fragments. A weapon used in the homicide was found in a little over one third of investigations.

The research database should therefore distinguish:

```text
WEAPON_EVIDENCE:
  FIREARM_TRACE_SECURED:
  WEAPON_RECOVERED:
  RECOVERED_WEAPON_LINK_CONFIDENCE:
  SUSPECT_DNA_ON_WEAPON:
  BALLISTIC_OR_FORENSIC_LINK:
  SOURCE:
```

Do not infer weapon identity or ownership merely from a recovered object.

## Witness work and door-to-door enquiries

Brå found eyewitnesses in the majority of investigations. Most witnesses who came forward were strangers to both victim and perpetrator. Witnesses who knew the perpetrator were much less common but were associated with higher clearance probability in the study.

Door-to-door enquiries were conducted in the great majority of cases. Median time from first police arrival to the start of door-to-door work was under two hours.

Public police incident notices from 2025–2026 repeatedly show the same pattern after shootings and explosions:

- door-to-door enquiries;
- interviews;
- repeated requests for public tips;
- police remaining in the area the following day to both collect information and reduce anxiety.

Research fields:

```text
WITNESS_WORK:
  EYEWITNESSES_KNOWN:
  WITNESS_RELATION_TO_PARTIES:
    stranger | knows_victim | knows_suspect | both | unknown
  DOOR_KNOCKING:
  START_TIME_OR_APPROXIMATION:
  PUBLIC_APPEAL:
  INTERPRETER_USE_PUBLICLY_REPORTED:
```

Never treat absence of a public witness report as proof that no witnesses existed.

## Camera and video evidence

Brå found that investigators routinely examine whether cameras may have captured relevant events at:

- the crime scene;
- possible routes to or from the scene;
- other places relevant to victim or suspect movement.

Useful camera material in the reviewed cases often showed:

- victim or suspect movements before the incident;
- escape movement after the incident;
- people later identified as witnesses or persons of interest.

Recent public police notices continue to use phrases such as `inventering av kameror`, `inhämtning av kameraövervakningsmaterial` and `säkra övervakningsfilm` immediately after serious incidents.

Public general source on police camera use:
- https://polisen.se/lagar-och-regler/behandling-av-personuppgifter/kamerabevakning/

Research rule: record that video was sought, obtained or evidentially useful. Do not catalogue real blind spots or infer where cameras are absent.

## Electronic communication and telecom evidence

Brå's 2017–2019 sample found that lawful secret monitoring of electronic communication was used in nearly all investigations, and telephone interception was also common. The report discusses examples such as:

- historical connection/contact information;
- base-station/location-related telecom data;
- communication patterns between phones.

This file deliberately records only broad legal/evidential categories. It does not document technical collection procedures, thresholds, provider weaknesses or methods for defeating them.

Research fields:

```text
ELECTRONIC_EVIDENCE:
  TELECOM_DATA_USED:
  COMMUNICATION_LINK_EVIDENCE:
  LOCATION_RELATED_TELECOM_EVIDENCE:
  INTERCEPTION_PUBLICLY_CONFIRMED:
  ENCRYPTED_COMMUNICATION_EVIDENCE:
  SOURCE:
```

Brå notes that EncroChat, Sky ECC and Anom material became important later than the 2017–2019 sample and was therefore not adequately captured by that study.

## Digital evidence timing

Time is a recurring dependency in serious investigations. Brå notes that some digital information, including operator records and surveillance footage, may exist only for limited periods. Early identification of a suspect can therefore make otherwise perishable evidence available.

This supports a non-operational research concept:

```text
EVIDENCE_AVAILABILITY:
  evidence_type
  discovered_at
  collection_started_at
  still_available_when_requested
  evidential_result
```

For gameplay abstraction later, the safe pattern is `some evidence becomes harder to obtain as time passes`, not a real retention-time simulator.

## Suspect development and early arrests

Only one in ten investigations in Brå's sample never had a suspect. In more than four in ten, one or more people were prosecuted for homicide, aiding or instigation.

Among cases that eventually resulted in a conviction:

- nearly one third of the convicted people had been arrested within 12 hours of the first patrol arriving;
- half had been arrested within three days.

Brå's interviewees repeatedly emphasized rapid, coordinated early work. The report calls this an `offensivt arbetssätt`: substantial resources are used quickly to gather evidence and identify/arrest relevant people before the evidential situation changes.

The report also describes a later police method support called ILG (`identifiera, lokalisera och gripa`) but explicitly states that Brå did not evaluate it. Therefore this research must not present ILG as a proven causal mechanism.

## Investigation organization

Police method support Pug describes a special investigation organization for major serious-violence investigations where the perpetrator is initially unknown and large resources are likely to be required.

Brå found:

- around three quarters of reviewed cases reported working according to Pug;
- actual investigation teams rarely contained every function described in the model;
- staffing/resource shortages were common reasons for incomplete organization;
- stability and continuity in investigation leadership appeared important;
- large investigations often contain several thousand pages and require systematic organization.

Research should therefore distinguish `intended organization` from `organization actually documented in the case`.

```text
INVESTIGATION_ORGANIZATION:
  PUG_PUBLICLY_REPORTED:
  SPECIAL_INVESTIGATION_ORG:
  KEY_FUNCTIONS_PUBLICLY_REPORTED:
  PROSECUTOR_INVOLVEMENT:
  NFC_CONTACT:
  INTELLIGENCE_CONTACT:
  CROSS_CASE_COORDINATION:
  MATERIAL_VOLUME:
```

## Cross-case coordination

Many gang-related homicides are reactions to earlier violence. Brå found that conflicts can develop into long sequences of serious offences and specifically identified a need to coordinate investigations that share people, vehicles, weapons, places or conflict context.

In three of ten reviewed investigations that had links to another investigation, no coordination was reported.

This is highly relevant to BRUR research because the causal chain often looks like:

```text
incident A
   ↓
retaliation risk / conflict development
   ↓
incident B
   ↓
shared people / weapon / vehicle / communications / motive evidence
   ↓
investigation A ↔ investigation B
   ↓
combined evidential understanding
```

The gameplay layer must later abstract this into fictional composite conflict memory rather than reusing a real network's chain.

## NFC and forensic cooperation

Brå identifies cooperation with the National Forensic Centre (NFC) as a major success factor and a major friction point. Technical evidence is often central, but investigators reported uncertainty around ordering, understanding and using forensic analyses.

The report recommends closer dialogue between investigation leadership and NFC and notes that long forensic processing times can affect evidential opportunities.

Research fields:

```text
FORENSIC_PROCESS:
  NFC_INVOLVED:
  EXAMINATIONS_REQUESTED:
  RESULT_RETURNED:
  RESULT_CHANGED_CASE_DIRECTION:
  DELAY_PUBLICLY_REPORTED:
  NOTES:
```

## Public examples confirming the modern sequence

### Alby, Botkyrka, 2025-02-24

Police notice documents:

`multiple callers → injured person → attempted-murder investigation → search for perpetrator(s) + door knocking + camera inventory → cordon + forensic examination → death changes classification to murder → broad controls → two arrests/then prosecutor detention decision`

Source:
- https://polisen.se/aktuellt/handelser/2025/februari/24/24-februari-22.35-morddrap-botkyrka/

### Vårby, Huddinge, 2026-03-23

Public sequence:

`police/ambulance called → large police deployment → victim to hospital → broad cordon → interviews + camera inventory + possible door knocking → multiple people brought for interview → forensic examination completed → cordon lifted → later death changes classification to murder`

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/23/23-mars-16.49-morddrap-huddinge/

### Fagersjö, Stockholm, 2026-03-07

Public sequence:

`call reporting bangs → injured man found → attempted-murder investigation → overnight door knocking + camera inventory + controls → forensic examination and cordon release → next-day reassurance/information patrols → five detained suspects by 10 March`

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/7/07-mars-17.22-skottlossning-stockholm/

### Örebro, 2026-03

Police later summarized:

`multiple calls → victim transported and dies → early cordon → overnight forensic examination → dog search + door knocking/interviews + camera material → large-volume material analysis → compulsory attendance for interview → continuing reassurance presence`

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/23/23-mars-11.35-information-orebro/

These examples prove recurrence of the broad chain, not fixed timing or staffing formulas.

## Evidence-grade proposal

```text
A — aggregate official study / court / official police documentation
B — established journalism quoting named police/prosecutor/court source
C — secondary summary or incomplete public description
D — lead only; not used for factual chain assertion
```

For a chain edge to be marked `PROVEN`, require at least one A source or two independent B sources that directly support the relationship.

## Safe gameplay abstraction

Research can support fictional mechanics such as:

- first responders change the state of the scene;
- witnesses may appear immediately or later;
- information quality improves over time;
- some evidence is time-sensitive;
- multiple weak traces can combine into a strong lead;
- a recovered object is not automatically linked to a suspect;
- linked incidents can cause separate investigations to converge;
- investigation workload and staff continuity affect progress;
- an incident can continue producing consequences days or months later.

Do not expose real-world investigative blind spots, thresholds or ways to avoid detection.
