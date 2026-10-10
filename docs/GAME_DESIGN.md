# TACTERRA RPG — Game Design

Design pillars: **plan before you strike, expand with purpose, protect
your lifelines.** Winning rewards strategic planning, intelligent
expansion, resource balance, and tactical positioning — not clicking
faster or fielding the biggest stack.

## The match arc

1. You start as one nation (blue) among several AI rivals, holding your
   capital plus a few adjacent territories, with a modest army.
2. Scout the map: fertile plains for income, mountains for defense,
   chokepoints, wealthy neutral lands, and weaker neighbors.
3. Expand into neutral territory, develop key provinces, and recruit —
   but every soldier costs upkeep and every border you open is a border
   you must defend.
4. Rivals expand, build, and probe too. Weak borders invite attack.
5. Eliminate every rival nation to win. Lose all your territory and the
   match is over.

## Resources

| Resource | Earned from | Spent on | Shortage consequence |
|---|---|---|---|
| **Credits** | Territory income per day (terrain, cities, capitals, coasts, rivers, development) | Recruitment, development, fortifications | Cannot recruit or build; unpaid army upkeep → 3%/day desertion + warning |
| **Supplies** | Produced per territory per day (fertile land best, cities/capitals bonus) | Consumed by armies in the field | Unsupplied armies fight at 60% power after a 3-day grace period, then 2%/day attrition |
| **Manpower** | Regenerates at 2% of cap per day (cap = total population ÷ 10) | Recruitment (1 per soldier) | Cannot recruit beyond available manpower |

Income is always explainable: territory panel shows base income and
bonuses. You can inspect every cost before confirming.

## Territory

- Every territory has an ID, name, terrain, owner, neighbors, population,
  development (0–5), fort level (0–3), and garrison/army.
- **Orders only travel along adjacency.** You can move or attack only
  connected territories; the game rejects anything else with a reason.
- Capturing updates ownership, borders, income, and supply immediately.
- Terrain matters: fertile land earns most; mountains defend best;
  rivers add defense and income; coasts add income.

## Combat (documented formula)

Army power (attacker or defender):

```
power = troops × (1 + 0.5 × training) × defender_mult × supply_mult
```

- `training`: 0 (fresh recruits still training) → 1 (fully trained)
- `defender_mult`: terrain defense × (1 + 0.2 × fort level) × (1.15 if
  river) × **1.25 defender bonus**
- `supply_mult`: 1.0 if supplied, **0.6** if unsupplied past grace
- Losses scale with `COMBAT_LOSS_FACTOR` (0.35) and the power ratio, with
  a documented **±10% random jitter** — the only randomness in combat.
- The winner's surviving troops take the territory (if attacking);
  battle reports list both sides, the advantage reasons, losses, and
  whether the territory changed hands.

## Supply lines

Each nation's capital is its supply source. A territory is supplied if a
path of owned territories connects it to the capital (recomputed after
every ownership change). Armies in unsupplied territory get a 3-day grace
period, then fight weakened and attrit. Supply status is visible per
territory and per army — never a hidden rule.

## Enemy AI

Three personalities, emerging from different priorities:

- **Expansionist** — prioritizes neutral territory and economic growth.
- **Defensive** — fortifies threatened borders, only takes favorable fights.
- **Aggressive** — hunts weakness in nearby rivals, attacks at lower
  power thresholds.

Three difficulties scale decision quality, **not** secret resources:

| Difficulty | Think every | Attack threshold | Recruit target |
|---|---|---|---|
| Easy | 5 days | 2.2× power | 60% |
| Normal | 3 days | 1.6× power | 100% |
| Hard | 2 days | 1.35× power | 120% |

Aggressive lowers the attack threshold by 0.15; Defensive raises it by
0.3 and recruits slightly fewer troops. On every think tick an AI nation:
develops or fortifies (if it can afford it), recruits toward its target,
expands into beatable neutral neighbors, attacks its weakest beatable
enemy neighbor, and shifts troops from safe interior to threatened
borders. AI nations obey the same movement, cost, supply, and combat
rules as the player and are eliminated the same way.

## Victory & defeat

- A nation with **zero territories** is eliminated (armies removed,
  notification posted).
- **Victory:** all AI nations eliminated.
- **Defeat:** the player nation eliminated.
- The result screen reports the outcome plus match statistics:
  territories captured, battles won/lost, troops lost/killed, income
  earned, and match duration.

## Key numbers

| Constant | Value | Meaning |
|---|---|---|
| `DAYS_PER_SECOND` | 2.0 | game-days per real second at 1× |
| `SPEEDS` | 0.5 / 1 / 2 / 4 | pause + four speeds |
| Income: Fertile / Plains / Forest / Hills / Mountains / Desert | 10 / 6 / 5 / 4 / 3 / 2 | credits/day base |
| City / Capital / Coastal / River bonus | +8 / +10 / +2 / +1 | credits/day |
| Development | +25%/level, max 5; cost 100×2^level | economy investment |
| Fort | +20% defense/level, max 3; cost 80×2^level | defense investment |
| Terrain defense | Plains 1.0, Fertile 1.0, Forest 1.15, Hills 1.25, **Mountains 1.5**, Desert 0.9 | defender multiplier |
| Recruit | 10 credits + 1 manpower per soldier, 3 days training | army building |
| Upkeep | 0.02 credits/soldier/day; unpaid → 3%/day desertion | army cost |
| Supply | 0.01/army/day use; unsupplied → 60% power, 2%/day attrition after 3-day grace | logistics |
| Manpower | cap = population ÷ 10, regen 2%/day | recruit limit |
| Move speed | 600 map units/day | army movement |
| Defender bonus | 1.25× | entrenched advantage |
| Combat jitter | ±10% | only randomness in combat |
| Start presets | Poor (250/120/180), Standard (500/200/300), Rich (900/350/450) | credits / supplies / starting troops |
| Map sizes | Small 24, Standard 36, Large 48 territories | match scale |
| Save slots | 3, versioned JSON | local persistence |

(Values live in `scripts/core/tacterra.gd` — the single place where
tuning numbers are defined.)
