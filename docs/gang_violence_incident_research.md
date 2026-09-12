# BRUR Gang-Violence Incident Research

Status: v0.2 — populated structured text research, intended for later database conversion
Coverage target: Sweden, 2011–present
Last research update: 2026-09-12

## Purpose

This file is the detailed incident/person layer behind `gameplay_research_map.md`. It catalogues deaths and injuries connected to Swedish criminal-network violence while preserving enough structure to convert the research into a database later.

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

National police shooting statistics become systematic from 2017. Earlier coverage therefore relies more heavily on Brå research and local/retrospective media mapping. A missing record means `not yet found`, not that an event did not occur.

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
- Official shooting totals are comparison baselines, not automatic gang/network counts.

## Controlled vocabulary

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

## Incident record format

```text
INCIDENT: SE-YYYY-NNNN
DATE:
LOCATION:
MUNICIPALITY:
REGION:
INCIDENT_TYPE:
CONFLICT:
SUMMARY:

VICTIMS:
- PERSON: V1
  OUTCOME:
  AGE:
  SEX:
  HOME_LOCATION:
  TARGET_STATUS:
  NETWORK:
  NETWORK_STATUS:
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

## Research confidence

```text
HIGH   = authoritative record or multiple strong independent sources agree
MEDIUM = credible established reporting supports the claim but primary confirmation is absent/incomplete
LOW    = preliminary, single-source, ambiguous or conflicting reporting
UNKNOWN = not researched enough to rate
```

## National and regional comparison baseline

These figures are context, not a count of confirmed gang/network cases.

| Year | Official/strong comparison figure | Notes | Coverage of detailed catalogue |
| --- | --- | --- | --- |
| 2011 | 17 firearm-homicide victims nationally in Brå's total lethal-violence series | not equivalent to gang violence | incomplete |
| 2012 | no uniform national police shooting series yet | Göteborg gang-conflict escalation becomes visible in retrospective reporting | incomplete |
| 2013 | Stockholm 90 shootings/7 dead; Storgöteborg 56/8 dead | local police figures | incomplete |
| 2014 | Stockholm 88/10; Storgöteborg about 50/4 dead and about 20–24 injured | local police/SVT mapping | incomplete |
| 2015 | Stockholm 97/11; Storgöteborg 31–32/7 dead, 27 injured | includes major Biskopsgården conflict incidents | partial |
| 2016 | Stockholm 119/10; Storgöteborg 39/6; late-2016 three-city snapshot: Malmö 6 dead/26 injured, Göteborg 5/9, Stockholm 7/43 | pre-national-series local data | partial |
| 2017 | 320 shootings, 43 dead, 140 injured nationally | police: almost all fatal shootings linked to criminal conflicts in vulnerable areas | partial-to-near-complete for fatal shooting leads; not all injuries individually coded |
| 2018 | national police series available; first half 22 dead/66 injured | SVT interactive national series starts 2018 | partial |
| 2019 | first half 22 dead/55 injured; Stockholm County full year 17 dead | national archive available | partial |
| 2020 | 380 shootings, 55 dead, 120 injured | police annual series | partial |
| 2021 | 345 shootings, 46 dead, 115 injured | police explicitly notes no network-link requirement in this statistic | partial |
| 2022 | 391 shootings, 62 dead, 107 injured | police describes high conflict level among loosely organized criminal groups | partial |
| 2023 | approximately 368–370 shootings, 54–55 dead, 108–112 injured depending final statistical revision | major Foxtrot/internal-conflict and relative-targeting escalation | partial |
| 2024 | 296 shootings, 44 dead, 66 injured | police annual series | partial |
| 2025 | 158 shootings, 46 dead, 44 injured | includes Campus Risbergska mass shooting and therefore cannot be read as gang totals | partial |
| 2026 | Jan–Jun: 39 shootings, 8 dead, 15 injured; Jan–Aug: 53 shootings | current year, ongoing | partial/provisional |

### Aggregate victim/perpetrator characteristics from Brå

Brå's study of lethal violence in criminal conflicts 2005–2017 contains 216 victims. Median victim age fell from 32.5 in 2005–2012 to 25 in 2013–2017. Median age among identified perpetrators fell from 28 to 25, while suspects had a median age of 23 in 2013–2017. The increase in later years was concentrated among young men, especially ages 18–24. Children under 18 were rare but did occur, including cases where very young children were probably not the intended target.

A later Brå investigation of firearm killings in criminal environments found 121 deceased victims in its study set; almost all were men, median age 25, and four were under 18.

## Verified detailed incident catalogue

The catalogue below contains incidents for which the current source set provides enough detail to create a stable anonymized record. It is not yet a claim of exhaustive coverage for every year.

### 2012

#### SE-2012-0001 — Biskopsgården conflict escalation

```text
DATE: summer 2012
LOCATION: Önskevädersgatan, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: Biskopsgården criminal-network conflict
SUMMARY: A 23-year-old man was shot dead. Uppdrag granskning later identified this killing as the starting point of a violence spiral that continued through subsequent years.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 23
  SEX: male
  HOME_LOCATION: unknown
  TARGET_STATUS: intended
  NETWORK: unknown
  NETWORK_STATUS: unknown

SUSPECTS/PERPETRATORS:
  unknown in current source set

RESEARCH_CONFIDENCE: MEDIUM
```

### 2013

#### SE-2013-0001 — Väderilsgatan double killing

```text
DATE: 2013-09 (exact day not yet coded)
LOCATION: Väderilsgatan, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: Biskopsgården criminal-network conflict
SUMMARY: Two males, aged 17 and 28, were killed when two unmasked shooters fired at a group near a walkway. Retrospective UG reporting places the incident inside the ongoing gang conflict.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 17
  SEX: male
  TARGET_STATUS: unknown
  NETWORK_STATUS: unknown
- PERSON: V2
  OUTCOME: killed
  AGE: 28
  SEX: male
  TARGET_STATUS: unknown
  NETWORK_STATUS: unknown

RESEARCH_CONFIDENCE: MEDIUM
```

YEAR: 2013
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: 2
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: 0
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: Stockholm 7 dead in 90 shootings; Storgöteborg 8 dead in 56 shootings
COVERAGE: incomplete
KNOWN_GAPS: most Stockholm, Malmö and Göteborg person-level incidents not yet reconstructed

### 2014

YEAR: 2014
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: not yet reconciled person-by-person
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: not yet reconciled person-by-person
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: Storgöteborg about 50 shootings, 4 dead, about 20–24 injured; Stockholm 88 shootings, 10 dead
COVERAGE: incomplete
KNOWN_GAPS: SVT has a complete Göteborg shooting list, but each event still needs network-link filtering and individual coding

### 2015

#### SE-2015-0001 — Vår krog och bar / Vårväderstorget

```text
DATE: 2015-03-18
LOCATION: Vårväderstorget, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: North/South Biskopsgården criminal-network conflict
SUMMARY: Two masked shooters armed with automatic weapons attacked a restaurant. Two men were killed and eight people were shot and injured. Prosecutors treated ten additional people in the restaurant as attempted-murder victims. Courts later convicted several participants for involvement, but the appeal court did not identify which convicted persons were the actual shooters.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 25
  SEX: male
  TARGET_STATUS: intended
  NETWORK: Biskopsgården conflict side, exact label not stored
  NETWORK_STATUS: alleged_member
  RELATION_TO_CONFLICT: reporting described him as likely principal target
- PERSON: V2
  OUTCOME: killed
  AGE: 20
  SEX: male
  TARGET_STATUS: bystander
  NETWORK: none_known
  NETWORK_STATUS: none_known
  RELATION_TO_CONFLICT: reporting described no criminal background; present to collect food
- PERSONS: V3-V10
  OUTCOME: injured
  AGE: mixed/unknown
  SEX: predominantly male/individual coding pending
  TARGET_STATUS: mixed; several bystanders
  NETWORK_STATUS: mixed/unknown

SUSPECTS/PERPETRATORS:
- PERSONS: P1-P7
  SEX: male
  ROLE: participation in planned attack
  LEGAL_STATUS: convicted
  LEGAL_STATUS_HISTORY: district-court convictions later reframed by appeal court primarily as aiding/abetting because actual shooters could not be proven among defendants

EVENT:
  METHOD: automatic firearms
  SETTING: restaurant/public venue
  VEHICLE_INVOLVED: yes, getaway vehicle
  TARGET_TYPE: person in criminal-network conflict inside crowded venue
  RETALIATION: conflict-related
  BYSTANDERS_PRESENT: yes, many

RESEARCH_CONFIDENCE: HIGH
```

#### SE-2015-0002 — Torslanda vehicle explosion

```text
DATE: 2015-06-12
LOCATION: near Torslanda fire station
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: explosion
CONFLICT: Göteborg/Biskopsgården criminal-network conflict, connection publicly investigated/reported
SUMMARY: A vehicle exploded and all four occupants died. One man in his 30s was described as a prominent gang member. A four-year-old girl was among the dead. Later reporting treated the event as connected to the wider conflict, while early police reporting still considered both an accidental-onboard-explosive theory and an externally planted device.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 30s
  SEX: male
  TARGET_STATUS: intended_or_unknown
  NETWORK_STATUS: member/leader-level reporting
- PERSON: V2
  OUTCOME: killed
  AGE: 29
  SEX: male
  TARGET_STATUS: associate_or_unknown
- PERSON: V3
  OUTCOME: killed
  AGE: 33
  SEX: male
  TARGET_STATUS: associate_or_unknown
- PERSON: V4
  OUTCOME: killed
  AGE: 4
  SEX: female
  TARGET_STATUS: bystander
  NETWORK: none_known
  NETWORK_STATUS: none_known

RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

YEAR: 2015
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: 6
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: 8 individually unresolved + other year incidents missing
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: Storgöteborg 7 shooting deaths, 27 injured; Stockholm 11 shooting deaths
COVERAGE: partial
KNOWN_GAPS: most Stockholm/Malmö incidents and several Göteborg shootings

### 2016

#### SE-2016-0001 — Dimvädersgatan grenade attack

```text
DATE: 2016-08-22
LOCATION: Dimvädersgatan, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: grenade_attack
CONFLICT: Biskopsgården criminal-network conflict
SUMMARY: A hand grenade was thrown into an apartment where several people, many of them children, were present. An eight-year-old boy visiting with his family was killed. The apartment was the home of the mother of a man convicted over the Vår krog och bar attack, creating a documented relation between a prior conflict participant and the attacked residence.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 8
  SEX: male
  HOME_LOCATION: visiting family; exact location not stored
  TARGET_STATUS: bystander
  NETWORK: none_known
  NETWORK_STATUS: none_known
  RELATION_TO_CONFLICT: child guest at conflict-linked address

EVENT:
  METHOD: hand grenade thrown into residence
  SETTING: apartment/home
  TARGET_TYPE: conflict-linked household/address
  RELATIVE_TARGETING: yes/address-linked
  BYSTANDERS_PRESENT: yes, including several children

RESEARCH_CONFIDENCE: HIGH
```

#### SE-2016-0002 — central Göteborg gang-linked shooting injury

```text
DATE: 2016-05-20
LOCATION: Vasagatan
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
SUMMARY: A man was shot several times in central Göteborg and seriously injured. Police stated that he had links to conflicts between criminal groups in Göteborg.

VICTIMS:
- PERSON: V1
  OUTCOME: injured
  AGE: unknown
  SEX: male
  TARGET_STATUS: intended
  NETWORK_STATUS: alleged_associate

RESEARCH_CONFIDENCE: HIGH for injury and police-stated gang link; LOW for exact conflict/network
```

YEAR: 2016
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: 1
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: 1
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: late-November snapshot Malmö 6 dead/26 injured, Göteborg 5 dead/9 injured, Stockholm 7 dead/43 injured in shootings; full-year local totals differ slightly
COVERAGE: partial
KNOWN_GAPS: most 2016 person-level cases are still uncoded

### 2017

Police reported 320 shootings, 43 killed and 140 injured nationally. Police said almost all shootings with fatal outcome could be linked to criminal conflicts in vulnerable areas, while roughly half of all shootings had such links. SVT's nationwide fatal-shooting map supplies a strong starting set but still contains non-gang cases; entries below only include cases with a conflict/network signal or useful unresolved criminal-environment link.

#### SE-2017-0001 — Sundbyberg pursuit killing

```text
DATE: 2017-01-22
LOCATION: Sundbyberg / route toward hospital
REGION: Stockholm
INCIDENT_TYPE: shooting + vehicle pursuit
SUMMARY: A 25-year-old man was first shot, driven toward hospital, then pursued; the vehicle was forced off the road and he was killed by a shot to the head. Police suspected links to previous violent incidents. Six childhood friends were suspects at the reporting date.
VICTIM: V1 | killed | male | 25 | intended | network unknown
SUSPECTS: P1-P6 | male | suspected at reporting date | final legal outcomes not yet coded
RESEARCH_CONFIDENCE: HIGH incident / MEDIUM conflict attribution
```

#### SE-2017-0002 — Skärholmen double shooting

```text
DATE: 2017-02-01
LOCATION: Skärholmen
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIMS:
- V1 | killed | male | 20s | target status unknown
- V2 | seriously injured | sex/age not yet coded | target status unknown
LEGAL_STATUS: two defendants initially convicted of murder/attempted murder; appeal court changed the convictions to aiding causing another's death and reduced sentences.
RESEARCH_CONFIDENCE: HIGH incident/legal chronology; network motive not yet coded
```

#### SE-2017-0003 — Kista vehicle double murder

```text
DATE: 2017-03-08
LOCATION: Kista
REGION: Stockholm
INCIDENT_TYPE: shooting
SUMMARY: Three people sat in a car; the rear-seat passenger shot the two men in front and left. Police sources described one victim as a leading figure in Lejonen. A 30-year-old man was later convicted and sentenced to life imprisonment.
VICTIMS:
- V1 | killed | male | age unknown | intended | Lejonen | leader
- V2 | killed | male | age unknown | intended_or_associate | network unknown
PERPETRATOR:
- P1 | male | 30 at reporting | convicted | life sentence
RESEARCH_CONFIDENCE: HIGH
```

#### SE-2017-0004 — Uppsala suspected contract killing

```text
DATE: 2017-04-01
LOCATION: Boländerna, Uppsala
REGION: Mitt
INCIDENT_TYPE: shooting
SUMMARY: A man was shot dead outside a restaurant. Prosecutor described the attack as a contract killing. The victim had previously been suspected of killing a Södertälje-network profile in 2013 but had been acquitted. Ten people were later detained in a large operation; four were remanded, but evidence did not reach prosecution at the time of the source.
VICTIM: V1 | killed | male | age unknown | intended | relation: previously acquitted in Södertälje-network homicide case
SUSPECTS: multiple | suspected/remanded historically | no prosecution in source state
RESEARCH_CONFIDENCE: HIGH incident / MEDIUM motive
```

#### SE-2017-0005 — Järfälla killing

```text
DATE: 2017-05-21
LOCATION: near Görvälnsbadet, Järfälla
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 18 | intended | network unknown
CONFLICT: reporting described murder as part of gang war in western Stockholm
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

#### SE-2017-0006 — Vårberg double shooting

```text
DATE: 2017-07-20
LOCATION: Vårberg
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIMS:
- V1 | killed | male | 20s | target status unknown
- V2 | injured, shot in hand | age/sex male implied by source | target status unknown
SUSPECTS: none arrested at source date
RESEARCH_CONFIDENCE: HIGH incident; LOW current network classification
```

#### SE-2017-0007 — Östberga conflict shooting

```text
DATE: 2017-08-15
LOCATION: Östberga torg
REGION: Stockholm
INCIDENT_TYPE: shooting
CONFLICT: ongoing criminal-group conflict in southern Stockholm
VICTIMS:
- V1 | killed | male | age unknown | intended_or_unknown
- V2 | injured, leg wound | male | age unknown
METHOD: automatic rifle evidence reported at scene
RESEARCH_CONFIDENCE: HIGH incident / MEDIUM conflict relation
```

#### SE-2017-0008 — Stenhagen suspected retaliation

```text
DATE: 2017-08-18
LOCATION: Stenhagen, Uppsala
REGION: Mitt
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 30s | intended
SUSPECTED_MOTIVE: possible retaliation for a shooting hours earlier in Västerås where two men were injured
LEGAL_STATUS: a 20-year-old was initially suspected; suspicion was later dropped and he was released
RELATION: SE-2017-0008 -> possible_retaliation_for -> uncoded Västerås shooting same day
RESEARCH_CONFIDENCE: HIGH incident/legal update / LOW-MEDIUM motive
```

#### SE-2017-0009 — Mariehäll killing of alleged network leader

```text
DATE: 2017-11-20
LOCATION: Mariehäll/Bromma
REGION: Stockholm
INCIDENT_TYPE: shooting from moving vehicle / pursuit
VICTIM: V1 | killed | male | 28 | intended | Bredängsnätverket | leader (publicly described)
SUSPECTED_MOTIVE: reporting discussed possible retaliation for earlier murder(s)
SUSPECTS: at least three arrested at source date
RESEARCH_CONFIDENCE: HIGH victim/network attribution in reporting; MEDIUM motive
```

#### SE-2017-0010 — Rinkeby garage killing

```text
DATE: 2017-12-31
LOCATION: Rinkeby
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 20s | intended | Dödspatrullen | alleged_associate
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

#### SE-2017-0011 — Docentgatan execution-style killing

```text
DATE: 2017-01-03
LOCATION: Docentgatan, Malmö
REGION: Syd
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 20s | intended
EVENT: victim hit by 22 shots; police described it as an execution
LEGAL_STATUS: 22-year-old arrested on suspicion of aiding murder, later released in source state
RESEARCH_CONFIDENCE: HIGH incident / LOW current network attribution
```

#### SE-2017-0012 — Kronetorpsgatan plus later attack on victim's brother

```text
DATE: 2017-03-04
LOCATION: Kronetorpsgatan, Malmö
REGION: Syd
INCIDENT_TYPE: shooting
VICTIMS:
- V1 | killed | male | 23 | intended
- V2 | seriously injured | male | 22 | intended_or_associate
FOLLOW-UP: weeks later V1's brother was shot at but survived
SUSPECTS: two men aged 23 and 20 remanded for aiding murder and also sought/remanded in relation to attempted murder of the brother
RELATION: follow-up incident -> relative_of(V1) and linked_to SE-2017-0012
RESEARCH_CONFIDENCE: HIGH
```

#### SE-2017-0013 — Ramels väg witness killing

```text
DATE: 2017-03-30
LOCATION: Ramels väg, Malmö
REGION: Syd
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 23 | witness | network unknown
RELATION_TO_CONFLICT: source reported he had witnessed an earlier January murder and was living under threat
RELATION: V1 -> witness_to -> earlier Malmö homicide (not yet assigned stable incident ID)
RESEARCH_CONFIDENCE: HIGH for witness relation; motive connection remains MEDIUM unless later judicially established
```

#### SE-2017-0014 — Eriksfältsgatan double shooting

```text
DATE: 2017-11-30
LOCATION: Eriksfältsgatan, Malmö
REGION: Syd
INCIDENT_TYPE: shooting
VICTIMS:
- V1 | killed | male | 20
- V2 | critically injured | male | age unknown
SUSPECT: P1 | male | 28 | arrested/suspected of murder and attempted murder at source date
RESEARCH_CONFIDENCE: HIGH incident; network motive not yet coded
```

YEAR: 2017
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: 17 in currently coded conflict/likely-criminal-environment records above
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: at least 7 individually represented above, plus major uncoded injury population
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 43 killed and 140 injured in all police-confirmed shootings nationally
COVERAGE: partial-to-near-complete for fatal-shooting research leads, incomplete for injured victims and network filtering
KNOWN_GAPS: remaining 2017 fatal cases need gang/non-gang classification; all 140 injured persons cannot yet be individually reconstructed from open sources

### 2018–2021

The national police/SVT shooting archive is available from 2018 onward, but the person-level pass for these four years is not yet exhaustive. Do not infer gang membership from presence in the shooting dataset alone.

YEAR: 2018
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: national police series available; first-half benchmark 22 dead/66 injured
COVERAGE: incomplete
KNOWN_GAPS: person-level extraction and conflict filtering pending

YEAR: 2019
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: first-half benchmark 22 dead/55 injured; Stockholm County full-year 17 dead in shootings
COVERAGE: incomplete
KNOWN_GAPS: person-level extraction and conflict filtering pending

YEAR: 2020
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 380 shootings, 55 dead, 120 injured
COVERAGE: partial
KNOWN_GAPS: person-level extraction pending; relatives were already documented as frequent targets of threats/explosions by this year

YEAR: 2021
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 345 shootings, 46 dead, 115 injured
COVERAGE: partial
KNOWN_GAPS: police statistic contains all illegal confirmed shootings, not only network violence

### 2022

YEAR: 2022
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 391 shootings, 62 dead, 107 injured
COVERAGE: partial
KNOWN_GAPS: person-level catalogue not yet exhaustive
RESEARCH_NOTE: Police described a high conflict level among loosely organized criminal groupings and more execution-style attacks intended to kill rather than injure.

### 2023

2023 is treated as a major breakpoint. Diamant Salihu's year-end analysis describes an internal Foxtrot split in which seven people were killed in 14 days during September, and emphasizes the new scale of violence directed at family members.

#### SE-2023-0001 — family-targeting wave, Stockholm region

```text
DATE: early 2023, multiple incidents
LOCATION: Stockholm region
INCIDENT_TYPE: shooting(s)
CONFLICT: criminal-network conflict
SUMMARY: Multiple shootings were investigated where relatives of criminally involved persons were suspected intended targets. Contemporary criminology commentary described deliberate targeting of relatives/friends as potentially a new development in shootings.
VICTIMS: multiple, individual IDs pending source-by-source reconstruction
TARGET_STATUS: relative
RESEARCH_CONFIDENCE: HIGH for pattern; individual catalogue pending
```

#### SE-2023-0002 — Västberga family shooting

```text
DATE: 2023-10 (exact date to reconcile)
LOCATION: Västberga, Stockholm
REGION: Stockholm
INCIDENT_TYPE: shooting
SUMMARY: A family's home was attacked. The father was killed and the mother injured. Reporting stated that the family had no gang connection and investigated whether a shared surname with an intended gang-conflict target contributed to the attack.
VICTIMS:
- V1 | killed | male | adult | wrong_person_or_wrong_address | none_known
- V2 | injured | female | adult | wrong_person_or_wrong_address | none_known
RELATION_TO_CONFLICT: possible mistaken identity/surname relation
RESEARCH_CONFIDENCE: MEDIUM-HIGH; motive classification remains provisional
```

#### SE-2023-0003 — Foxtrot internal-conflict September cluster

```text
DATE: September 2023
LOCATION: Stockholm/Uppsala and other affected locations
INCIDENT_TYPE: multiple shootings/explosions
CONFLICT: internal Foxtrot split and connected conflicts
SUMMARY: Diamant Salihu's year-end analysis states that seven people were killed in 14 days during the September escalation. Individual incidents must remain separately coded; this cluster record exists only as a conflict-level grouping.
VICTIMS: 7 killed in cited 14-day cluster; individual age/sex/location coding pending
NETWORK: Foxtrot-related internal conflict
RESEARCH_CONFIDENCE: HIGH for cluster count in cited analysis
```

YEAR: 2023
KNOWN_GANG_RELATED_DEATHS_IN_CATALOGUE: cluster evidence includes at least 7 conflict-linked deaths, plus individually documented family/wrong-target case(s); full count pending
KNOWN_GANG_RELATED_INJURED_IN_CATALOGUE: incomplete
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: approximately 368–370 shootings, 54–55 dead, 108–112 injured after later statistical revisions
COVERAGE: partial
KNOWN_GAPS: full incident-by-incident 2023 extraction, especially September wave and all relatives/bystanders

### 2024

#### SE-2024-0001 — Flemingsberg relative-targeting injury

```text
DATE: 2024-05-19
LOCATION: Flemingsberg
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIM: V1 | seriously injured | male | 60s | relative | none_known for victim
RELATION_TO_CONFLICT: SVT reported that a relative of the victim was a member of a criminal gang
TARGET_STATUS: relative
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

#### SE-2024-0002 — Hovsjö teenage victim

```text
DATE: 2024-07-23
LOCATION: Hovsjö centrum, Södertälje
REGION: Stockholm
INCIDENT_TYPE: shooting
CONFLICT: Nätverk Södertälje vs Nätverk Telge (formerly described as Ronnafalangen/Saltskogsfalangen)
VICTIM: V1 | seriously injured, survived | male | teenager | intended | linked by police to one Södertälje network
SUSPECTS/PERPETRATORS:
- P1 | teenager | admitted being shooter according to later reporting | convicted | youth care
- P2 | teenager | convicted in relation to attempted murder | youth care
RESEARCH_CONFIDENCE: HIGH
```

#### SE-2024-0003 — Hallstahammar killing

```text
DATE: 2024-09-19
LOCATION: central Hallstahammar
REGION: Mitt
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | young adult | home location: southern Stockholm suburbs | target status unknown
CONFLICT: sources to SVT described possible connection to conflict between Rawa Majid's Foxtrot side and Ismail Abdo's competing network
SUSPECT: P1 | male | suspected of aiding murder at source date
RESEARCH_CONFIDENCE: HIGH incident / MEDIUM network attribution
```

YEAR: 2024
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 296 shootings, 44 dead, 66 injured
COVERAGE: partial
KNOWN_GAPS: most fatal/injury records still need individual extraction

### 2025

#### SE-2025-0001 — Fruängen teenage killing

```text
DATE: 2025-03-02
LOCATION: Fruängen, Stockholm
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 16 | target status unknown
CONFLICT: sources to SVT described possible link to conflict between criminal groups amplified through music/social-media threats
NETWORK_STATUS: unknown for victim
RESEARCH_CONFIDENCE: HIGH incident / MEDIUM conflict attribution
```

#### SE-2025-0002 — Bromma killing filmed and distributed

```text
DATE: 2025-11-05
LOCATION: Bromma, Stockholm
REGION: Stockholm
INCIDENT_TYPE: shooting
VICTIM: V1 | killed | male | 20s | network status not coded
EVENT: close-range shooting was filmed and circulated online within minutes; police described broader growth in filming/distribution of gang-environment killings
RESEARCH_CONFIDENCE: HIGH incident; exact network/motive pending
```

YEAR: 2025
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: 158 shootings, 46 dead, 44 injured, but total includes the non-gang Campus Risbergska mass shooting
COVERAGE: partial
KNOWN_GAPS: official totals require event-level exclusion before gang/network counts can be produced

### 2026

YEAR: 2026
OFFICIAL_COMPARISON_TOTAL_IF_AVAILABLE: Jan–Jun 39 shootings, 8 dead, 15 injured; Jan–Aug 53 shootings, with one injury and no deaths recorded in August itself
COVERAGE: partial/provisional
KNOWN_GAPS: current-year investigations and final classifications; person-level extraction through September 12 not yet complete

## Cross-incident research findings already supported

### Relatives and family-linked addresses

- 2016: a child bystander was killed in a grenade attack on an address linked to a man convicted in the Vår krog case.
- By 2020: Swedish Radio reported that explosions and death threats from criminal networks were often directed at family members of the actual target.
- Early 2023: deliberate shootings of relatives/friends were described as a possible new development.
- Autumn 2023: relatives and family-linked addresses were described as increasingly common targets; police were conducting large-scale risk assessment of potential targets/addresses.
- 2024: a man in his 60s was seriously injured in Flemingsberg; reporting stated that a relative belonged to a criminal gang.
- 2025: reporting described relatives being named/threatened in music and social media around criminal conflicts.

### Bystanders and wrong targets

The file must distinguish:

```text
bystander != relative != wrong_person != wrong_address != associate
```

Documented examples already include:

- 2015 Vår krog: 20-year-old killed despite no known criminal background, plus several injured bystanders.
- 2015 Torslanda: four-year-old girl killed in vehicle explosion connected in reporting to gang conflict.
- 2016 Dimvädersgatan: eight-year-old boy killed while visiting a conflict-linked household.
- 2023 Västberga: family with no known gang link attacked; possible mistaken identity/surname mechanism investigated.

### Witnesses becoming victims

The March 2017 Ramels väg case is an explicit candidate relation:

```text
PERSON -> witness_to -> earlier homicide
PERSON -> later victim_in -> SE-2017-0013
```

The causal motive must remain separately evidenced; being a witness does not itself prove why the later killing occurred.

### Victim/perpetrator overlap

Brå's research supports treating network violence as a repeated-interaction system rather than isolated events: victims and suspects/perpetrators often resemble one another demographically and may recur in criminal cases over time. The detailed catalogue should therefore preserve prior victimization, prior suspect status and network-role changes whenever those facts are strongly sourced.

## Source register

### Official / research

- Brå, `Dödligt våld i den kriminella miljön 2005–2017`: https://bra.se/rapporter/arkiv/2020-04-02-dodligt-vald-i-den-kriminella-miljon
- Brå, `Utredning och uppklaring av dödligt våld i kriminell miljö`: https://bra.se/rapporter/arkiv/2023-03-07-utredning-och-uppklaring-av-dodligt-vald-i-kriminell-miljo
- Brå topic page, `Våld i kriminella miljöer`: https://bra.se/amnen/vald-i-kriminella-miljoer
- Polismyndigheten, current and archived shooting/explosion statistics: https://polisen.se/om-polisen/polisens-arbete/sprangningar-och-skjutningar/
- Polismyndigheten, 2022 annual report: https://polisen.se/siteassets/dokument/polisens-arsredovisning/polismyndighetens-arsredovisning-2022.pdf/download/
- Polismyndigheten, 2023 annual report: https://polisen.se/b12edf3008f151314bc931f719765f2b/siteassets/dokument/polisens-arsredovisning/polismyndighetens-arsedovisning-2023.pdf
- Polismyndigheten, 2024 annual report: https://polisen.se/bee739fd2259ec74421dda08a877b250/siteassets/dokument/polisens-arsredovisning/polismyndighetens-arsredovisning-2024.pdf

### Detailed media mappings and incident sources

- SVT, national fatal-shooting map 2017: https://www.svt.se/special/dodsskjutningar-2017/
- SVT, Stockholm/middle/north 2017: https://www.svt.se/special/dodsskjutningar-2017-stockholm/
- SVT, South 2017: https://www.svt.se/special/dodsskjutningar-2017-syd/
- SVT, West 2017: https://www.svt.se/special/dodsskjutningar-2017-vast/
- SVT, year-by-year shootings from 2018: https://www.svt.se/datajournalistik/skjutningar-i-sverige-ar-for-ar/
- SVT/UG, Göteborg gang-conflict retrospective: https://www.svt.se/nyheter/granskning/ug/30-doda-pa-fem-ar-i-gangkrigets-goteborg
- SVT, Vår krog case chronology: https://www.svt.se/nyheter/lokalt/vast/dubbelmordet-pa-var-krog-och-bar-detta-har-hant
- SVT, Vårväderstorget victim analysis: https://www.svt.se/nyheter/lokalt/vast/totalt-20-offer-vid-varvaderstorget
- SVT, Torslanda child victim/gang link: https://www.svt.se/nyheter/lokalt/vast/polisen-bekraftar-explosionen-har-gangkoppling
- SVT, 2016 Dimvädersgatan child victim: https://www.svt.se/nyheter/lokalt/vast/attaarige-yuusuf-blev-offer-for-handgranaten
- SVT, 2023 year analysis by Diamant Salihu: https://www.svt.se/nyheter/inrikes/diamant-salihu-sa-har-det-varit-att-bevaka-gangkriget-2023
- SVT, 2024 Flemingsberg analysis by Diamant Salihu: https://www.svt.se/nyheter/lokalt/stockholm/diamant-salihu-om-senaste-tidens-skjutningar-risk-att-det-kan-eskalera-annu-mer
- SVT, 2024 Hovsjö case/court outcome: https://www.svt.se/nyheter/lokalt/sodertalje/samma-tryckarlagenhet-anvandes-vid-mordforsok-och-planerad-skjutning-nu-doms-flera-personer
- SVT, 2024 Hallstahammar/Foxtrot conflict reporting: https://www.svt.se/nyheter/lokalt/vastmanland/stor-polisinsats-i-hallstahammar
- SVT, 2025 music/social-media conflict reporting with Diamant Salihu: https://www.svt.se/kultur/sa-sprids-gangens-hot-av-svenska-musiktjanster
- SVT, 2025 filmed Bromma killing: https://www.svt.se/nyheter/lokalt/stockholm/videor-pa-dodsskjutningar-sprids-pa-natet-polisen-det-ar-olagligt

## Research work queue

The next population pass should proceed in this order:

```text
1. Finish every 2017 fatal case classification: gang/network / other / unresolved.
2. Extract every individually reported injured person from the 2017 maps and linked articles.
3. Run the SVT/police national shooting archive year-by-year for 2018–2025.
4. For each event with death/injury, add age, sex, locality and target status when public.
5. Add court-result updates so suspect status never remains stale when a later judgment exists.
6. Add explicit conflict/network edges from Diamant Salihu/UG/Brå and corroborating sources.
7. Reconcile yearly person counts against official totals while keeping non-network cases excluded.
8. For 2026, keep all entries provisional until investigations/legal classifications mature.
```

For each year retain:

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

Useful BRUR outputs include:

- how often violence reaches relatives or uninvolved people;
- how retaliation chains evolve;
- how victim/perpetrator ages change over time;
- how conflicts move geographically;
- how often vehicles, homes, public spaces or businesses become settings;
- how network membership and leadership relate to victimization;
- how arrests, convictions, deaths and power vacuums alter subsequent conflicts.

The detailed real-world records remain anonymized research evidence. BRUR should derive fictional systems and population-level patterns from them rather than reproducing individual real cases.
