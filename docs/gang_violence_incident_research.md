# BRUR Gang-Violence Incident Research

Status: v0.1 — structured text research, intended for later database conversion
Coverage target: Sweden, 2011–present

## Purpose

This file is the detailed incident/person layer behind `gameplay_research_map.md`. It is intended to catalogue deaths and injuries connected to Swedish criminal-network violence while preserving enough structure to convert the research into a database later.

The research is anonymized. Do not store real victim, suspect, perpetrator or witness names here. Publicly reported criminal-network names may be retained when relevant to understanding conflicts and organizational relationships.

This is research input for fictional systemic game design. It must not be used to recreate identifiable real crimes, victims or perpetrators as entertainment content.

## Source policy

Prefer, in order appropriate to the claim:

1. Police, Brå, courts and other authoritative public records for counts, legal outcomes and official classifications.
2. Established Swedish journalism for incident details, chronology and relationships that are not available in aggregate official data.
3. Diamant Salihu's books, reporting and analysis as an important expert journalistic source for conflict chronology, network relationships and changes in the criminal environment. Where possible, corroborate factual incident/person claims with primary reporting, court material or another independent source.

Never convert an allegation into fact merely because it appears in reporting. Preserve the source's level of certainty.

## Coverage limitations

The goal is comprehensive coverage, but public reporting does not expose every injured person's age, sex, home location, network status or relationship to a conflict. Use `unknown` rather than inference.

National police shooting statistics and media archives vary in consistency over the 2011–present period. A missing record means `not yet found`, not that an event did not occur.

General shooting statistics are not identical to gang/network violence. Exclude unrelated domestic violence, suicide, accidents, mass violence without a supported criminal-network connection, and police use of force unless a documented network-conflict relationship makes the event relevant.

## Identity and evidence rules

- Assign anonymous stable IDs to incidents and people.
- Never store real personal names.
- Age, sex and broad home location may be stored when publicly reported and research-relevant.
- Avoid unnecessary identifying detail below locality/neighborhood level.
- A network affiliation must have an evidence status.
- `suspected`, `charged`, `convicted`, `acquitted` and `unknown` are distinct legal states.
- Never label a suspect as a perpetrator solely because they were arrested, suspected or charged.
- Preserve changes in legal status over time.
- Preserve contradictory reporting instead of silently choosing one version.
- Every material person/conflict assertion should eventually be traceable to a source.

## Controlled vocabulary — initial

### Outcome

```text
killed
injured
uninjured_target
unknown
```

### Target status

```text
intended
relative
associate
witness
bystander
wrong_person
wrong_address
unknown
```

### Network status

```text
member
leader
associate
alleged_member
alleged_associate
former_member
none_known
unknown
```

### Legal status

```text
suspected
arrested
charged
convicted
acquitted
case_dismissed
unknown
```

### Incident type

```text
shooting
explosion
grenade_attack
assault
kidnapping
vehicle_attack
other
```

These vocabularies may expand as research reveals genuinely distinct categories. Do not create synonyms for an existing category merely because a source uses different wording.

## Incident record format

```text
INCIDENT: SE-YYYY-NNNN
DATE: YYYY-MM-DD | approximate | unknown
LOCATION:
MUNICIPALITY:
REGION:
INCIDENT_TYPE:
CONFLICT:
SUMMARY:

VICTIMS:
- PERSON: V1
  OUTCOME: killed | injured | uninjured_target | unknown
  AGE:
  SEX:
  HOME_LOCATION:
  TARGET_STATUS: intended | relative | associate | witness | bystander | wrong_person | wrong_address | unknown
  NETWORK:
  NETWORK_STATUS: member | leader | associate | alleged_member | alleged_associate | former_member | none_known | unknown
  RELATION_TO_CONFLICT:
  PREVIOUS_INCIDENT_LINKS:

SUSPECTS/PERPETRATORS:
- PERSON: P1
  AGE:
  SEX:
  HOME_LOCATION:
  NETWORK:
  NETWORK_STATUS:
  ROLE:
  LEGAL_STATUS:
  LEGAL_STATUS_HISTORY:
  SENTENCE:
  PREVIOUS_INCIDENT_LINKS:

EVENT:
  METHOD:
  SETTING:
  VEHICLE_INVOLVED:
  TARGET_TYPE:
  SUSPECTED_MOTIVE:
  RETALIATION:
  RELATIVE_TARGETING:
  BYSTANDERS_PRESENT:

AFTERMATH:
  RETALIATION_EVENTS:
  POLICE_RESPONSE:
  ARRESTS:
  COURT_OUTCOME:
  LONG_TERM_EFFECTS:

SOURCES:
- SOURCE_ID:
  OUTLET:
  AUTHOR:
  PUBLISHED:
  URL:
  SOURCE_TYPE:
  SUPPORTS:
  CONFIDENCE:

RESEARCH_CONFIDENCE:
NOTES:
```

## Relationship model

Relations should be explicit enough to become graph/database edges later.

```text
PERSON -> member_of -> NETWORK
PERSON -> associate_of -> NETWORK
PERSON -> relative_of -> PERSON
PERSON -> victim_in -> INCIDENT
PERSON -> suspected_in -> INCIDENT
PERSON -> convicted_in -> INCIDENT
PERSON -> witness_to -> INCIDENT
INCIDENT -> retaliation_for -> INCIDENT
INCIDENT -> linked_to -> CONFLICT
NETWORK -> conflict_with -> NETWORK
PERSON -> ordered_by -> PERSON
```

Example using anonymous IDs only:

```text
INCIDENT: SE-2017-0042
PERSON: V1
RELATION: V1 -> relative_of -> SE-2017-0061:V1

INCIDENT: SE-2017-0061
SUSPECTED_MOTIVE: retaliation
RELATION: SE-2017-0061 -> retaliation_for -> SE-2017-0042
```

## Legal-status history

When later reporting changes the legal picture, preserve the chronology instead of overwriting it.

```text
PERSON: P1
LEGAL_STATUS_HISTORY:
- 2019-04-02: suspected
- 2019-07-14: charged
- 2020-02-06: acquitted
FINAL_STATUS: acquitted
```

## Research confidence

Use a simple initial scale:

```text
HIGH   = authoritative record or multiple strong independent sources agree
MEDIUM = credible established reporting supports the claim but primary confirmation is absent/incomplete
LOW    = preliminary, single-source, ambiguous or conflicting reporting
UNKNOWN = not researched enough to rate
```

Confidence applies to individual claims where necessary; an incident can have high confidence that a shooting occurred while having low confidence about motive or network affiliation.

## Seed research observations

These are starting observations from the existing BRUR research and are not yet the comprehensive 2011–present incident catalogue.

### 2017 national scale

Contemporary SVT reporting mapped the year's fatal shootings, while final police figures reported 43 people shot dead and approximately 140 injured during 2017. The detailed incident catalogue must distinguish the subset with supported criminal-network/conflict connections from all shootings.

### 2017 Stockholm examples to expand into full records

The existing research has identified anonymized examples including:

- January, Sundbyberg: man aged 25 killed; contemporary reporting described several suspects. Motive/network evidence requires source-level review before coding.
- January, Vårby gård: man in his twenties killed; motive and perpetrator status initially unclear.
- February, Skärholmen: man in his twenties killed and another man seriously injured; later court outcomes must be recorded chronologically rather than using the initial reporting state.
- March, Kista: two men killed; one victim was publicly described as a leading figure in Lejonen. A man in his thirties was later convicted and received a life sentence according to the source set.
- May, Järfälla: 18-year-old man killed; reporting connected the event to gang conflict in western Stockholm.
- July, Vårberg: one man killed and one injured.
- August, Östberga: one man killed and one injured; reporting discussed an ongoing gang conflict.
- August, Stenhagen/Uppsala: man in his thirties killed; possible retaliation was discussed in reporting and an initially suspected person was later cleared, illustrating why legal-status history is required.
- November, Mariehäll: 28-year-old man killed; reporting described him as a leader of Bredängsnätverket.
- December, Rinkeby: man in his twenties killed; reporting described a connection to Dödspatrullen.

These bullets are research leads, not completed records. Each must be rebuilt from sources before being considered database-ready.

### 2017 southern Sweden examples to expand

Existing research identified a March 2017 Malmö incident in which a 23-year-old man was killed and a 22-year-old man seriously injured. Later reporting described the dead man's brother being shot at, making this a useful candidate for an explicit cross-incident family relation.

Another March 2017 Malmö case involved a 23-year-old man who had reportedly witnessed an earlier murder and lived under threat before being killed. This should be researched as a possible `witness_to -> later victim_in` relation without preserving the real person's identity.

### Violence against relatives

Current research distinguishes several stages:

- threats/explosions against relatives were clearly established in reporting no later than 2020;
- deliberate shootings in which relatives substituted for the principal conflict target were described as a possible new development in early 2023;
- by autumn 2023, relatives and family-linked addresses were described as increasingly common targets.

Incident records must therefore distinguish `relative`, `wrong_address`, `wrong_person`, `associate` and `bystander`; these are not interchangeable categories.

## Research work queue

Build the catalogue chronologically and keep yearly completeness visible:

```text
2011 -> identify all supported fatal incidents first; then injured persons
2012 -> same
2013 -> same
...
2017 -> reconcile detailed media mapping with police totals
...
2023 -> pay particular attention to relatives, bystanders, young executors and linked retaliation chains
...
2026 -> research through the current date, while marking ongoing investigations as provisional
```

For each year record:

```text
YEAR:
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE:
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE:
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE:
COVERAGE: incomplete | partial | near-complete | complete-as-defined
KNOWN_GAPS:
```

Never label a year `complete-as-defined` solely because one media list has been exhausted. Reconcile against official totals and independent sources where possible.

## Connection to gameplay research

`gameplay_research_map.md` should contain aggregate patterns and design implications. This file contains the detailed evidence layer.

The useful outputs for BRUR are aggregate/systemic questions such as:

- how often violence reaches relatives or uninvolved people;
- how retaliation chains evolve;
- how victim/perpetrator ages change over time;
- how conflicts move geographically;
- how often vehicles, homes, public spaces or businesses become settings;
- how network membership and leadership relate to victimization;
- how arrests, convictions, deaths and power vacuums alter subsequent conflicts.

The detailed real-world records remain anonymized research evidence. BRUR should derive fictional systems and population-level patterns from them rather than reproducing individual real cases.
