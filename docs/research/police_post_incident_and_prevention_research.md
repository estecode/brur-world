# BRUR Police Post-Incident and Prevention Research

Status: v0.1 — public, non-sensitive post-incident and prevention research
Coverage target: Sweden, serious violence in criminal environments
Last research update: 2026-09-12

## Purpose

This file records what may happen after the immediate crime-scene phase: reassurance presence, information gathering, escalation to special command structures, linked-conflict analysis, group-violence prevention, support/exit pathways and longer-running interventions.

It complements:

- `police_dispatch_and_command_research.md` — acute command and dispatch;
- `police_response_research.md` — what happened in specific historical incidents;
- `police_investigation_methods_research.md` — investigative work after serious violence;
- `police_event_chain_research.md` — cross-file chain model.

This is not a catalogue of police pressure points, surveillance coverage, local staffing gaps or ways to evade police activity.

## Immediate post-incident presence

Recent official police notices show that the visible police response often continues after the forensic cordon has been lifted.

Recurring publicly documented purposes include:

- reassurance / `trygghetsskapande` presence;
- being available to residents with questions;
- continuing door-to-door enquiries;
- collecting tips and observations;
- maintaining police visibility after a frightening public event;
- sometimes using a mobile police office or equivalent public contact point.

Examples:

### Fagersjö, Stockholm, 2026-03-07

After the forensic examination and cordon were finished, police announced that several patrols would return the next day in a reassurance role and to be available to people with information.

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/7/07-mars-17.22-skottlossning-stockholm/

### Mölndal explosion, 2025-01-12

After the initial explosive-scene work, police deployed a mobile police office so residents could ask questions or leave tips.

Source:
- https://polisen.se/aktuellt/handelser/2025/januari/12/12-januari-06.01-explosion-molndal/

### Göteborg explosion, 2026-03-06

After technicians completed the scene examination and the initial operation ended, police stated that investigation work would continue during the day with information collection, surveillance-video acquisition and door-to-door enquiries, while personnel would remain for reassurance measures.

Source:
- https://polisen.se/aktuellt/handelser/2026/mars/6/06-mars-23.14-explosion-goteborg/

Research pattern:

```text
scene stabilized
      ↓
forensic cordon eventually lifted
      ↓
visible police presence may remain
      ↓
public contact + tips + continued enquiries
      ↓
community anxiety / information flow changes
```

This is not guaranteed in every incident.

## Reclassification as information changes

Police event notices repeatedly demonstrate that legal/investigative classification can change when facts change.

Examples include:

- attempted murder → murder when a victim later dies;
- explosion / serious public-danger offence → attempted murder when targeting intent becomes clearer;
- initial uncertain event → confirmed firearm or explosive incident after technical examination.

The research database must therefore preserve classification history instead of overwriting the first classification.

```text
CLASSIFICATION_HISTORY:
- AT:
  CLASSIFICATION:
  BASIS_PUBLICLY_REPORTED:
  SOURCE:
```

This creates an important causal mechanic for later fictional design: authorities and other actors act on imperfect information, and the perceived meaning of an incident can change.

## Special incident (`särskild händelse`)

Polismyndigheten defines a `särskild händelse` as a situation that the ordinary police organization is not adapted to handle and therefore requires a special organization and command structure. Reasons can include scale, seriousness, complexity, need for many police personnel or specialist competence.

Regional special incidents are normally decided at regional command level; national ones by national command. A region can request support from other regions or national specialist functions.

Public source:
- https://polisen.se/om-polisen/polisens-arbete/sarskild-handelse/

Publicly described support can include broad categories such as:

- additional investigators;
- National Bomb Squad;
- National Task Force / specialist intervention resources where appropriate;
- police aviation;
- reinforcement with uniformed field personnel.

Research rule: record only the fact that a special incident/operation was publicly declared and the broad support actually reported. Do not infer unpublished staffing, readiness, staging or tactics.

## Police operation vs special incident

A 2026 Stockholm police communication describes a `polisoperation` as a series of coordinated police actions led inside ordinary line operations, in contrast to a `särskild händelse`, which creates a special organization.

Source:
- https://polisen.se/aktuellt/nyheter/stockholm/2026/mars/starkta-sakerhetsatgarder-med-anledning-av-det-forsamrade-omvarldslaget/

Research distinction:

```text
COMMAND_FORM:
  ordinary_line
  police_operation
  regional_special_incident
  national_special_incident
  unknown
```

Do not treat these labels as interchangeable.

## Conflict-series response

Brå 2023:4 emphasizes that many homicides in criminal environments are reactions to previous violent events and that conflicts can become long sequences of serious offences. This means the police response can move from a single-case mindset to a linked-conflict mindset.

Possible publicly evidenced transitions:

```text
incident A
      ↓
retaliation hypothesis / linked conflict recognized
      ↓
addresses or persons considered at elevated risk
      ↓
increased protective / preventive presence where publicly reported
      ↓
incident B or disrupted planned violence
      ↓
case coordination / intelligence sharing
```

Example already stored in `police_response_research.md`:

`SE-2023-SUP-0001 — Gränby, Uppsala`

Public reporting described police investigating links to criminal conflict and the risk of retaliation, with additional reinforcements and monitoring/protection of addresses.

This relationship is important for chain research but must never be turned into a real-time predictor of which actual addresses police protect.

## Group Violence Intervention (GVI)

Brå describes Group Violence Intervention as a strategy to reduce serious violence in criminal environments in a defined city or area through cooperation between police, municipality, Prison and Probation Service and the local community.

Official Brå source:
- https://bra.se/english/crime-prevention/gvi

The three core components are:

1. **Communication** — a shared message that violence must stop, communicated directly to group members.
2. **Offer of help** — support for people who want to leave criminal life.
3. **Sanctions / focused consequences** — swift and predictable consequences when violence continues, focused on groups driving violence.

Brå stresses that the three components reinforce each other.

## Call-ins and custom notifications

Swedish GVI implementations use two broad communication forms:

- **call-in** — organized meetings where selected people from mapped violent groups hear the anti-violence message from justice, municipal and community actors;
- **custom notification** — more individualized communication, often involving police and/or probation together with social services.

A 2024 process evaluation covering Järfälla/Upplands-Bro, Huddinge and Uppsala describes planning, group mapping, call-ins, custom notifications, sanctions and social support as linked parts of the implementation.

Source:
- https://bra.se/download/18.5e0f78b192bd39b2327ef2/1730456293391/GVI%20Processutv%C3%A4rdering%20J%C3%A4rf%C3%A4lla%20U-Bro%20Huddinge%20Uppsala%20Slutrapport.pdf

For BRUR research, store only the broad intervention state:

```text
GVI_EVENT:
  AREA:
  PERIOD:
  TARGET_GROUP_PUBLICLY_DESCRIBED:
  COMMUNICATION:
    call_in | custom_notification | both | unknown
  SUPPORT_OFFER_PUBLICLY_REPORTED:
  INCREASED_FOCUS_PUBLICLY_REPORTED:
  SOURCE:
```

Do not reproduce current target lists, operational selection criteria or tactics.

## GVI and event chains

GVI is especially relevant because it creates a documented bridge from a violent event to later preventive/social consequences.

Safe high-level chain:

```text
serious group-linked violence
      ↓
violence attributed at group level through lawful/publicly described process
      ↓
anti-violence communication
      ↓
focused societal attention / lawful sanctions
      ↘
       support offered to leave violence/criminality
      ↓
future group behaviour may change
```

This is a strategic model, not proof that every later event was caused by GVI.

## Social support and exit

GVI and separate exit-support work show that the institutional response is not only arrest/prosecution. Public strategy includes offers of support to leave criminal life.

For later fictional mechanics this supports independent consequences such as:

- a person considers leaving a group;
- family pressure increases;
- contact with social services/probation becomes possible;
- a group member's decision affects relationships inside the group.

Raw real-world support cases must never become game characters or missions.

## Trust, witnesses and community response

Brå 2023:4 found that witnesses who know the perpetrator are strongly relevant to case clearance, but such witnesses appear less often in some vulnerable-area cases. Brå connects willingness to provide information to trust, treatment by authorities and fear of threats/violence.

The police response therefore has two simultaneous tracks:

```text
ENFORCEMENT / INVESTIGATION
         +
TRUST / INFORMATION RELATIONSHIP
```

This is relevant to gameplay abstraction because police visibility can plausibly have more than one effect:

- improve information flow;
- reduce anxiety for some residents;
- increase anxiety or distrust for others;
- affect whether people choose to speak.

No single deterministic effect should be assumed.

## Public camera presence as prevention + evidence infrastructure

Polismyndigheten publicly states that camera surveillance can be used to prevent, prevent or detect crime and to investigate/prosecute offences after they occur. Recorded material may become trial evidence.

Source:
- https://polisen.se/lagar-och-regler/behandling-av-personuppgifter/kamerabevakning/

This creates a two-stage research relationship:

```text
preventive surveillance decision
      ↓
incident occurs inside/near covered public space
      ↓
recorded material may become investigative evidence
```

The research layer may store public decisions and later evidential use when established. It must not map or infer real camera blind spots.

## Long-term learning and linked investigations

Brå 2023:4 identifies several organizational effects relevant after the initial event:

- information sharing between linked investigations;
- cooperation with intelligence functions;
- cooperation with prosecutors;
- cooperation with NFC;
- systematic structuring of very large investigation material;
- continuity of investigation leadership.

The chain is therefore not simply `crime → arrest`. It can be:

```text
crime
 ↓
initial investigation
 ↓
no immediate resolution
 ↓
new linked incident / new forensic result / new digital material
 ↓
old evidence reinterpreted
 ↓
new suspect or evidential theory
 ↓
later prosecution
```

That delayed feedback loop is a strong candidate for fictional systemic gameplay after proper abstraction.

## Research schema

```text
POST_INCIDENT_RESPONSE:
  INCIDENT_ID:
  AFTER_CORDON:
    REASSURANCE_PRESENCE:
    CONTINUED_DOOR_KNOCKING:
    PUBLIC_TIP_POINT:
    MOBILE_POLICE_OFFICE:
  CLASSIFICATION_HISTORY:
  COMMAND_FORM:
  SPECIAL_INCIDENT:
  REINFORCEMENT_PUBLICLY_REPORTED:
  RETALIATION_RISK_PUBLICLY_REPORTED:
  PROTECTIVE_ACTION_PUBLICLY_REPORTED:
  LINKED_INVESTIGATIONS:
  GVI_LINK_PUBLICLY_ESTABLISHED:
  EXIT_OR_SUPPORT_LINK_PUBLICLY_ESTABLISHED:
  SOURCES:
  RESEARCH_CONFIDENCE:
```

Unknown remains unknown.

## Safe gameplay abstractions

This research can later support fictional systems where:

- a violent event changes police presence in an area for a period;
- residents react differently to visible police presence;
- new tips emerge after the first night;
- fear of retaliation affects people around a conflict;
- separate incidents become recognized as one conflict chain;
- preventive intervention can target a fictional group after a pattern emerges;
- support to exit can coexist with enforcement;
- consequences can continue long after the original incident.

None of those systems should recreate a real intervention, real target group or real police deployment pattern.
