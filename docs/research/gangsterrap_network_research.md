# BRUR Gangsterrap / Criminal-Network Research

Status: v0.1 — structured public-figure research
Coverage target: Swedish rappers publicly documented as linked to criminal networks, network conflicts or network-related serious crime
Last research update: 2026-09-12

## Purpose

This file maps the overlap between Swedish rap/gangsterrap and criminal networks as a research layer for BRUR. It is **not** a list of rappers who merely use criminal imagery or belong to a genre.

An artist is included only when reliable public reporting, court material or police statements establish at least one of the following:

```text
- explicit network membership / leadership allegation from police or court material
- conviction or prosecution in a network-related serious-crime case
- documented close operational relationship with a criminal network
- murdered/injured in a violence event publicly assessed as network/gang related
- public reporting showing the artist used as a network propaganda/loyalty node
```

Musical collaborations, lyrics, neighborhood origin or friendships alone are not enough.

## Evidence states

```text
COURT_ESTABLISHED          = fact established in judgment / court finding
POLICE_ASSESSED            = police publicly assess network role/affiliation
MEDIA_CORROBORATED         = multiple established outlets report the same relationship
ASSOCIATE_ONLY             = documented proximity/relationship, but no verified membership
VICTIM_OF_NETWORK_VIOLENCE = network-related victim without verified network membership
DISPUTED                   = artist publicly denies the affiliation
UNKNOWN                    = insufficient evidence for a stronger label
```

## Artist record format

```text
ARTIST_ID:
STAGE_NAME:
BIRTH_YEAR:
STATUS: alive | deceased
DEATH_DATE:
DEATH_CONTEXT:
HOME/ORIGIN_AREA:
NETWORK:
NETWORK_ROLE:
NETWORK_EVIDENCE_STATE:
NETWORK_EVIDENCE:
ARTIST_DENIAL:
CRIMINAL_CASES:
VIOLENCE_EVENTS:
RELATIONSHIPS:
SOURCES:
RESEARCH_CONFIDENCE:
NOTES:
```

## Verified / strongly supported records

### ART-YASIN

```text
STAGE_NAME: Yasin
STATUS: alive
HOME/ORIGIN_AREA: Rinkeby/Järva, Stockholm
NETWORK: Shottaz-linked milieu; documented contacts with Vårbynätverket
NETWORK_ROLE: associate / network-linked artist
NETWORK_EVIDENCE_STATE: COURT_ESTABLISHED + MEDIA_CORROBORATED
NETWORK_EVIDENCE:
- SVT reported that Yasin had connections to people in Vårbynätverket and members of Shottaz.
- He was convicted in connection with preparations for an attempted kidnapping of Einár; the case formed part of the larger Vårbynätverket prosecution.
CRIMINAL_CASES:
- preparation for kidnapping / involvement in planned abduction of Einár; prison sentence upheld in appellate proceedings
VIOLENCE_EVENTS:
- linked to the 2020 Einár kidnapping case, not as victim in the completed kidnapping
RELATIONSHIPS:
- Yasin -> documented_contact_with -> Vårbynätverket actor(s)
- Yasin -> linked_to -> Shottaz members
- Yasin -> case_relation -> Einár kidnapping plot
ARTIST_DENIAL: denied criminal responsibility during proceedings
RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- SVT, `Rapparen Yasin på fri fot`
  https://www.svt.se/nyheter/inrikes/rapparen-yasin-pa-fri-fot
- SVT, `Yasin vill frias – överklagar till HD`
  https://www.svt.se/nyheter/inrikes/yasin-vill-frias-overklagar-till-hd

### ART-HAVAL

```text
STAGE_NAME: Haval
STATUS: alive
HOME/ORIGIN_AREA: Stockholm
NETWORK: Vårbynätverket/Dalennätverket case environment; police-described close links to criminal networks
NETWORK_ROLE: associate / network-linked artist
NETWORK_EVIDENCE_STATE: COURT_ESTABLISHED + POLICE_ASSESSED
NETWORK_EVIDENCE:
- Haval was convicted for participation in the completed kidnapping and robbery of Einár.
- SVT reported police assessed both Haval and Yasin as having close connections to other criminal networks in Stockholm.
CRIMINAL_CASES:
- convicted for aiding kidnapping and robbery of Einár
VIOLENCE_EVENTS:
- 2020 Einár kidnapping
RELATIONSHIPS:
- Haval -> convicted_in -> Einár kidnapping
- Haval -> network_case_context -> Vårbynätverket
RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- SVT, `Åklagaren om mordet på Einár: Fruktansvärt`
  https://www.svt.se/nyheter/lokalt/stockholm/kidnappningen-av-ein-r-upp-i-hovratten
- SVT, `Rapparen Yasin på fri fot`
  https://www.svt.se/nyheter/inrikes/rapparen-yasin-pa-fri-fot

### ART-DREE-LOW

```text
STAGE_NAME: Dree Low
STATUS: alive
HOME/ORIGIN_AREA: Husby/Järva, Stockholm
NETWORK: Husby-area criminal network / Husbys hyenor in police/media descriptions
NETWORK_ROLE: leading/driving role according to police assessment
NETWORK_EVIDENCE_STATE: POLICE_ASSESSED + DISPUTED
NETWORK_EVIDENCE:
- SVT reported police assessed Dree Low as having had a leading role in a criminal gang in the Järva area.
- Separate SVT reporting on a Husby murder stated defendants were connected to the same criminal network to which Dree Low had previously been linked.
- Aftonbladet later described police material characterizing him as a central actor in the Husby network environment.
ARTIST_DENIAL: Dree Low has denied network affiliation in reporting.
CRIMINAL_CASES:
- convicted robbery (2021)
- convicted gross weapons offence after appellate judgment (reported 2025)
VIOLENCE_EVENTS:
- people charged in a Husby murder appeared in and were praised in his music videos; this is evidence of social/network overlap, not proof he participated in that murder
RELATIONSHIPS:
- Dree Low -> police_assessed_role -> Husby-area network
- Dree Low -> social/media_relation -> defendants in Husby murder case
RESEARCH_CONFIDENCE: HIGH for police assessment and convictions; membership remains disputed by artist
```

SOURCES:
- SVT, `Rapparen Dree Low åtalas för grovt vapenbrott`
  https://www.svt.se/nyheter/lokalt/stockholm/dree-low-atalas-for-grovt-vapenbrott
- SVT, `Åtalade för mordet i Husby figurerar i artisten Dree Lows musikvideor`
  https://www.svt.se/kultur/atalade-for-mordet-i-husby-figurerar-i-artisten-dree-lows-musikvideor
- SVT, `Rapparen Dree Low döms till fängelse`
  https://www.svt.se/nyheter/inrikes/rapparen-dree-low-doms-till-fangelse

### ART-5FIFTYY

```text
STAGE_NAME: 5iftyy
STATUS: alive
HOME/ORIGIN_AREA: Upplands-Bro / Stockholm region
NETWORK: Bronätverket / Foxtrot, Rawa Majid side
NETWORK_ROLE: inner-circle / propaganda-loyalty artist according to police/media/court material
NETWORK_EVIDENCE_STATE: POLICE_ASSESSED + COURT_CORROBORATED
NETWORK_EVIDENCE:
- Aftonbladet reported police had considered 5iftyy part of Bronätverket for years and, in 2023, part of Rawa Majid's inner circle.
- Södertörns tingsrätt later described 5iftyy as responsible for a significant part of Foxtrot's marketing/loyalty messaging in music and social media.
VIOLENCE_EVENTS:
- explosions occurred at addresses linked to the artist during the Foxtrot/Dalen conflict; one person was injured in one attack
RELATIONSHIPS:
- 5iftyy -> member_of/linked_to -> Bronätverket
- 5iftyy -> allied_with -> Rawa Majid/Foxtrot side
- 5iftyy -> conflict_media_opposition -> Nummeruno / Zeronätverket side after Foxtrot split
RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- Aftonbladet, `Rapparna kopplas till våldsvågen i Stockholm`
  https://www.aftonbladet.se/nyheter/a/xgkV6X/rapparna-kopplas-till-valdsvagen-i-stockholm
- Södertörns tingsrätt B 15631-23, judgment 2024-08-28 (network analysis section)
  https://fup.link/d/tr/sodertorns/b-15631-23/Sodertorns_TR_B_15631-23_DOM_2024-08-28.pdf

### ART-NUMMERUNO

```text
STAGE_NAME: Nummeruno
STATUS: alive/unknown-current
HOME/ORIGIN_AREA: Stockholm region
NETWORK: Zeronätverket / Ismail Abdo side in Foxtrot split
NETWORK_ROLE: network-aligned propaganda/loyalty artist according to court analysis
NETWORK_EVIDENCE_STATE: COURT_CORROBORATED
NETWORK_EVIDENCE:
- Södertörns tingsrätt described Nummeruno as serving a similar promotional/loyalty function for Zeronätverket as 5iftyy did for Foxtrot/Bronätverket.
- The judgment describes an earlier musical collaboration between 5iftyy and Nummeruno followed by hostile social-media signaling after the Foxtrot split.
RELATIONSHIPS:
- Nummeruno -> aligned_with -> Zeronätverket / Ismail Abdo side
- Nummeruno <-> previous_music_collaboration -> 5iftyy
- Nummeruno <-> later_conflict_media_opposition -> 5iftyy side
RESEARCH_CONFIDENCE: HIGH for court-described role
```

SOURCE:
- Södertörns tingsrätt B 15631-23, judgment 2024-08-28
  https://fup.link/d/tr/sodertorns/b-15631-23/Sodertorns_TR_B_15631-23_DOM_2024-08-28.pdf

### ART-EINAR

```text
STAGE_NAME: Einár
STATUS: deceased
DEATH_DATE: 2021-10-21
DEATH_CONTEXT: shot dead in Hammarby sjöstad; contemporary SVT sources described the shooting as gang-related based on source information
HOME/ORIGIN_AREA: Stockholm
NETWORK: no single verified membership; moved among several criminally connected groups
NETWORK_ROLE: network-adjacent artist / victim
NETWORK_EVIDENCE_STATE: ASSOCIATE_ONLY + VICTIM_OF_NETWORK_VIOLENCE
NETWORK_EVIDENCE:
- SVT/Diamant Salihu reported that Einár moved between many groupings and lacked the same stable backing that other rappers tied to particular gangs had.
- He was kidnapped by actors from the Vårbynätverket/Dalennätverket case environment in 2020 and subjected to extortion/violence.
- A planned explosion against a family-linked residence formed part of the coercion campaign.
VIOLENCE_EVENTS:
- 2020 kidnapping and robbery
- 2021 murder
RELATIONSHIPS:
- Einár -> victim_of -> Vårbynätverket/Dalennätverket kidnapping actors
- Einár -> moved_between -> multiple criminally connected groups
RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- SVT, `Hade kopplingar till kriminella gäng – och levde under hot`
  https://www.svt.se/nyheter/inrikes/rapartisten-einars-liv-i-kriminalitet
- SVT, `Rapparen Einár skjuten till döds i södra Stockholm`
  https://www.svt.se/nyheter/inrikes/person-allvarligt-skadad-efter-misstankt-skottlossning-i-hammarby-sjostad

### ART-C-GAMBINO

```text
STAGE_NAME: C.Gambino
STATUS: deceased
BIRTH_YEAR: 1998
DEATH_DATE: 2024-06-04/05
DEATH_CONTEXT: ambushed and shot in parking garage by Selma Lagerlöfs torg, Göteborg; later court proceedings resulted in convictions for aiding the murder
HOME/ORIGIN_AREA: Göteborg / Backa
NETWORK: no verified direct membership; friendships/links across Göteborg network environments
NETWORK_ROLE: network-adjacent artist / victim
NETWORK_EVIDENCE_STATE: ASSOCIATE_ONLY + VICTIM_OF_NETWORK_VIOLENCE
NETWORK_EVIDENCE:
- Police said the murder had links to criminal networks.
- Diamant Salihu reported some gang connections but no heavy criminal background.
- Sveriges Radio later reported prosecutors considered the motive gang-linked while police did not assess C.Gambino as directly tied to a criminal network.
VIOLENCE_EVENTS:
- murdered 2024
- subsequent threats/explosions/extortion around colleagues/music-industry actors have been linked in reporting to the conflict around his music/network associations
RELATIONSHIPS:
- C.Gambino -> friendship_links -> people in multiple Göteborg networks
- C.Gambino -> victim_of -> gang-linked murder
RESEARCH_CONFIDENCE: HIGH
```

SOURCES:
- SVT, `Rapartisten C.Gambino skjuten till döds i parkeringsgarage i Göteborg`
  https://www.svt.se/nyheter/lokalt/vast/man-skjuten-till-dods-i-parkeringsgarage-i-goteborg
- SVT, `Två anhållna för inblandning i mordet på C.Gambino`
  https://www.svt.se/nyheter/lokalt/vast/tva-anhallna-for-inblandning-i-mordet-pa-cgambino
- Sveriges Radio, `Mordet på C.Gambino firades i chattgrupp`
  https://www.sverigesradio.se/artikel/mordet-pa-c-gambino-firades-i-chattgrupp-timmar-efter-skjutningen

### ART-ROZH

```text
STAGE_NAME: Rozh
STATUS: deceased
DEATH_DATE: 2019-06-30
DEATH_CONTEXT: shot dead outside/near his home in Blackeberg, Stockholm
HOME/ORIGIN_AREA: Stockholm
NETWORK: exact network affiliation not established in current strong source set
NETWORK_ROLE: artist in gang-violence environment / murder victim
NETWORK_EVIDENCE_STATE: VICTIM_OF_NETWORK_VIOLENCE; membership UNKNOWN
NETWORK_EVIDENCE:
- SVT's later gangsterrap coverage explicitly groups Rozh, Einár and C.Gambino among known gangsterrappers murdered in gang violence.
- Earlier reporting documented that Rozh's older brother had also been shot dead in Stockholm.
VIOLENCE_EVENTS:
- 2019 murder
RELATIONSHIPS:
- Rozh -> sibling_of -> earlier homicide victim
RESEARCH_CONFIDENCE: HIGH for murder; LOW/UNKNOWN for specific network membership
```

SOURCES:
- SVT, `Våldet som skakar den svenska hiphopscenen`
  https://www.svt.se/kultur/kopplingar-mellan-vald-och-den-svenska-hiphopscenen
- SVT, `Juans söner Rozh och Shalaw mördades`
  https://www.svt.se/nyheter/lokalt/stockholm/juans-bada-soner-rozh-och-shalaw-mordades-kyrkogarden-ar-mitt-hem-nu
- SVT, `Så kan C.Gambinos död påverka svensk gangsterrap`
  https://www.svt.se/nyheter/lokalt/vast/sa-kan-cgambinos-dod-paverka-svensk-gangsterrap

## Records that remain intentionally anonymous

### ART-DALEN-ANON-01

```text
STAGE_NAME: withheld by source
STATUS: alive at 2023 reporting
AGE_AT_REPORT: 26
NETWORK: Dalennätverket
NETWORK_ROLE: leadership layer according to police material reported by Aftonbladet
NETWORK_EVIDENCE_STATE: POLICE_ASSESSED + DISPUTED
NETWORK_EVIDENCE:
- Aftonbladet reported police considered the artist part of Dalennätverket leadership.
- The artist denied being a member.
VIOLENCE_EVENTS:
- residence linked to artist was shot at
- separate murder plans against artist led to conviction of another person
NOTES: Do not deanonymize by inference from collaborations, age or catalog metadata. The source chose not to name the artist.
RESEARCH_CONFIDENCE: HIGH for source-described police assessment
```

### ART-FARSTA-ANON-01

```text
STAGE_NAME: withheld by source
STATUS: alive at 2023 reporting
AGE_AT_REPORT: 23
NETWORK: Farstautbrytarna; close relation to Dalennätverket in police material
NETWORK_ROLE: member according to police assessment reported by Aftonbladet
NETWORK_EVIDENCE_STATE: POLICE_ASSESSED
CRIMINAL_CASES:
- arrested/suspected in 2023 for involvement in an explosion; final legal outcome not yet coded
NOTES: Do not infer/deanonymize identity from music-video clues.
RESEARCH_CONFIDENCE: HIGH for reported police assessment
```

SOURCE for both anonymous records:
- Aftonbladet, `Rapparna kopplas till våldsvågen i Stockholm`
  https://www.aftonbladet.se/nyheter/a/xgkV6X/rapparna-kopplas-till-valdsvagen-i-stockholm

## Criminal-environment artist, no network membership yet established

### ART-ALEX-CEESAY

```text
STAGE_NAME: Alex Ceesay
STATUS: alive
NETWORK: no specific network membership established in current strong-source set
NETWORK_ROLE: none assigned
NETWORK_EVIDENCE_STATE: UNKNOWN
CRIMINAL_CASES:
- long criminal history publicly discussed by artist and documented in SVT reporting, including robbery, weapons, violence, narcotics and later gross money laundering
NOTES:
- Include in the research universe because he explicitly discusses his own criminal life and gangsterrap's influence, but do not label him a network member without stronger evidence.
RESEARCH_CONFIDENCE: HIGH for criminal history; UNKNOWN for network affiliation
```

SOURCE:
- SVT, `Rapparen Alex Ceesay om tiden på behandlingshemmet i Kramfors`
  https://www.svt.se/nyheter/lokalt/vasternorrland/rapparen-alex-ceesay-pa-behandlingshem-i-kramfors-korpberget-var-det-enda-stallet-som-ville-ta-emot-mig

## Exclusion rules

Do **not** add an artist merely because:

- the music is called gangsterrap/drill;
- lyrics discuss weapons, drugs or gangs;
- the artist comes from a neighborhood with an active network;
- the artist collaborates with somebody who has a network link;
- social media or Flashback alleges membership without corroboration.

Examples such as A36, Asme, Aden, Z.E, 1.Cuz and other major rap artists require an explicit supported network relation before they belong in this registry. Musical association is not network evidence.

## Database conversion

Recommended entities/edges:

```text
artist(id, stage_name, birth_year, status, death_date, origin_area)
artist_network(artist_id, network_id, role, evidence_state, valid_from, valid_to, disputed)
artist_case(artist_id, case_id, legal_status, offence, date)
artist_incident(artist_id, incident_id, relation_type)
artist_artist_relation(artist_a, artist_b, relation_type, source)
network_conflict(network_a, network_b, period)
source(source_id, outlet, date, url, evidence_type)
```

A single artist can be simultaneously:

```text
artist
network associate
convicted person
victim
relative/friend of another participant
music collaborator
```

Do not collapse these into one label.

## Research backlog

1. Expand historically before 2019; identify artists with explicit police/court network links rather than genre associations.
2. Follow final court outcomes for network-related artist cases.
3. Map murdered artists and their incidents into `gang_violence_geospatial_research.md`.
4. Track network split/loyalty changes over time; affiliation is time-dependent.
5. Add deceased artists only after confirming the death belongs to the network-violence research scope.
6. Preserve anonymous source treatment when reputable reporting intentionally withholds an artist's identity.
