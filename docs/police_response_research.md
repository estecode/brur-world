# BRUR Gang-Violence Police-Response Research

Status: v0.1 — structured incident-response evidence layer
Coverage target: Sweden, 2011–present
Last research update: 2026-09-12

## Purpose

This file records how police and other emergency services responded to incidents already catalogued in the BRUR gang-violence research. The goal is to capture the public, historical response chain: when authorities were alerted, how quickly they arrived when reported, what broad resources were used, what was done at the scene, how the investigation proceeded, and what the later outcome was.

This is descriptive historical research. It must not be used to infer current police vulnerabilities, patrol routines, response blind spots or evasion tactics.

## Evidence rules

- Use only publicly reported information.
- Never invent an exact alarm time, arrival time, route, unit, vehicle or tactic.
- Preserve source wording such as `minutes later`, `during the night`, etc., instead of converting it into fake precision.
- `ARRIVAL_MODE` records only publicly stated broad resources such as patrols, helicopter, ambulance, rescue service or bomb squad.
- Prefer role over named officers in the dataset.
- Preserve `gripped`, `arrested`, `detained/remanded`, `charged`, `convicted`, `released`, `acquitted` and `unknown` as separate legal states.
- Later court outcomes must never be projected backward into the initial response.
- Exact private-address routing and current police infrastructure are outside scope.

## Response record schema

```text
INCIDENT_ID:
ALARM:
  RECEIVED_AT:
  SOURCE_OF_ALARM: emergency_call | witness | patrol_observation | security_guard | other | unknown
  INITIAL_REPORT:

ARRIVAL:
  FIRST_POLICE_AT:
  RESPONSE_TIME:
  ARRIVAL_MODE:
  OTHER_EMERGENCY_SERVICES:
  FIRST_ACTIONS:

SCENE:
  LIFE_SAVING_ACTIONS:
  CORDON:
  EVACUATION:
  DOOR_KNOCKING:
  WITNESS_CANVASS:
  TECHNICAL_EXAMINATION:
  SPECIALIST_RESOURCES:
  SEARCH:

IMMEDIATE_ENFORCEMENT:
  PERSONS_STOPPED:
  PERSONS_DETAINED:
  PERSONS_ARRESTED:
  VEHICLES_STOPPED_OR_SEIZED:
  WEAPONS_OR_OBJECTS_SEIZED:

INVESTIGATION:
  INITIAL_CLASSIFICATION:
  LATER_CLASSIFICATION:
  SPECIAL_INCIDENT_DECLARED:
  INVESTIGATIVE_ACTIONS:
  LINKED_CASES:

OUTCOME:
  SUSPECTS_IDENTIFIED:
  CHARGES:
  COURT_OUTCOME:
  OTHER_CONSEQUENCES:

SOURCES:
RESEARCH_CONFIDENCE:
NOTES:
```

## Verified records

### SE-2012-SUP-0002 — Kantatgatan, Malmö

```text
ALARM:
  RECEIVED_AT: around midday; exact minute not established in current source set
  SOURCE_OF_ALARM: public incident / emergency response; exact caller unknown
  INITIAL_REPORT: man shot on open street

ARRIVAL:
  FIRST_POLICE_AT: shortly after shooting
  RESPONSE_TIME: exact minutes unknown
  ARRIVAL_MODE: police patrols; ambulance also attended
  FIRST_ACTIONS: police and medical personnel reached victim; victim died shortly after police arrived

SCENE:
  CORDON: large area rapidly cordoned
  TECHNICAL_EXAMINATION: yes, started shortly after cordon

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder
  INVESTIGATIVE_ACTIONS: telephone/SMS evidence and relationship/motive reconstruction later became important in prosecution

OUTCOME:
  SUSPECTS_IDENTIFIED: yes
  CHARGES: shooter and several alleged planners prosecuted
  COURT_OUTCOME: shooter convicted; appeal court increased sentence to 16 years
  OTHER_CONSEQUENCES: prosecution/court found victim had been mistaken for intended target

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- SVT, `Lindängenmordet sannolikt misstag`
- SVT, `Hämnades på fel person`
- Sveriges Radio court follow-up in source register

### SE-2015-0001 — Vår krog och bar, Göteborg

```text
ALARM:
  RECEIVED_AT: shortly after 22:00 on 2015-03-18; later evidence places attack closer to 22:30
  SOURCE_OF_ALARM: calls from restaurant / people at scene
  INITIAL_REPORT: shooting inside restaurant, multiple injured

ARRIVAL:
  FIRST_POLICE_AT: within a few minutes after perpetrators left, according to first officer interviewed later
  RESPONSE_TIME: qualitative `a few minutes`; exact dispatch-to-arrival interval not yet established
  ARRIVAL_MODE: nearby police patrol; additional police and emergency medical resources followed
  FIRST_ACTIONS: entered scene, began dealing with numerous injured; first officer attempted life-saving care on a critically wounded victim

SCENE:
  LIFE_SAVING_ACTIONS: yes
  CORDON: yes
  TECHNICAL_EXAMINATION: extensive
  WITNESS_CANVASS: extensive

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: no immediate shooter arrest documented in the initial minutes

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder / attempted murder; gang-related attack suspected immediately
  INVESTIGATIVE_ACTIONS: surveillance-video analysis, witness interviews, technical evidence, links to other shootings, drugs and weapons investigations
  LINKED_CASES: Brämaregården/Väderkvarnsgatan and Jaegerdorffsplatsen investigations were included in wider casework

OUTCOME:
  SUSPECTS_IDENTIFIED: multiple
  CHARGES: eight men charged in major prosecution
  COURT_OUTCOME: all eight convicted in district court; appeal handling later changed parts of legal responsibility
  OTHER_CONSEQUENCES: investigation reached about 12,000 pages and was one of Region West's largest at the time

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- Sveriges Radio, `Två döda i skottdrama i Göteborg`
- SVT, `Skjuten man vid Vårväderstorget dog i hans armar`
- Sveriges Radio, `Åtta åtalas efter dubbelmordet i Göteborg`
- SVT/SR court follow-ups

### SE-2015-0002 — Torslanda vehicle explosion

```text
ALARM:
  RECEIVED_AT: shortly after 17:00 on 2015-06-12
  SOURCE_OF_ALARM: explosion/traffic incident reports; exact caller not yet coded
  INITIAL_REPORT: vehicle exploded near Torslanda fire station

ARRIVAL:
  FIRST_POLICE_AT: exact time unknown
  RESPONSE_TIME: unknown
  ARRIVAL_MODE: police and rescue/medical response
  FIRST_ACTIONS: scene secured; casualties handled; incident initially had to be understood as both catastrophic explosion and possible criminal act

SCENE:
  CORDON: traffic/area cordon extended for roughly three kilometres according to SVT reporting
  TECHNICAL_EXAMINATION: extensive
  SPECIALIST_RESOURCES: explosion/forensic expertise; exact unit names not coded
  SEARCH: police searched surrounding terrain for vehicle parts because of blast force

INVESTIGATION:
  INITIAL_CLASSIFICATION: cause initially open
  INVESTIGATIVE_ACTIONS: vehicle removed for detailed forensic examination; multiple technical analyses; two hypotheses examined publicly — accidental/onboard explosive versus device placed by an outsider

OUTCOME:
  OTHER_CONSEQUENCES: event was later publicly connected to gang conflict

RESEARCH_CONFIDENCE: HIGH for response/forensics; later perpetrator outcome pending reconciliation
```

Sources:
- SVT, `Bilexplosion har koppling till gängkonflikt`
- SVT, `Efter explosionen i Torslanda – Detta gör polisen nu`
- SVT, `4-årig flicka offer i gängkonflikten`

### SE-2015-GEO-001 — Dimvädersgatan grenade attack, 2015-10-13/14

```text
ALARM:
  RECEIVED_AT: shortly before 23:00
  SOURCE_OF_ALARM: emergency report of explosion
  INITIAL_REPORT: explosion at apartment building

ARRIVAL:
  FIRST_POLICE_AT: shortly after alarm; exact minute unknown
  ARRIVAL_MODE: first police patrols
  FIRST_ACTIONS: confirmed damage to windows/building and secured scene

SCENE:
  TECHNICAL_EXAMINATION: yes; incident established as hand-grenade attack

INVESTIGATION:
  INITIAL_CLASSIFICATION: serious explosive incident
  SPECIAL_INCIDENT_DECLARED: broader gang-conflict work was already being handled as a special police operation in Göteborg
  INVESTIGATIVE_ACTIONS: folded into wider work against gang conflict; police publicly said they were working to identify responsible persons

OUTCOME:
  OTHER_CONSEQUENCES: police cited increased presence and broader seizures of weapons/explosives during the ongoing special operation

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- Sveriges Radio, `Handgranat kastad i bostadsområde`
- Sveriges Radio, `Uppblossande våld i Göteborg orsakar oro`

### SE-2016-0001 — Dimvädersgatan fatal grenade attack

```text
ALARM:
  RECEIVED_AT: shortly after 03:00 on 2016-08-22
  SOURCE_OF_ALARM: emergency call after explosion
  INITIAL_REPORT: explosion in apartment building with injured child

ARRIVAL:
  FIRST_POLICE_AT: exact time unknown
  RESPONSE_TIME: unknown
  ARRIVAL_MODE: police and ambulance/emergency medical response
  FIRST_ACTIONS: child transported to hospital; scene secured

SCENE:
  LIFE_SAVING_ACTIONS: child taken to hospital but later died
  CORDON: yes
  DOOR_KNOCKING: yes, conducted in surrounding area
  TECHNICAL_EXAMINATION: started during morning; later established that a hand grenade had been thrown through window
  WITNESS_CANVASS: door-knocking / neighborhood information collection

INVESTIGATION:
  INITIAL_CLASSIFICATION: serious explosion / suspected criminal attack
  LATER_CLASSIFICATION: gang-conflict/homicide investigation
  SPECIAL_INCIDENT_DECLARED: yes; police established a `Särskild händelse`
  INVESTIGATIVE_ACTIONS: examined revenge hypothesis and connection to household linked to a convicted Vår krog participant

OUTCOME:
  SUSPECTS_IDENTIFIED: none in immediate reporting
  OTHER_CONSEQUENCES: heightened concern about retaliatory gang violence and harm to children/relatives

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- Sveriges Radio, `Åttaåring död i explosion - kan vara hämnd`
- Sveriges Radio, `Gängkrig förmodas ligga bakom åttaårings död`
- Sveriges Radio, `Brå: Hänsynslösheten har ökat bland kriminella`

### SE-2016-GEO-002 — Vårvädersgatan grenade attack, 2016-12-15

```text
ALARM:
  RECEIVED_AT: just before 22:00
  SOURCE_OF_ALARM: reports of explosion
  INITIAL_REPORT: explosion near residential property

ARRIVAL:
  FIRST_POLICE_AT: shortly after alarm
  ARRIVAL_MODE: police + rescue service
  FIRST_ACTIONS: locate blast site, establish damage/no known personal injury

SCENE:
  TECHNICAL_EXAMINATION: yes; by morning police assessed device was probably a hand grenade

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: none by following morning

INVESTIGATION:
  INITIAL_CLASSIFICATION: public-endangerment-type offence
  LATER_CLASSIFICATION: attempted murder during night because targeted attack could not be ruled out

OUTCOME:
  OTHER_CONSEQUENCES: illustrates how legal classification changed as police understanding of target intent developed

RESEARCH_CONFIDENCE: HIGH
```

Source:
- Sveriges Radio, `Explosion i Biskopsgården`

### SE-2023-SUP-0001 — Gränby, Uppsala

```text
ALARM:
  RECEIVED_AT: around 01:00 on 2023-09-07
  SOURCE_OF_ALARM: alarm to police; exact caller type unknown
  INITIAL_REPORT: serious shooting at residence in Gränby area

ARRIVAL:
  FIRST_POLICE_AT: exact minute unknown
  RESPONSE_TIME: unknown
  ARRIVAL_MODE: large police response
  FIRST_ACTIONS: secured scene, confirmed woman in her 60s fatally shot, notified relatives

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: two people, aged 15 and 19, arrested during the same day
  PERSONS_DETAINED: both later held/anhållna on probable cause at that stage

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder
  INVESTIGATIVE_ACTIONS: police investigated connection to criminal environment and risk of retaliation
  SPECIALIST_RESOURCES: additional reinforcements sent to Uppsala

OUTCOME:
  OTHER_CONSEQUENCES: police placed addresses under surveillance/protection and prepared to prevent retaliatory attacks
  COURT_OUTCOME: final court result not yet reconciled in this file

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- SVT, `Kvinna i 60-årsåldern skjuten till döds i Uppsala – två anhållna`
- SVT, `Polisen bevakar adresser – rustar för hämndaktioner`
- Sveriges Radio, `Polisen bekräftar: Två gripna efter mordet`

### Farsta centrum mass shooting, 2023-06-10

```text
ALARM:
  RECEIVED_AT: early evening around 18:00; exact first emergency-call minute not yet reconciled
  SOURCE_OF_ALARM: public/witness reports; exact first caller not coded
  INITIAL_REPORT: automatic-fire shooting near Farsta centrum/tunnelbana with multiple people hit

ARRIVAL:
  FIRST_POLICE_AT: exact minute not yet coded
  RESPONSE_TIME: unknown in current source set
  ARRIVAL_MODE: large police response; pursuit resources
  OTHER_EMERGENCY_SERVICES: ambulance/medical response
  FIRST_ACTIONS: scene response to multiple casualties; search for fleeing vehicle/persons

SCENE:
  LIFE_SAVING_ACTIONS: yes through emergency medical response; exact police first-aid actions not yet coded
  CORDON: yes
  TECHNICAL_EXAMINATION: extensive; around twenty shots were later reconstructed in evidence

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: two men arrested the same evening after intensive vehicle pursuit outside Järna
  VEHICLES_STOPPED_OR_SEIZED: suspected getaway car stopped/seized
  WEAPONS_OR_OBJECTS_SEIZED: firearms found in suspected getaway vehicle

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder / attempted murder / weapons offences
  INVESTIGATIVE_ACTIONS: vehicle/firearm evidence, scene evidence, suspect reconstruction, later arrests

OUTCOME:
  SUSPECTS_IDENTIFIED: four principal suspects later prosecuted
  CHARGES: two murders, 17 attempted murders, aggravated weapons offences and other charges
  OTHER_CONSEQUENCES: two additional suspected participants were arrested in August 2023; case proceeded to major trial in 2024
  COURT_OUTCOME: final judgment details should be added in next legal-status reconciliation pass

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- SVT, `Fyra män åtalas efter dödsskjutningen i Farsta`
- SVT, `Två personer häktade misstänkta för skjutningen i Farsta`
- SVT, `Rättegången om dödsskjutningen i Farsta inledd`

### SE-2023-0002 — Telefonplan/Västberga family shooting

```text
ALARM:
  RECEIVED_AT: shortly before 01:00 on 2023-10-12
  SOURCE_OF_ALARM: police alarm to residence; exact caller unknown
  INITIAL_REPORT: shooting at villa/home, multiple victims

ARRIVAL:
  FIRST_POLICE_AT: exact minute unknown
  RESPONSE_TIME: unknown
  ARRIVAL_MODE: police and medical response
  FIRST_ACTIONS: located two shot parents indoors; one dead at scene, one transported/treated; child also found lightly injured

SCENE:
  CORDON: police remained in area into daytime
  DOOR_KNOCKING: yes
  WITNESS_CANVASS: neighborhood canvass/door-knocking

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: none in immediate reporting

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder / attempted murder
  INVESTIGATIVE_ACTIONS: police examined links to other serious violent incidents during same night and earlier criminal conflicts
  LINKED_CASES: contemporaneous Bredäng door shooting and Huddinge arson/possible explosive-device incident investigated for possible connections

OUTCOME:
  OTHER_CONSEQUENCES: bomb squad deployed to linked Huddinge incident; several homes evacuated there; police widened analysis from single shooting to possible coordinated/linked violence
  COURT_OUTCOME: pending reconciliation

RESEARCH_CONFIDENCE: HIGH for immediate response; later case outcome incomplete
```

Sources:
- SVT, `En död efter skjutning i södra Stockholm – fanns barn i hemmet`
- SVT Nyhetstecken follow-up on door-knocking and linked incidents

### Bagarmossen wrong-target killing, 2024-07-09

```text
ALARM:
  RECEIVED_AT: 23:23
  SOURCE_OF_ALARM: reports of several shots
  INITIAL_REPORT: suspected shooting outdoors

ARRIVAL:
  FIRST_POLICE_AT: approximately 23:27
  RESPONSE_TIME: about 4 minutes, explicitly stated by police spokesperson
  ARRIVAL_MODE: police patrols; ambulance followed
  FIRST_ACTIONS: found severely injured teenage boy; members of public had already started first aid

SCENE:
  LIFE_SAVING_ACTIONS: public first aid continued into ambulance takeover; victim transported to hospital and later died
  CORDON: yes
  TECHNICAL_EXAMINATION: completed during the night/early morning
  SEARCH: ongoing overnight

IMMEDIATE_ENFORCEMENT:
  PERSONS_ARRESTED: none by 02:40; three people arrested during following weekend
  PERSONS_DETAINED: one 17-year-old later remanded on probable cause for murder and aggravated weapons offence; two others released, one still suspected of protecting an offender

INVESTIGATION:
  INITIAL_CLASSIFICATION: murder
  INVESTIGATIVE_ACTIONS: technical scene examination, suspect search, later arrests; police/SVT hypothesis developed that victim was not intended target

OUTCOME:
  OTHER_CONSEQUENCES: increased police presence announced for reassurance in area; later homicide prosecution developed
  COURT_OUTCOME: subsequent trial/judgment status requires separate update

RESEARCH_CONFIDENCE: HIGH
```

Sources:
- SVT, `Tonåring död efter skjutning i Bagarmossen`
- SVT, `Uppgifter till SVT: 16-åringen var inte tilltänkt måltavla`
- SVT, `17-åring häktad efter dödsskjutningen i Bagarmossen`

## Cross-incident police-response fields to derive later

```text
known response time when publicly reported
immediate arrest vs delayed arrest vs no known arrest
helicopter/dog/bomb-squad/specialist resources
first aid by public vs police vs ambulance
door-knocking / witness canvass
technical scene examination
protective surveillance of linked addresses
legal-classification changes after scene assessment
Särskild händelse / reinforced regional or national operation
prosecution outcome
conviction / acquittal / released suspect
```

## Coverage queue

This v0.1 is materially populated but not exhaustive. Every incident ID in these files must eventually receive a response record or an explicit `public_data_not_found` marker:

- `docs/gang_violence_incident_research.md`
- `docs/gang_violence_source_supplement.md`
- `docs/gang_violence_third_party_research.md`
- `docs/gang_violence_geospatial_research.md`

Priority extraction order:

```text
1. 2011–2016: reconstruct alarm/arrival/investigation from local archives.
2. 2017: pair every fatal/injury record with initial police reporting and later court outcome.
3. 2018–2022: use police/SVT shooting archive as incident backbone, then add local response articles.
4. 2023: fully reconstruct Stockholm/Uppsala violence wave including preventive address protection and linked-event investigations.
5. 2024–2025: add exact public alarm/arrival timestamps where police reporting exposes them.
6. 2026: keep current investigations provisional and avoid tactical/current-resource inference.
```

For records where police response cannot be found publicly:

```text
POLICE_RESPONSE_STATUS: public_data_not_found
```

That is preferable to fabricating a plausible standard response.
