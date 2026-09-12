# BRUR Gang-Violence Third-Party Victim Research

Status: v0.1 — structured text research for later database conversion
Coverage target: Sweden, 2011–present
Last research update: 2026-09-12

## Purpose

This file is the dedicated evidence layer for people who are not themselves participating in the criminal conflict but are killed, injured, endangered or otherwise directly affected by gang/network violence.

It complements:

- `gang_violence_incident_research.md`
- `gang_violence_source_supplement.md`

The core incident catalogue should continue to contain the event itself. This file makes third-party status first-class so these people are not reduced to a generic `bystander` note.

Real names are not stored. Network names may be retained when needed to understand the relation between the violence and the third party.

## Definition: third party / utomstående

For this research, a third party is a person who is not participating in the active criminal conflict in the incident being coded.

This includes distinct categories:

```text
bystander
wrong_person
wrong_address_resident
relative_noncriminal
partner_noncriminal
child_of_target
parent_of_target
sibling_of_target
friend_nonparticipant
witness_nonparticipant
worker_or_customer
passenger
neighbor
other_nonparticipant
unknown_nonparticipant
```

These must not be collapsed into one category. A non-criminal relative deliberately targeted is different from a random passer-by, and both differ from a person killed because the shooter mistook them for someone else.

## Third-party person schema

```text
THIRD_PARTY_PERSON: T-YYYY-NNNN
INCIDENT_ID:
OUTCOME: killed | injured | uninjured_target | endangered
AGE:
AGE_BAND:
SEX:
HOME_LOCATION:
INCIDENT_LOCATION:
THIRD_PARTY_TYPE:
TARGET_STATUS: unintended | deliberately_targeted_relative | wrong_person | wrong_address | unknown
NETWORK: none_known | unknown
NETWORK_STATUS: none_known | unknown
RELATION_TO_INTENDED_TARGET:
RELATION_TO_CONFLICT:
WHY_PRESENT:
INJURY_TYPE:
LONG_TERM_INJURY:
CHILD_PRESENT:
OTHER_RELATIONS:
SOURCE_CONFIDENCE:
NOTES:
```

## Third-party incident extension

Every relevant incident should additionally support:

```text
THIRD_PARTY_PRESENT: yes | no | unknown
THIRD_PARTY_KILLED:
THIRD_PARTY_INJURED:
THIRD_PARTY_UNINJURED_BUT_DIRECTLY_TARGETED:
THIRD_PARTY_ENDANGERED_ESTIMATE:
THIRD_PARTY_MECHANISM:
  stray_bullet
  indiscriminate_fire
  mistaken_identity
  wrong_address
  relative_targeting
  explosive_residue_or_abandoned_explosive
  blast_radius
  target_using_public_space
  other
```

## Aggregate evidence baseline

### 2011–2020

A study reported by SVT found at least 46 third-party people in 36 serious gang-related violent incidents in Sweden between 2011 and 2020. They were killed or injured despite being outside the active criminal conflict.

A separate SVT review reported 12 third parties killed and 19 injured during the six years preceding late 2020.

The same 2011–2020 study reported:

```text
FIRST_THREE_YEARS_OF_PERIOD: 4 third parties killed or injured
LAST_THREE_YEARS_OF_PERIOD: 24 third parties killed or injured
TOTAL_2011_2020: at least 46
INCIDENTS: 36
```

Interpretation: direct harm to outsiders increased substantially over the decade, but the underlying source set is not an official continuously maintained registry.

### 2022–2025 police comparison

Police figures reported by Sveriges Radio provide a newer comparison series:

```text
2022: fewer than half the 2023 level; exact final count not yet extracted here
2023: more than 28 third parties killed or injured; police reporting said the level was more than double 2022
2023 to 2025-04-29: 60 total; 22 killed + 38 injured
2025 full year: 18 total; 3 killed + 15 injured
2023 to end-2025: 72 total; 24 killed + 48 injured
```

Police-described mechanisms include:

- non-criminal relatives deliberately attacked;
- shooters or bombers selecting the wrong person;
- attacks at the wrong address;
- people simply being present at the location of the attack.

## Verified detailed third-party catalogue

### 2012

#### TP-SE-2012-0001 — Malmö wrong-person killing

```text
DATE: 2012-01-03
INCIDENT_LOCATION: Kantatgatan, Malmö
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2012-0001
OUTCOME: killed
AGE: 48
SEX: male
HOME_LOCATION: Malmö area / exact location not retained
THIRD_PARTY_TYPE: wrong_person
TARGET_STATUS: wrong_person
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: neighbor of intended target according to prosecution theory
RELATION_TO_CONFLICT: none established personally
WHY_PRESENT: at/near residence in daytime
INJURY_TYPE: multiple gunshot wounds

PERPETRATOR_SIDE:
- P1: male, 29 at later appeal reporting
- ROLE: shooter
- LEGAL_STATUS: convicted
- SENTENCE: 16 years after appeal

MECHANISM: mistaken_identity
RESEARCH_CONFIDENCE: HIGH
```

### 2013

#### TP-SE-2013-0001 — Tensta grill visitor seriously injured

```text
DATE: 2013, exact incident date pending reconciliation
INCIDENT_LOCATION: Tensta, Stockholm
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2013-0001
OUTCOME: injured
AGE: unknown
SEX: unknown in current source excerpt
THIRD_PARTY_TYPE: customer_or_visitor
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: none known; described as an outsider visiting the grill kiosk
WHY_PRESENT: visitor/customer at grill kiosk
INJURY_TYPE: gunshot injuries
LONG_TERM_INJURY: paralysis reported

MECHANISM: indiscriminate_or_misdirected_fire
RESEARCH_CONFIDENCE: MEDIUM-HIGH
NOTES: Later SVT reporting referenced this injury while describing the criminal background of a person in another 2017 gang-related case.
```

### 2015

#### TP-SE-2015-0001 — Vårväderstorget restaurant bystander killed

```text
DATE: 2015-03-18
INCIDENT_LOCATION: Vår krog och bar, Vårväderstorget, Göteborg
INCIDENT_TYPE: shooting
CONFLICT: Biskopsgården network conflict

THIRD_PARTY_PERSON: T-2015-0001
OUTCOME: killed
AGE: 20
SEX: male
HOME_LOCATION: unknown
THIRD_PARTY_TYPE: customer
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: none known
RELATION_TO_CONFLICT: none known
WHY_PRESENT: collecting/buying food at restaurant
INJURY_TYPE: gunshot wounds

MECHANISM: indiscriminate_fire_in_public_venue
RESEARCH_CONFIDENCE: HIGH
```

Additional third parties in the same incident:

```text
THIRD_PARTY_INJURED: several among eight shot and injured; individual age/sex coding still pending
THIRD_PARTY_ENDANGERED: prosecutors treated additional restaurant occupants as attempted-murder victims
```

#### TP-SE-2015-0002 — four-year-old killed in vehicle explosion

```text
DATE: 2015-06-12
INCIDENT_LOCATION: Torslanda, Göteborg
INCIDENT_TYPE: explosion

THIRD_PARTY_PERSON: T-2015-0002
OUTCOME: killed
AGE: 4
SEX: female
THIRD_PARTY_TYPE: child_passenger
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: child travelling in same vehicle as adults including a person publicly described as a gang leader
RELATION_TO_CONFLICT: none personally
WHY_PRESENT: passenger after family/social activity
INJURY_TYPE: blast injuries
CHILD_PRESENT: yes

MECHANISM: blast_radius/vehicle_explosion
RESEARCH_CONFIDENCE: HIGH for victim/outcome; motive mechanism remains less certain than victim status
```

#### TP-SE-2015-0003 — Hässelby square, two women injured

```text
DATE: 2015-06-11
INCIDENT_LOCATION: Hässelby torg, Stockholm
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSONS: T-2015-0003A, T-2015-0003B
OUTCOME: injured
AGE: unknown
SEX: female, female
THIRD_PARTY_TYPE: bystanders
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: none reported
WHY_PRESENT: public square
INJURY_TYPE: minor gunshot-related injuries

MECHANISM: shots fired at another person in public square
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

#### TP-SE-2015-0004 — Husby child and adult hit during shooting

```text
DATE: 2015-05-16
INCIDENT_LOCATION: Husby centrum, Stockholm
INCIDENT_TYPE: shooting during altercation

THIRD_PARTY_PERSON: T-2015-0004A
OUTCOME: injured
AGE: 7
SEX: male
THIRD_PARTY_TYPE: child_bystander
TARGET_STATUS: unintended
NETWORK: none_known
INJURY_TYPE: hit near/outside knee

THIRD_PARTY_PERSON: T-2015-0004B
OUTCOME: injured
AGE: 55s
SEX: male
THIRD_PARTY_TYPE: bystander
TARGET_STATUS: unintended
NETWORK: none_known
INJURY_TYPE: hit in mouth / survived

RELATION_TO_CONFLICT: source explicitly states neither injured person was involved in the fight
MECHANISM: public-space crossfire/stray bullets
RESEARCH_CONFIDENCE: HIGH for third-party status and age bands
```

### 2016

#### TP-SE-2016-0001 — eight-year-old killed in grenade attack on conflict-linked home

```text
DATE: 2016-08-22
INCIDENT_LOCATION: Dimvädersgatan, Biskopsgården, Göteborg
INCIDENT_TYPE: grenade_attack

THIRD_PARTY_PERSON: T-2016-0001
OUTCOME: killed
AGE: 8
SEX: male
THIRD_PARTY_TYPE: child_guest
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: guest in apartment associated with family member of person convicted in earlier gang-conflict shooting
RELATION_TO_CONFLICT: none personally
WHY_PRESENT: visiting family/household
INJURY_TYPE: blast injuries
CHILD_PRESENT: yes

MECHANISM: attack_on_conflict_linked_address / blast_radius
RESEARCH_CONFIDENCE: HIGH
```

### 2018

#### TP-SE-2018-0001 — 22-year-old killed after mistaken identity

```text
DATE: 2018, exact date pending source reconciliation
INCIDENT_LOCATION: Segeltorp, Huddinge
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2018-0001
OUTCOME: killed
AGE: 22
SEX: male
THIRD_PARTY_TYPE: wrong_person
TARGET_STATUS: wrong_person
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: mistaken for another man
RELATION_TO_CONFLICT: none personally
WHY_PRESENT: had left a restaurant with cousin
INJURY_TYPE: multiple gunshot wounds; SVT reports 13 shots

MECHANISM: mistaken_identity
RESEARCH_CONFIDENCE: HIGH
```

#### TP-SE-2018-0002 — 63-year-old killed by abandoned hand grenade

```text
DATE: 2018, exact date pending source reconciliation
INCIDENT_LOCATION: Vårby gård, Huddinge
INCIDENT_TYPE: grenade_explosion

THIRD_PARTY_PERSON: T-2018-0002A
OUTCOME: killed
AGE: 63
SEX: male
THIRD_PARTY_TYPE: passerby
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: none known
WHY_PRESENT: cycling home from work with spouse
INJURY_TYPE: blast injuries after picking up object believed to be harmless

THIRD_PARTY_PERSON: T-2018-0002B
OUTCOME: injured
AGE: unknown
SEX: female
THIRD_PARTY_TYPE: spouse/passerby
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: none known
WHY_PRESENT: cycling home with spouse
INJURY_TYPE: blast injuries
RELATION_TO_OTHER_PERSON: spouse_of T-2018-0002A

MECHANISM: abandoned_explosive / blast_radius
RESEARCH_CONFIDENCE: HIGH
```

### 2019

#### TP-SE-2019-0001 — 31-year-old mother killed while holding infant

```text
DATE: 2019-08
INCIDENT_LOCATION: Ribersborg, Malmö
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2019-0001
OUTCOME: killed
AGE: 31
SEX: female
THIRD_PARTY_TYPE: partner_nonparticipant
TARGET_STATUS: unintended_or_partner_of_target
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: partner of man described in reporting as possible intended target
RELATION_TO_CONFLICT: none personally established
WHY_PRESENT: walking/standing with partner and infant
CHILD_PRESENT: yes, newborn/infant in arms
INJURY_TYPE: gunshot wounds

MECHANISM: target_in_close_proximity_to_nonparticipant
RESEARCH_CONFIDENCE: HIGH for victim/outcome; MEDIUM for intended-target theory
```

#### TP-SE-2019-0002 — 18-year-old wife killed in home attack

```text
DATE: 2019-08-28
INCIDENT_LOCATION: Råcksta, Stockholm
INCIDENT_TYPE: shooting through residence/window

THIRD_PARTY_PERSON: T-2019-0002
OUTCOME: killed
AGE: 18
SEX: female
HOME_LOCATION: grew up in Fisksätra/Nacka; living in Råcksta at incident
THIRD_PARTY_TYPE: spouse_nonparticipant
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: wife of 33-year-old man identified by police/prosecutor as intended target
RELATION_TO_CONFLICT: none personally established
WHY_PRESENT: at home/in bed
INJURY_TYPE: multiple gunshot wounds

MECHANISM: intended_target_shared_residence
RESEARCH_CONFIDENCE: HIGH
```

#### TP-SE-2019-0003 — Nacka taxicab driver and music student injured

```text
DATE: 2019-09-08
INCIDENT_LOCATION: Alphyddan/Sickla, Nacka
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2019-0003A
OUTCOME: injured
AGE: unknown
SEX: male
THIRD_PARTY_TYPE: worker/taxi_driver
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: none
RELATION_TO_CONFLICT: none
WHY_PRESENT: working/driving taxi
INJURY_TYPE: gunshot injury

THIRD_PARTY_PERSON: T-2019-0003B
OUTCOME: injured
AGE: 25
SEX: male
THIRD_PARTY_TYPE: resident/student
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: none
RELATION_TO_CONFLICT: none
WHY_PRESENT: inside apartment near street shooting
INJURY_TYPE: shot in eye by stray bullet from automatic weapon
LONG_TERM_INJURY: loss of sight in one eye

INTENDED_TARGET: same 33-year-old man believed targeted in TP-SE-2019-0002
MECHANISM: stray_bullet / public-to-residential spillover
RESEARCH_CONFIDENCE: HIGH
```

### 2020

#### TP-SE-2020-0001 — 12-year-old killed at petrol station

```text
DATE: 2020-08-02
INCIDENT_LOCATION: Norsborg/Botkyrka
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2020-0001
OUTCOME: killed
AGE: 12
SEX: female
THIRD_PARTY_TYPE: child_bystander
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: none
RELATION_TO_CONFLICT: none personally
WHY_PRESENT: outside with dog / at petrol-station area according to reporting
INJURY_TYPE: gunshot wounds

INTENDED_TARGET: people wearing ballistic vests associated with internal Botkyrka-network drug conflict according to investigation/reporting
MECHANISM: mistaken_or_misdirected_fire at intended gang targets
PERPETRATOR_SIDE: three men later prosecuted; later court history should be synchronized with the main incident record
RESEARCH_CONFIDENCE: HIGH for third-party status
```

YEAR_AGGREGATE_NOTE:
- Study reported by SVT: at least 46 outsiders harmed in 36 gang-related violent incidents during 2011–2020.
- Another SVT review: 12 killed + 19 injured outsiders over the preceding six years.

### 2023

2023 marks a strong increase in third-party victimization through three mechanisms at once: deliberate attacks on non-criminal relatives, mistaken identity/wrong address, and uninvolved people hit in crowded public places.

#### TP-SE-2023-0001 — Gränby mother killed as relative target

```text
DATE: 2023-09-07
INCIDENT_LOCATION: Gränby, Uppsala
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2023-0001
OUTCOME: killed
AGE: 60s
SEX: female
THIRD_PARTY_TYPE: parent_of_target_or_conflict_actor
TARGET_STATUS: deliberately_targeted_relative
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: mother of Foxtrot-linked person on opposing side of internal conflict
RELATION_TO_CONFLICT: non-criminal relative used as conflict target
WHY_PRESENT: at/near home
INJURY_TYPE: gunshot wounds

MECHANISM: relative_targeting
RESEARCH_CONFIDENCE: HIGH
```

#### TP-SE-2023-0002 — Farsta public-square mass shooting

```text
DATE: 2023-06-10
INCIDENT_LOCATION: Farsta centrum, Stockholm
INCIDENT_TYPE: shooting
CONFLICT: prosecutors/court reporting linked attack to Foxtrot-Dalen conflict; intended target not conclusively identified

THIRD_PARTY_PERSON: T-2023-0002A
OUTCOME: killed
AGE: 15
SEX: male
THIRD_PARTY_TYPE: bystander_or_nonparticipant
TARGET_STATUS: unintended
NETWORK: none_known in court reporting
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: not established as intended target
INJURY_TYPE: gunshot wounds

THIRD_PARTY_PERSON: T-2023-0002B
OUTCOME: killed
AGE: 43
SEX: male
THIRD_PARTY_TYPE: bystander
TARGET_STATUS: unintended
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: no clear criminal link in public reporting
INJURY_TYPE: gunshot wounds

THIRD_PARTY_PERSON: T-2023-0002C
OUTCOME: injured
AGE: 60s
SEX: female
THIRD_PARTY_TYPE: passerby
TARGET_STATUS: unintended
WHY_PRESENT: unlocking bicycle after leaving transit/public area
INJURY_TYPE: shot through knee/leg
LONG_TERM_INJURY: not fully coded; source states projectile passed through leg without striking bone, major vessels, nerves or ligaments

THIRD_PARTY_PERSONS: additional injured people
OUTCOME: injured
COUNT: later court reporting states four people were injured in addition to the two killed; individual attributes not yet fully extracted

PERPETRATOR_SIDE:
- P1: male, about 20 at sentencing; convicted
- P2: male, about 20 at sentencing; convicted
- SENTENCE: life imprisonment for two principal perpetrators; court also convicted accomplices
- COURT_FINDING: two murders, multiple attempted murders, danger to others

MECHANISM: indiscriminate_fire_in_crowded_public_space
THIRD_PARTY_ENDANGERED_ESTIMATE: court reporting says roughly 30 people were placed in danger; convictions included 17 attempted murders
RESEARCH_CONFIDENCE: HIGH
```

#### TP-SE-2023-0003 — Västberga family attacked, possible wrong-target mechanism

```text
DATE: 2023-10, exact date retained in main incident record
INCIDENT_LOCATION: Västberga, Stockholm
INCIDENT_TYPE: shooting at home

THIRD_PARTY_PERSON: T-2023-0003A
OUTCOME: killed
AGE: adult
SEX: male
THIRD_PARTY_TYPE: wrong_address_resident_or_wrong_person
TARGET_STATUS: wrong_person_or_wrong_address
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: reporting stated family had no gang connection; possible surname confusion with intended target investigated

THIRD_PARTY_PERSON: T-2023-0003B
OUTCOME: injured
AGE: adult
SEX: female
THIRD_PARTY_TYPE: wrong_address_resident_or_wrong_person
TARGET_STATUS: wrong_person_or_wrong_address
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_OTHER_PERSON: spouse/family relation to T-2023-0003A

MECHANISM: possible mistaken_identity / wrong_address
RESEARCH_CONFIDENCE: MEDIUM-HIGH; motive remains provisional
```

YEAR_AGGREGATE_NOTE:
- Police data reported in January 2024: more than 28 third parties had been killed or injured in 2023 by network-linked shootings or explosions, more than twice the 2022 level.
- Stockholm reporting at year-end said roughly one in three people shot dead in the Stockholm area during 2023 were outsiders, including wrong-target victims and relatives.

### 2024

#### TP-SE-2024-0001 — Flemingsberg man seriously injured because of family relation

```text
DATE: 2024-05-19
INCIDENT_LOCATION: Flemingsberg, Huddinge
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2024-0001
OUTCOME: injured
AGE: 60s
SEX: male
THIRD_PARTY_TYPE: relative_noncriminal
TARGET_STATUS: deliberately_targeted_relative_or_conflict_spillover
NETWORK: none established for victim
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: relative reported to be member of criminal gang
RELATION_TO_CONFLICT: victim himself not reported as gang member
INJURY_TYPE: serious gunshot injury

MECHANISM: relative_targeting
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

#### TP-SE-2024-0002 — Bagarmossen 16-year-old killed after suspected mistaken identity

```text
DATE: 2024-07-09/10 night, exact date per incident source
INCIDENT_LOCATION: Bagarmossen, Stockholm
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2024-0002
OUTCOME: killed
AGE: 16
SEX: male
THIRD_PARTY_TYPE: wrong_person
TARGET_STATUS: wrong_person
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: believed by investigators/source reporting to have been mistaken for another person
RELATION_TO_CONFLICT: no gang connection reported for victim
INJURY_TYPE: fatal gunshot wounds

MECHANISM: mistaken_identity
RESEARCH_CONFIDENCE: MEDIUM-HIGH for wrong-person hypothesis; HIGH for victim age/outcome
```

#### TP-SE-2024-0003 — Akalla mother killed as relative target

```text
DATE: 2024-10-22
INCIDENT_LOCATION: Akalla, Stockholm
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2024-0003
OUTCOME: killed
AGE: 60s
SEX: female
THIRD_PARTY_TYPE: parent_of_target_or_conflict_actor
TARGET_STATUS: deliberately_targeted_relative
NETWORK: none established for victim
NETWORK_STATUS: none_known
RELATION_TO_INTENDED_TARGET: mother of person described as known gang criminal
RELATION_TO_CONFLICT: reporting described existing threat against relative and risk of retaliation
INJURY_TYPE: gunshot wounds

MECHANISM: relative_targeting
RESEARCH_CONFIDENCE: HIGH for family relation/outcome; exact motive chain should remain source-qualified
```

#### TP-SE-2024-0004 — Malmö father killed in suspected wrong-person contract shooting

```text
DATE: autumn 2024, exact incident date pending main-record reconciliation
INCIDENT_LOCATION: Malmö, home/residential setting
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSON: T-2024-0004
OUTCOME: killed
AGE: adult / exact age not yet extracted
SEX: male
THIRD_PARTY_TYPE: wrong_person
TARGET_STATUS: wrong_person
NETWORK: none_known
NETWORK_STATUS: none_known
RELATION_TO_CONFLICT: no criminal connection reported for victim
WHY_PRESENT: in own home; went to investigate broken patio/window area according to later court reporting
INJURY_TYPE: fatal gunshot wounds

PERPETRATOR_SIDE:
- alleged shooter: boy aged 17 at trial reporting
- alleged assignment: prosecutors said shooter had been recruited for a murder mission for Foxtrot
- LEGAL_STATUS: trial ongoing at cited 2025 reporting stage; do not code as convicted without later source

MECHANISM: mistaken_identity / outsourced_contract_attack
RESEARCH_CONFIDENCE: HIGH for victim being non-criminal and prosecution's wrong-person theory; final perpetrator status pending
```

### 2025

Police full-year assessment reported:

```text
THIRD_PARTY_KILLED: 3
THIRD_PARTY_INJURED: 15
TOTAL: 18
MOST_COMMON_MECHANISM: happened to be present at attack location
MINORITY_MECHANISM: wrong person selected
```

The same police series gave a cumulative total since the start of 2023 of 24 killed and 48 injured outsiders by the end of 2025.

#### TP-SE-2025-0001 — Gävle public shooting cluster, six outsiders injured

```text
DATE: 2025, autumn according to retrospective police/SR summary
INCIDENT_LOCATION: Gävle
INCIDENT_TYPE: shooting

THIRD_PARTY_PERSONS: T-2025-0001A through T-2025-0001F
OUTCOME: injured
COUNT: 6
AGE: not yet individually extracted
SEX: not yet individually extracted
THIRD_PARTY_TYPE: bystanders/present-at-scene
TARGET_STATUS: unintended
NETWORK: none_known for the six outsiders in police summary
WHY_PRESENT: public street/area
INJURY_TYPE: mixed; at least one person shot in leg

MECHANISM: public-space attack with outsider spillover
RESEARCH_CONFIDENCE: MEDIUM-HIGH pending individual incident-source extraction
```

## Relationship fields required for every third party

The future database should support explicit edges such as:

```text
T -> spouse_of -> PERSON
T -> parent_of -> PERSON
T -> child_of -> PERSON
T -> sibling_of -> PERSON
T -> neighbor_of -> PERSON
T -> customer_at -> LOCATION
T -> employee_at -> LOCATION
T -> witness_to -> INCIDENT
T -> resident_at -> LOCATION
T -> mistaken_for -> PERSON
T -> harmed_in -> INCIDENT
T -> killed_in -> INCIDENT
T -> injured_in -> INCIDENT
INCIDENT -> intended_target -> PERSON
INCIDENT -> wrong_address_for -> PERSON
INCIDENT -> retaliation_for -> INCIDENT
```

A person may have more than one relation. Example:

```text
T-2019-0002 -> spouse_of -> intended target
T-2019-0002 -> resident_at -> attacked home
T-2019-0002 -> killed_in -> Råcksta incident
```

## Required data-quality distinction

Never infer `innocent` from `not convicted` and never infer `gang member` from proximity to a target. Use only evidence-based categories:

```text
none_known
unknown
alleged_associate
associate
member
leader
```

For third-party classification, the relevant question is narrower:

> Was this person participating in the active criminal conflict that generated the attack?

Someone can have a prior conviction or social relationship to a criminal actor and still be a third party to a particular conflict if the evidence supports that classification.

## Third-party coverage tracker

```text
2011: incomplete
2012: partial — one high-confidence wrong-person death coded
2013: partial — one severe outsider injury coded; broader early-study cases not individually extracted
2014: incomplete
2015: partial — restaurant bystander death, child blast death, two women at Hässelby, child+adult Husby injuries coded
2016: partial — child grenade death coded
2017: incomplete — main incident catalogue contains potential third-party cases that still need classification
2018: partial — Segeltorp wrong-person killing and Vårby grenade death/injury coded
2019: partial — Malmö mother, Råcksta wife, Nacka taxi driver/student coded
2020: partial — 12-year-old Botkyrka victim coded; aggregate 2011–2020 baseline recorded
2021: incomplete
2022: incomplete — police comparison exists but individual people not yet reconstructed
2023: partial — Gränby, Farsta, Västberga and aggregate police figures coded
2024: partial — Flemingsberg, Bagarmossen, Akalla, Malmö wrong-person case coded
2025: partial — official 3 killed/15 injured baseline plus Gävle six-injury cluster seed record
2026: incomplete/provisional
```

## Source register

- SVT, 2020, `Ny studie visar: Ökning av utomstående personer som drabbas av gängvåld`: https://www.svt.se/nyheter/inrikes/ny-studie-visar-okning-av-utomstaende-personer-som-drabbas-av-gangvald
- SVT, 2020/2021, `Allt fler utomstående drabbas av gängkonflikter`: https://www.svt.se/nyheter/inrikes/allt-fler-utomstaende-dodas-i-gangkrigen
- SVT, 2020, `Sex uppmärksammade fall med kopplingar till gängkonflikter`: https://www.svt.se/nyheter/inrikes/andra-uppmarksammade-fall-med-kopplingar-till-gangkonflikter
- SVT, 2015, `Extremt våldsamma månader`: https://www.svt.se/nyheter/lokalt/stockholm/extremt-valdsamma-manader-1
- SVT, 2017, report referencing outsider paralyzed in Tensta grill shooting: https://www.svt.se/nyheter/lokalt/stockholm/kallor-till-svt-dubbelmordet-gangrelaterat
- SVT, 2019, `Det vet vi om mordet på Ndella Jack`: https://www.svt.se/nyheter/lokalt/stockholm/det-vet-vi-om-mordet-pa-ndella-jack
- SVT, 2020, `Musikstudenten Sammy sköts i ögat – var inte måltavla`: https://www.svt.se/nyheter/lokalt/stockholm/musikstudent-oskyldigt-offer-i-kriminell-uppgorelse
- SVT, 2020, `Uppgifter: Gängkonflikt bakom dödsskjutningen – flickan sköts av misstag`: https://www.svt.se/nyheter/lokalt/stockholm/uppgifter-gangkonflikten-bakom-mordet
- Sveriges Radio, 2023, `Mamman: Kulor från gängkriminella dödade Adriana`: https://www.sverigesradio.se/artikel/mamman-kulor-fran-gangkriminella-dodade-adriana
- Sveriges Radio, 2024, `Fler utomstående drabbas av gängvåld`: https://www.sverigesradio.se/artikel/fler-utomstaende-drabbas-av-gangvald
- Sveriges Radio, 2025, `60 utomstående har dödats eller skadats av gängens våld`: https://www.sverigesradio.se/artikel/60-utomstaende-har-dodats-eller-skadats-av-gangens-vald
- Sveriges Radio, 2026 reporting on 2025 totals, `18 utomstående dödade eller skadade av gängvåld 2025`: https://www.sverigesradio.se/artikel/polisen-18-utomstaende-dodade-eller-skadade-av-gangvald-2025
- Sveriges Radio, 2025, suspected wrong-person Malmö killing/trial: https://www.sverigesradio.se/artikel/smabarnspappa-skots-ihjal-av-misstag-nu-avslutas-rattegangen
- SVT, 2024, Bagarmossen wrong-person hypothesis: https://www.svt.se/nyheter/lokalt/stockholm/uppgifter-till-svt-16-aringen-var-inte-tilltankt-maltavla
- SVT, 2024, Akalla mother killed: https://www.svt.se/nyheter/lokalt/stockholm/grovt-brott-inomhus-i-akalla-polisinsats-pagar
- SVT/Diamant Salihu, 2024, Flemingsberg relative victim: https://www.svt.se/nyheter/lokalt/stockholm/diamant-salihu-om-senaste-tidens-skjutningar-risk-att-det-kan-eskalera-annu-mer
- Aftonbladet, 2023 Farsta immediate victim details: https://www.aftonbladet.se/nyheter/a/pQmxoX/skottlossning-i-farsta-familjen-hamnade-mitt-i-skjutningen
- Aftonbladet, 2024 Farsta court outcome: https://www.aftonbladet.se/nyheter/a/PpRWrz/nu-faller-domen-efter-skjutningen-pa-farsta-torg

## Research queue specifically for third parties

```text
1. Reconstruct every one of the 46 known 2011–2020 outsiders from the underlying 36 incidents where open sources allow it.
2. Resolve the 12 killed + 19 injured six-year SVT review into person IDs and incident IDs.
3. Build 2021 and 2022 individual records, currently the largest gap before the 2023 police series.
4. Reconcile every 2023 outsider against the police >28 count and classify mechanism.
5. Reconcile 2024 + 2025 records against cumulative police totals: 24 killed + 48 injured since 2023 by end-2025.
6. Add injury severity and long-term impairment when publicly reported.
7. Add explicit family/household relations without storing names.
8. Record uninjured but directly targeted third parties separately from physically injured victims.
9. Add people endangered in public-space attacks only where a court or authoritative source provides a defensible count.
10. Keep 2026 provisional and update legal outcomes as cases mature.
```
