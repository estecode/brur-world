# BRUR Research

This folder contains BRUR's structured real-world research evidence. Research is kept separate from runtime/architecture documentation and is designed to be converted into a database later.

## Research boundary / fiction firewall

**Research data is research data. It stays in `docs/research/` and must never be copied directly into game data, gameplay content, characters, factions, dialogue, missions or world events.**

Real-world research may inform only abstract patterns after a deliberate fiction-safety pass. Any material that crosses from research into game design must be thoroughly transformed into independently fictional content.

Required transformation rules:

- Never map a real person, artist, victim, suspect, perpetrator or relative directly to a game character.
- Never map a real criminal network directly to a game faction. Names alone are not sufficient anonymization.
- Do not preserve a distinctive combination of real network history, leadership, enemies, geography, chronology, relationships or incidents under fictional names.
- Replace or substantially transform names, faction identities, geography, addresses, chronology, relationships and circumstances.
- Prefer composite fiction built from broad patterns observed across multiple independent sources/cases rather than adapting one identifiable case.
- Do not reproduce unique or unusual incident details when their combination could make a real case identifiable.
- Do not use research-derived fiction to attribute stupidity, incompetence, cowardice, brutality, motives, personality traits or other evaluative characteristics to an identifiable real person or network.
- Do not create satire, ridicule or disrespectful caricatures that can reasonably be read as referring to an identifiable real criminal actor or network.
- Research GPS coordinates and real incident locations are evidence only; they are not gameplay spawn/event coordinates.
- Real network relationships are evidence only; they are not a template for the game's faction graph.
- If a fictional element can still reasonably be traced to one real person, network or incident, transform it further or do not use it.

The intended flow is:

```text
real-world sources
      ↓
docs/research/ evidence
      ↓
abstract patterns / mechanics
      ↓
fiction-safety transformation
      ↓
independently fictional BRUR content
```

There is deliberately no direct `research -> game data` path.

The research layer may retain factual detail needed for source analysis and historical understanding. The gameplay layer must not. This boundary applies even when the underlying facts are public.

## Files

- `gameplay_research_map.md` — aggregate patterns, timelines and gameplay implications.
- `gang_violence_incident_research.md` — anonymized incident/person catalogue.
- `gang_violence_source_supplement.md` — supplemental source pass and corroborated leads.
- `gang_violence_third_party_research.md` — third-party/outsider victims and relationships.
- `gang_violence_geospatial_research.md` — WGS84 positions and precision classes.
- `gangsterrap_network_research.md` — evidence-graded rapper/network relationships.
- `police_response_research.md` — police/emergency response and investigative follow-up.
- `legal_case_research.md` — courts, case numbers, judgments, appeals and final legal status.

## Shared evidence rules

- Public-source research only.
- Real victim/suspect/perpetrator names remain anonymized in incident/person records unless a public artist identity is itself the research subject.
- Allegations remain allegations; suspicion, charge, conviction and acquittal are distinct states.
- Every material claim should be traceable to a source.
- Unknown data stays `unknown` or `public_data_not_found`; never infer missing facts.
- Private/family-linked residences remain spatially coarse even if a precise address has been published.
