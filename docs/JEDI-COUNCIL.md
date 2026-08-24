# Jedi Council — Multi-Agent Deliberation (MAD) Engine

The **Jedi Council** opponent (`kind: "jedi_council"`) is a high-order Multi-Agent Deliberation (MAD) engine built for *Great Hauses Chess*. It coordinates multiple Frontier LLMs across Sanctum proxyd (`:4040`) to deliberate, critique, and synthesize chess moves in real time with entertaining in-character chamber dialogue and bespoke 3D piece attachments.

---

## 1. Multi-Agent Deliberation (MAD) Architecture

The deliberation runs in three distinct pipeline stages:

- **Phase 1: Parallel Candidate Generation**
  - **Master Yoda (`claude-fable`):** Strategic center control, pawn levers, long-term spatial compression.
  - **Master Qui-Gon Jinn (`mistral-devstral-24b`):** Dynamic tactical flow, speculative gambits, king safety pressure.
  - **Master Ki-Adi-Mundi (`grok-4.6`):** Calculation auditor, tactical sanity check, trade ROI.

- **Phase 2: Red-Team Critique & Tactical Filter**
  - **Master Mace Windu (`gemini-flash` / `gemini-pro`):** Vaapad red-teamer. Scrutinizes proposed candidates for tactical blunders, hidden pins, and traps. Roasts overly romantic or reckless proposals.

- **Phase 3: Grand Master Synthesis**
  - **Master Yoda (`claude-fable`):** Reviews candidate proposals and Windu's critique to deliver the final chosen move and punchy chamber wisdom.

---

## 2. The Carmack Quorum & Progressive Refinement

To guarantee responsive gameplay without stalling on high-latency LLM seats:
1. **Dynamic Complexity Timeouts:**
   - Opening (ply < 10): 65s
   - Standard: 75s
   - Tactical (checks / heavy pressure): 100s
   - Critical Endgames (pieces <= 8): 140s
2. **Quorum Trigger (2/3):**
   - As soon as 2 valid candidate proposals arrive in Phase 1, a **2.5s grace window** begins.
   - If the third model is slow, the pipeline proceeds immediately to Phase 2 with the available quorum.
3. **Speculative Pondering:**
   - Deep async background pondering anticipates player responses during human turn time (120s budget), enabling sub-frame instant ponder hits (`✨ [PONDER HIT]`).
4. **Decoupled Fail-Safe Recovery:**
   - If upstream LLMs are unreachable or time out, **Council Intuitive Defense** calculates the safest legal move, sends an in-character alert, and gameplay continues smoothly.

---

## 3. Star Wars 3D Piece Customization

When playing against the Council (`_is_star_wars_mode()`), base medieval accessories (masks, hooded cloaks, wizard hats, bear caps, knight visors, medieval crowns/capes) are automatically stripped, and custom 3D props are scaled prominently:

| Role | Piece | 3D Attachment | Scale | Notes |
|---|---|---|---|---|
| **Princess Leia** | Queen | `SW_LEIA_BUNS` | 1.85x | Iconic coiled hair buns, rebel gown |
| **Han Solo** | King | `SW_HAN_HOLSTER` | 1.60x | Slanted Corellian gun belt & DL-44 blaster |
| **Millennium Falcon**| Rook | `SW_FALCON_ROOK` | 2.20x | Top of watchtower with cyan hyperdrive glow |
| **C-3PO** | Bishop | `SW_C3PO` | 1.70x | Gleaming golden protocol droid head |
| **Chewbacca** | Knight | `SW_CHEWIE_BANDOLIER` | 1.60x | Bowcaster ammo sash across rider |
| **Ewoks** | Pawns | `SW_EWOK_HOOD` | 1.85x | Endor leather cowl with wooden spear |

---

## 4. Test & Quality Gates

- **Engine Test Suite:** `res://tests/run_tests.gd` (79/79 PASS)
- **Costumes & Animation Gate:** `res://tests/test_costumes.gd` (857/857 PASS)
- **Council Deliberation & Quorum Gate:** `res://tests/test_jedi_council.gd` (21/21 PASS)
- **Artifact Output:** Universal macOS Mach-O Binary synced to `/Applications/Great Hauses Chess.app`.
