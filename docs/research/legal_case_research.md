# BRUR Legal Case Research

Status: v0.1 — structured legal-proceeding companion
Coverage target: legal outcomes connected to incidents/persons in the BRUR gang/network violence research corpus
Last research update: 2026-09-12

## Purpose

This file records what happened in the justice system after an incident: prosecution, court, case number, instance, judgment date, offences, conviction/acquittal, sentence, damages, appeal and final known status.

It is intentionally separate from the incident and police-response layers so the later database can model one incident as producing several investigations, prosecutions, defendants and court decisions across multiple instances.

## Legal evidence rules

Prefer in this order:

1. Sveriges Domstolar / published judgments and official court press releases.
2. Åklagarmyndigheten and other primary justice-system material.
3. Government reports that identify case numbers and procedural history.
4. Established journalism when primary material is unavailable.

Never infer guilt from arrest, detention or charge. Record each procedural stage independently. A later appeal decision never silently overwrites the lower-court judgment; both are retained.

## Court-decision record

```text
LEGAL_CASE_ID:
INCIDENT_IDS:
PERSON_IDS:
PROSECUTION_AUTHORITY:
PROSECUTION_CASE_ID:

DECISIONS:
- INSTANCE: district_court | court_of_appeal | supreme_court
  COURT:
  CASE_NUMBER:
  DECISION_DATE:
  DECISION_TYPE: judgment | detention | procedural | leave_to_appeal
  OFFENCES:
  OUTCOME: convicted | acquitted | partly_convicted | dismissed | remanded | other
  SENTENCE:
  DAMAGES:
  DEPORTATION:
  NOTES:

APPEAL_CHAIN:
FINAL_KNOWN_STATUS:
FINALITY: final | appealed | leave_denied | unknown
SOURCES:
RESEARCH_CONFIDENCE:
```

## Verified legal records

### LEGAL-SE-2012-KANTATGATAN — wrong-person murder, Malmö

Linked incident: `SE-2012-SUP-0002`

```text
VICTIM: anonymized V1, 48, killed after being mistaken for another person
DEFENDANT: anonymized P1

DECISIONS:
- INSTANCE: district_court
  COURT: Malmö tingsrätt
  CASE_NUMBER: public case number not yet verified in current source set
  DECISION_DATE: 2012/2013, exact date pending primary judgment
  OFFENCES: murder; weapons-related offences reported
  OUTCOME: convicted
  SENTENCE: lower-court sentence later increased on appeal

- INSTANCE: court_of_appeal
  COURT: Hovrätten över Skåne och Blekinge
  CASE_NUMBER: pending primary-source verification
  DECISION_DATE: 2013-05-06 or earlier judgment date; article date is not automatically judgment date
  OFFENCES: murder and related offences
  OUTCOME: convicted
  SENTENCE: 16 years imprisonment

FINAL_KNOWN_STATUS: conviction, 16 years in the court of appeal
FINALITY: not yet checked against Supreme Court leave records
RESEARCH_CONFIDENCE: HIGH for conviction/sentence; MEDIUM for procedural metadata pending primary judgment
```

Sources: Sveriges Radio reports on the mistaken target and the increased sentence in the court of appeal.

### LEGAL-SE-2015-VARKROG — Vår krog och bar / Vårväderstorget

Linked incident: `SE-2015-0001`

```text
PROSECUTION_AUTHORITY: Åklagarmyndigheten
PROSECUTION_CASE_ID: AM-114704-14

DECISIONS:
- INSTANCE: district_court
  COURT: Göteborgs tingsrätt
  CASE_NUMBER: B 10647-14
  DECISION_DATE: 2016
  DEFENDANTS: 8
  OFFENCES: murder/attempted murder or participation in the attack; several defendants also faced serious drug/weapons charges
  OUTCOME: 8 convicted at first instance in the principal case according to contemporary procedural material
  NOTES: approximately 25 trial days; 24 injured parties and 33 witnesses heard; investigation exceeded 13,000 pages

- INSTANCE: court_of_appeal
  COURT: Hovrätten för Västra Sverige
  CASE_NUMBER: B 3777-16
  DECISION_DATE: 2016-12-22
  OUTCOME: 7 of 8 defendants convicted in relation to the attack
  LEGAL_CHARACTERISATION: the court of appeal primarily treated the convicted defendants as aiders/abettors because the evidence did not establish which convicted individuals had actually fired the weapons
  SENTENCE: two life sentences remained among the outcomes; other long custodial sentences also imposed

- INSTANCE: supreme_court
  COURT: Högsta domstolen
  DECISION_DATE: 2017-03-30 reporting date
  DECISION_TYPE: leave_to_appeal
  OUTCOME: leave to appeal denied / court-of-appeal judgments remained in force

FINAL_KNOWN_STATUS: court-of-appeal convictions remained after Supreme Court declined review
FINALITY: final
RESEARCH_CONFIDENCE: HIGH
```

Primary procedural source: SOU 2017:7 identifies prosecution case AM-114704-14, Göteborgs tingsrätt B 10647-14 and Hovrätten för Västra Sverige B 3777-16. Later reporting records the seven-of-eight appeal outcome and denied Supreme Court review.

### LEGAL-SE-2020-NORSBORG-12YO — murder of 12-year-old outsider

Linked third-party record: 12-year-old girl killed at a Norsborg rest area in August 2020.

```text
DECISIONS:
- INSTANCE: district_court
  COURT: Södertörns tingsrätt
  DECISION_DATE: 2023-04
  DEFENDANTS_FOR_MURDER: 3
  OFFENCES: murder; attempted murder of other people at the rest area; additional offences
  OUTCOME: convicted
  SENTENCE: life imprisonment for all three at first instance
  OTHER_DEFENDANTS: two additional men convicted of aggravated weapons offence and protecting an offender respectively

- INSTANCE: court_of_appeal
  COURT: Svea hovrätt
  CASE_NUMBER: B 5894-23
  DECISION_DATE: 2023-12-22
  OUTCOME: two defendants convicted of murder/attempted murder with life sentences affirmed; third defendant acquitted of murder/attempted murder but convicted of other offences including preparation to murder
  SENTENCE_THIRD_DEFENDANT: 9 years 8 months
  DAMAGES: increased damages to the killed girl's mother for the two murder-convicted defendants
  OTHER_DEFENDANTS: convictions affirmed with shorter custodial sentences

FINAL_KNOWN_STATUS: appeal judgment known; Supreme Court status still to be attached if relevant
FINALITY: unknown pending leave-to-appeal reconciliation
RESEARCH_CONFIDENCE: HIGH
```

Primary source: Svea hovrätt, case B 5894-23, published 2023-12-22.

### LEGAL-SE-2020-VARBY — Vårby network / kidnapping of artist

Linked research: Vårby network case; artist kidnapping and planned earlier abduction.

```text
DECISIONS:
- INSTANCE: district_court
  COURT: Södertörns tingsrätt
  DECISION_DATE: 2021-07-14
  DEFENDANTS: approximately 30 prosecuted; 27 convicted at first instance
  OFFENCES: attempted murder, kidnapping, aggravated weapons offences, serious narcotics offences, explosives-related offences and other organized crime
  TOTAL_SENTENCES: 147 years imprisonment reported at first instance
  NETWORK_LEADER_SENTENCE: 17 years 10 months
  ARTIST_A: convicted of preparation to kidnapping; 10 months imprisonment
  ARTIST_B: convicted of aiding kidnapping and robbery; 2 years 6 months imprisonment

- INSTANCE: court_of_appeal
  COURT: Svea hovrätt
  CASE_NUMBERS: B 9407-21 and B 3900-21 reported for the appeal complex
  DECISION_DATE: 2022-02-18
  OUTCOME: convictions largely affirmed; several sentences adjusted; convictions of the two artists for the kidnapping-related offences were affirmed
  NETWORK_LEADER_SENTENCE: 17 years 10 months remained

FINAL_KNOWN_STATUS: court-of-appeal judgment controls for the appealed counts; later Supreme Court status must be stored per defendant/count if found
FINALITY: partially reconciled
RESEARCH_CONFIDENCE: HIGH for district/appeal outcomes; MEDIUM for mapping every defendant/count to the two appeal case numbers
```

Sources: Södertörns tingsrätt/Svea hovrätt as summarized by SVT; Svea hovrätt appeal case numbers from published judgment references.

### LEGAL-SE-2023-FARSTA — Farsta torg double murder and mass attempted murder

Linked incident: Farsta torg shooting, 2023-06-10.

```text
DECISIONS:
- INSTANCE: district_court
  COURT: Södertörns tingsrätt
  CASE_NUMBER: B 8993-23
  DECISION_DATE: 2024-06-03
  DEFENDANTS: 4
  OFFENCES: two murders; 17 attempted murders; causing danger to another; aiding/abetting counts; related offences
  OUTCOME: all four received long custodial sentences
  SENTENCE: shooter and driver convicted of two murders and 17 attempted murders; principal sentences included life imprisonment; one defendant also ordered permanently deported
  DAMAGES: damages awarded to injured parties
  FINDING: court found that the attack was carried out on assignment from persons connected to criminal networks and was aimed at rival-gang members

- INSTANCE: court_of_appeal
  COURT: Svea hovrätt
  CASE_NUMBER: B 8536-24
  DECISION_DATE: 2024-09-19
  OUTCOME: life sentences for the two principal perpetrators affirmed; two other defendants convicted on additional aiding counts compared with the district court
  SENTENCE: one of the assisting defendants received an increased sentence; published secondary summaries report 15 years 10 months for each of the two assisting defendants
  DAMAGES: court of appeal increased non-pecuniary damages beyond standard levels for victims of attempted murder / causing danger to another

FINAL_KNOWN_STATUS: Svea hovrätt judgment
FINALITY: Supreme Court leave status pending explicit verification
RESEARCH_CONFIDENCE: HIGH
```

Primary/official reference: Svea hovrätt case B 8536-24; district-court case B 8993-23.

## Required expansion

Every stable incident in the research corpus should eventually have one of:

```text
LEGAL_CASE_ID: <linked record>
```

or

```text
LEGAL_CASE_STATUS: no_public_prosecution_found | unsolved | investigation_ongoing | no_charge | public_data_not_found
```

For each charged person, store the full procedural chain:

```text
suspected
-> detained/remanded
-> charged
-> district-court judgment
-> appeal
-> court-of-appeal judgment
-> Supreme Court leave/decision if any
-> finality
```

Do not flatten a mixed judgment into `convicted` when a person was convicted on some counts and acquitted on others. The later database should model `PERSON x COUNT x DECISION` where possible.

## Database conversion notes

Recommended entities:

```text
legal_case
court_decision
charge_count
person_decision
appeal
sentence
civil_damages
```

Key relationships:

```text
INCIDENT -> investigated_in -> LEGAL_CASE
PERSON -> charged_in -> LEGAL_CASE
LEGAL_CASE -> decided_by -> COURT_DECISION
COURT_DECISION -> appealed_to -> COURT_DECISION
PERSON -> convicted_on_count -> CHARGE_COUNT
PERSON -> acquitted_on_count -> CHARGE_COUNT
```

This structure preserves changes between instances instead of overwriting history.

## Research backlog

Priority:

1. attach district-court and appellate case numbers to every currently coded homicide/shooting where prosecution occurred;
2. add exact judgment dates and finality/leave-to-appeal status;
3. map each anonymized defendant to offence counts and sentence without storing unnecessary real names;
4. add damages, deportation and youth-care orders where relevant;
5. distinguish unsolved/no-charge cases from cases where legal data is merely not yet retrieved;
6. cross-link legal records to police-response, victim, third-party, geospatial and rapper/network files.
