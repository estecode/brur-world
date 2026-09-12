# BRUR Gang-Violence Research — Extended Media Source Supplement

Status: v0.1 — companion evidence file
Coverage pass: Aftonbladet, Expressen leads, BBC, CNN and Flashback
Last research update: 2026-09-12

## Purpose

This companion file records additions and source leads discovered by broadening the incident research beyond the official/SVT/SR/Brå core used in `gang_violence_incident_research.md`.

The same anonymization and evidence rules apply. Real personal names are not retained. Flashback is used only to discover candidate incidents or source links; claims from forum users are never accepted as factual evidence without independent corroboration.

## Source-quality policy for this pass

```text
Aftonbladet / Expressen:
  usable for incident detail, chronology, age, locality and contemporaneous police/source statements;
  allegations retain allegation status.

BBC / CNN:
  useful mainly for internationally covered Swedish events and exclusion/control checks;
  not expected to be comprehensive at person level.

Flashback:
  lead_generator_only;
  never sole evidence;
  forum speculation about identity, ethnicity, motive, affiliation or guilt is discarded;
  linked police/public-service reporting may be followed and independently verified.
```

## High-value aggregate finding from Aftonbladet

Aftonbladet published a 2018 review of fatal shootings in Stockholm, Göteborg and Malmö since 2011. It reported:

```text
PERIOD: 2011 through January 2018 review date
GEOGRAPHY: Stockholm + Göteborg + Malmö
FATAL_SHOOTING_VICTIMS_IN_REVIEW: 131
FATAL_SHOOTINGS_ON_PUBLIC_PLACES: at least 100 of 131
CONTEXT: review framed the set as deaths in gang conflicts / gang-war shootings
```

This is a valuable reconciliation benchmark for the pre-national police-series years. It is not yet an incident-by-incident import, but it gives a check against undercounting the 2011–2017 catalogue.

SOURCE:
- Aftonbladet, 2018-01-25, `Statistiken avslöjar: Gängskjutningar vanligast på allmänna platser`
  https://www.aftonbladet.se/nyheter/a/L01V7Q/statistiken-avslojar-gangskjutningar-vanligast-pa-allmanna-platser

## Newly strengthened / added early-period incidents

### SE-2011-SUP-0001 — central Göteborg killing of gang leader

```text
DATE: 2011-04-30
LOCATION: Vasastaden / central Göteborg
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
SUMMARY: Retrospective SVT reporting identifies a man described as having been a leading figure in a gang as shot dead on a street in central Göteborg.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: unknown in current corroborated source
  SEX: male
  TARGET_STATUS: intended
  NETWORK: unknown label
  NETWORK_STATUS: leader

RESEARCH_CONFIDENCE: MEDIUM-HIGH
NOTES: Aftonbladet later referenced a 2011 execution-style killing on Erik Dahlbergsgatan involving a 42-year-old recently released from prison; exact identity linkage to this retrospective SVT item should be reconciled before merging age into the stable record.
```

SOURCES:
- SVT retrospective Göteborg fatal-shooting fact box: https://www.svt.se/nyheter/lokalt/vast/skjutne-mannen-arbetade-pa-skolan
- Aftonbladet retrospective mention in 2016 shooting report: https://www.aftonbladet.se/nyheter/a/yvGmaa/man-skjuten-med-flera-skott-i-centrala-goteborg

### SE-2012-SUP-0001 — Önskevädersgatan killing, exact date strengthened

```text
DATE: 2012-07-05
LOCATION: Önskevädersgatan, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: Biskopsgården criminal-network conflict
SUMMARY: A 23-year-old man was shot dead. Later SVT reporting states he had survived earlier murder attempts and lived with protected identity. A person later described as leading in southern Biskopsgården was detained on suspicion of the murder, but no one was convicted.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 23
  SEX: male
  TARGET_STATUS: intended
  NETWORK: Biskopsgården conflict, exact side not assigned here
  NETWORK_STATUS: unknown
  PREVIOUS_INCIDENT_LINKS: survived earlier attempted killings, details not yet coded

SUSPECTS/PERPETRATORS:
- PERSON: P1
  NETWORK: southern Biskopsgården grouping
  NETWORK_STATUS: leader-level description in later reporting
  LEGAL_STATUS: historically suspected/detained; no conviction for this killing

RESEARCH_CONFIDENCE: HIGH for incident/date; MEDIUM for network-role description
```

SOURCE:
- SVT, 2025 retrospective, `Gängkriget i Biskopsgården inifrån: Finns inga bröder`
  https://www.svt.se/nyheter/lokalt/vast/gangkriget-i-biskopsgarden-inifran-finns-inga-broder

### SE-2012-SUP-0002 — Kantatgatan wrong-person execution

```text
DATE: 2012-01-03
LOCATION: Kantatgatan, Malmö
MUNICIPALITY: Malmö
REGION: Syd
INCIDENT_TYPE: shooting
SUMMARY: A 48-year-old man was shot six times at close range in daylight and died at the scene. Prosecutors later argued that he was killed by mistake after being confused with a neighbor involved in serious crime. The shooter was convicted; the appeal court increased the prison term to 16 years.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 48
  SEX: male
  TARGET_STATUS: wrong_person
  NETWORK: none established for victim
  NETWORK_STATUS: none_known
  RELATION_TO_CONFLICT: prosecutor said intended target was a criminal neighbor

SUSPECTS/PERPETRATORS:
- PERSON: P1
  AGE: 29 at appeal-report date
  SEX: male
  ROLE: shooter
  LEGAL_STATUS: convicted
  SENTENCE: 16 years imprisonment after appeal

EVENT:
  METHOD: handgun/firearm, six shots
  SETTING: public street in daytime
  TARGET_TYPE: mistaken identity
  BYSTANDERS_PRESENT: public setting

RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- Sveriges Radio, 2012-11-27, `Fel man mördades på Kantatgatan`
  https://www.sverigesradio.se/artikel/5360952
- Sveriges Radio, 2013-05-06, `Åklagaren nöjd med skärpt straff för mordet på Kantatgatan`
  https://www.sverigesradio.se/artikel/5525795
- Aftonbladet, 2012-01-03, contemporary Malmö violence context
  https://www.aftonbladet.se/nyheter/a/QljgBR/straffen-maste-hojas

### SE-2013-SUP-0001 — Biskopsgården shooting + stabbed witness

```text
DATE: 2013-06-13
LOCATION: Köldgatan, Södra Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting + assault
CONFLICT: network relation not established in corroborated source
SUMMARY: A man in his twenties was shot in the foot in or near a stairwell. Another man, described as a witness, was stabbed in the arm and sustained superficial injuries. Police believed four masked perpetrators were involved. No arrest had been made at the reporting time.

VICTIMS:
- PERSON: V1
  OUTCOME: injured
  AGE: 20s
  SEX: male
  TARGET_STATUS: intended_or_unknown
  NETWORK_STATUS: unknown
- PERSON: V2
  OUTCOME: injured
  AGE: unknown
  SEX: male
  TARGET_STATUS: witness
  NETWORK_STATUS: unknown
  RELATION_TO_CONFLICT: witness to same event

SUSPECTS/PERPETRATORS:
- PERSONS: P1-P4
  ROLE: suspected masked perpetrators
  LEGAL_STATUS: unknown/not arrested at source time

RESEARCH_CONFIDENCE: HIGH for injuries/event; UNKNOWN for gang motive
NOTES: Discovered through Flashback thread linking contemporary GP/Expressen/police reporting, then independently corroborated through Sveriges Radio. Forum speculation about motive was discarded.
```

SOURCE:
- Sveriges Radio, 2013-06-13, `Man skjuten i foten i Biskopsgården`
  https://www.sverigesradio.se/artikel/5564318

FLASHBACK_LEAD_ONLY:
- https://www.flashback.org/t2161759

### SE-2013-SUP-0002 — Väderilsgatan double murder, exact date and method strengthened

```text
DATE: 2013-09-04
LOCATION: Biskopsgården, Göteborg
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: retaliatory conflict between two groups according to police/UG reporting
SUMMARY: One or more attackers fired at least 40 rounds with an automatic weapon toward a group on a walkway. A 17-year-old boy was shot in the head and a 28-year-old man in the abdomen; both died. The event was part of the September escalation in Göteborg and police suspected revenge shootings between two groups.

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

EVENT:
  METHOD: automatic firearm; at least 40 shots reported
  SETTING: outdoor walkway / residential area
  RETALIATION: suspected by police in wider conflict
  BYSTANDERS_PRESENT: group of people present

RESEARCH_CONFIDENCE: HIGH
NOTES: Flashback chronology correctly pointed to 2013-09-04, but the stable facts are taken from SVT/SR corroboration.
```

SOURCES:
- SVT/UG, `Våldsamt år i Göteborg`
  https://www.svt.se/nyheter/granskning/ug/valdsamt-ar-i-goteborg
- Sveriges Radio, 2013-09-04/05, `Två män skjutna till döds i Göteborg`
  https://www.sverigesradio.se/artikel/5636734

FLASHBACK_LEAD_ONLY:
- https://www.flashback.org/p45784682

### SE-2013-SUP-0003 — Friskväderstorget inter-gang gunfight

```text
DATE: 2013-10-17
LOCATION: Friskväderstorget, Biskopsgården
MUNICIPALITY: Göteborg
REGION: Väst
INCIDENT_TYPE: shooting
CONFLICT: members of different gangs exchanging fire
SUMMARY: An 18-year-old man was shot and seriously injured during gunfire between two groups on a public square. Six others were detained/remanded. The injured man was later remanded on probable cause for attempted murder and aggravated weapons offence in relation to the same event.

VICTIMS/PARTICIPANTS:
- PERSON: V1/P1
  OUTCOME: injured
  AGE: 18
  SEX: male
  TARGET_STATUS: participant_and_victim
  NETWORK_STATUS: gang participant, exact network label not coded
  LEGAL_STATUS: later remanded on probable cause for attempted murder and aggravated weapons offence

EVENT:
  SETTING: public square among members of public
  METHOD: firearms exchanged between two groups
  BYSTANDERS_PRESENT: yes

RESEARCH_CONFIDENCE: HIGH
NOTES: This is a useful victim/perpetrator-overlap example and should eventually support a many-to-many role model rather than forcing each person into only one incident role.
```

SOURCES:
- SVT, 2013-10-17, `Sex anhållna efter skott`
  https://www.svt.se/nyheter/lokalt/vast/ny-skottlossning-i-goteborg-3
- Sveriges Radio, 2013-10-29, `Skjuten i Biskopsgården omhäktad`
  https://www.sverigesradio.se/artikel/5688903

### Göteborg 2011–2015 regional baseline strengthened

Aftonbladet/TT reported the following Göteborg shooting counts based on police information:

```text
2011: 48 shootings
2012: 46 shootings
2013: 56 shootings; 8 dead; 31 injured
2014: 50 shootings; 4 dead; 20 injured
2015 through 2015-08-12: 13 shootings; 5 dead; 16 injured
```

This strengthens the pre-2017 comparison layer but remains all qualifying shootings in that local police accounting, not automatically confirmed gang incidents person-by-person.

SOURCE:
- Aftonbladet/TT, `Färre skjutningar i Göteborg`
  https://www.aftonbladet.se/senastenytt/ttnyheter/inrikes/a/6nVVGr/farre-skjutningar-i-goteborg

## 2023 family-targeting additions

### SE-2023-SUP-0001 — Gränby mother killed in Foxtrot retaliation

```text
DATE: 2023-09-07
LOCATION: Gränby, Uppsala
MUNICIPALITY: Uppsala
REGION: Mitt
INCIDENT_TYPE: shooting
CONFLICT: internal Foxtrot conflict
SUMMARY: A woman in her sixties was shot dead. Multiple public-service reports state she was the mother of a person linked to Foxtrot who had turned against the network leader; reporting linked the killing to retaliation following a shooting in Istanbul.

VICTIMS:
- PERSON: V1
  OUTCOME: killed
  AGE: 60s
  SEX: female
  TARGET_STATUS: relative
  NETWORK: none established for victim
  NETWORK_STATUS: none_known
  RELATION_TO_CONFLICT: mother of a Foxtrot-linked person on opposing side of internal conflict

SUSPECTS/PERPETRATORS:
- PERSON: P1
  AGE: teenager
  LEGAL_STATUS: remanded/suspected at cited reporting stage
- PERSON: P2
  AGE: teenager
  LEGAL_STATUS: remanded/suspected at cited reporting stage

SUSPECTED_MOTIVE: retaliation connected to Foxtrot internal conflict and Istanbul shooting
RESEARCH_CONFIDENCE: HIGH for victim/relative status; later final court status still needs follow-up
```

SOURCES:
- SVT, 2023-09-10/12, `Tonåringar häktade för gängrelaterat mord på kvinna i Uppsala`
  https://www.svt.se/nyheter/lokalt/uppsala/tva-haktas-misstankta-for-mordet-i-granby--x4i24o
- Sveriges Radio, 2023-09-13, `Våldsbrott i Uppsala kopplas till gäng-konflikter i Turkiet`
  https://www.sverigesradio.se/artikel/valdsbrott-i-uppsala-kopplas-till-gang-konflikter-i-turkiet

### SE-2023-SUP-0002 — Stenhagen wrong-address shooting at relative target

```text
DATE: 2023-09-09
LOCATION: Stenhagen, Uppsala
MUNICIPALITY: Uppsala
REGION: Mitt
INCIDENT_TYPE: shooting
CONFLICT: Foxtrot internal conflict
SUMMARY: Shots were fired at an apartment. Reporting said the attack was intended for a relative of the Foxtrot leader but was believed to have been directed at the wrong residence.

TARGET_STATUS: wrong_address + intended relative target
RELATIVE_TARGETING: yes
OUTCOME: no death/injury established in current source excerpt
RESEARCH_CONFIDENCE: MEDIUM-HIGH
```

SOURCE:
- SVT, 2023-09-10/12
  https://www.svt.se/nyheter/lokalt/uppsala/tva-haktas-misstankta-for-mordet-i-granby--x4i24o

### 2023 Uppsala conflict cluster

SVT summarized that three people died in Uppsala through two shootings and one explosion during a suspected revenge spiral centered on the Foxtrot conflict. This supports grouping individual records under a conflict-cluster ID while retaining individual incidents separately.

SOURCE:
- SVT, `Senaste våldsdåden i Uppsala`
  https://www.svt.se/nyheter/lokalt/uppsala/dodsskjutningarna-i-uppsala--cz2aaf

## BBC/CNN control findings

### Campus Risbergska / Örebro 2025 — explicit exclusion from gang dataset

CNN reporting after the February 2025 school shooting quoted police as ruling out gang violence as a motive. BBC reporting likewise covered the event as Sweden's deadliest school shooting, not as a network-conflict event.

```text
EVENT: Campus Risbergska school shooting, Örebro
DATE: 2025-02-04
DATASET_STATUS: EXCLUDE_FROM_GANG_NETWORK_INCIDENT_COUNT
REASON: police explicitly ruled out gang violence in contemporaneous reporting
IMPORTANCE: prevents contamination of 2025 official shooting/death totals when estimating gang/network violence
```

SOURCES:
- CNN transcript, 2025-02-06: https://transcripts.cnn.com/show/cnr/date/2025-02-06/segment/21
- BBC News coverage, 2025-02-05/06 (search-indexed video/reporting)

### International coverage limitation

BBC/CNN searches produced useful context on Sweden's gang-violence trend but few person-level historical incident details beyond internationally prominent events. They should therefore remain secondary control/context sources rather than primary enumeration sources for the 2011–2026 catalogue.

## Flashback lead audit

The Flashback pass was useful mainly because old forum threads preserve links and dates for contemporary media/police reports that are otherwise difficult to search.

Useful independently corroborated leads from this pass:

```text
2013-06-13 Köldgatan, Biskopsgården:
  forum lead -> independently verified via Sveriges Radio
  result: one man shot in foot, witness stabbed in arm

2013-09-04 Biskopsgården double killing:
  forum chronology -> independently verified via SVT/UG and Sveriges Radio
  result: ages 17 and 28, at least 40 shots, both killed

2013-10-17 Friskväderstorget:
  forum lead -> independently verified via SVT/Sveriges Radio
  result: 18-year-old shot, later remanded as participant in inter-gang gunfight
```

Discarded from factual dataset:

- guesses about specific gang identities without corroboration;
- ethnic descriptions/speculation;
- usernames' claims about motive or personal identity;
- unsourced percentages such as claims that a given share of attacks targeted one faction;
- rumors about who ordered or carried out an attack.

## Research implications from this source pass

1. The pre-2017 dataset is still undercounted if it relies only on the current stable incident file. Aftonbladet's 131-death three-city review is a strong reconciliation target.
2. `wrong_person` is required as a distinct target type: the 2012 Kantatgatan case has a court-supported mistaken-identity theory and a convicted shooter.
3. One person may simultaneously be `injured victim` and `suspected participant/perpetrator` in the same incident, as the 2013 Friskväderstorget case demonstrates. The eventual database should therefore model roles many-to-many rather than one fixed role per person/event.
4. `relative` and `wrong_address` can coexist. The September 2023 Stenhagen attack was reportedly aimed at a relative but at the wrong dwelling.
5. International reporting is valuable for exclusions. The 2025 Örebro mass shooting must not inflate gang/network counts despite appearing in national firearm-death totals.
6. Flashback is most valuable as an archive index, not as evidence.

## Next source-pass targets

```text
- Use Aftonbladet's 2018 three-city review to reconstruct/link as many of the 131 fatal cases as possible.
- Continue Expressen/GT archive searches for missing Göteborg/Malmö injury records and later court outcomes.
- Use Flashback only to recover dead links/dates, then verify elsewhere.
- Search BBC/CNN only for internationally prominent incidents or exclusion/context checks.
- Promote records from this supplement into the main incident catalogue only after their stable IDs and source evidence are reconciled against existing entries.
```
