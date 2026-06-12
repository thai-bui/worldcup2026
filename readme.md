# FIFA World Cup 2026 - Monte Carlo Simulation

## Live Dashboards

Explore the interactive Tableau dashboards: [Tableau Public link](https://public.tableau.com/views/WorldCup2026_17812411216780/WorldCupPowerRankings?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link)

## Project Overview

This project predicts World Cup 2026 outcomes, including championship probabilities, round advancement rates, and group stage analysis, using a Monte Carlo simulation engine built from scratch.

The model scores all 48 teams using five factors: Elo rating, recent competitive form, top 5 league concentration, team cohesion and a slight advantage for the host countries. Each factor is normalized and weighted to produce a composite score, which drives match outcome probabilities across 10,000 simulated tournaments.

The stack is intentionally separated: PostgreSQL for data cleaning and transformation, R for the simulation engine, and Tableau for visualization. This separation reflects how these tools are used in practice, with each layer doing what it does best.

For a detailed breakdown of all findings, see [ANALYSIS.md](documentation/analysis.md).

---

## Folder Structure

```
worldcup2026/
├── documentation/       # Methodology writeup, analysis findings
├── exported_data/       # CSV outputs from R simulation
├── r/                   # R scripts (data load, simulation, aggregation, export)
├── raw_data/            # Source CSV files collected manually
├── sql/                 # PostgreSQL scripts for data cleaning and views
└── tableau/             # Tableau workbook and dashboard screenshots
```

---

## Data Sources

All data was collected manually or sourced from publicly available datasets.

| File | Source | Notes |
|------|--------|-------|
| `teams.csv` | [Elo Ratings](https://eloratings.net/), [FIFA Rankings](https://inside.fifa.com/fifa-world-ranking/men) | Manually compiled - team_id assigned alphabetically |
| `squads.csv` | [ESPN Squad Lists](https://www.espn.com/soccer/story/_/id/48757621/2026-world-cup-squad-lists-players-announced-all-48-teams) | Player and club data for all 48 squads |
| `top5_leagues_clubs.csv` | Manually compiled from 2025-26 league standings | Premier League, La Liga, Bundesliga, Serie A, Ligue 1 |
| `matches.csv` | [Manually entered from FIFA's official schedule](https://www.fifa.com/en/tournaments/mens/worldcup/canadamexicousa2026/articles/match-schedule-fixtures-results-teams-stadiums) | 104 matches - 72 group stage, 32 knockout |
| `hist_results.csv` | [Kaggle - International football results 1872-2026](https://www.kaggle.com/datasets/martj42/international-football-results-from-1872-to-2017) | 49,437 international matches |
| `world_elo_ratings.csv` | [Elo Ratings](https://eloratings.net/) | 242 nations - used for opponent strength in form calculation |
| `third_place_bracket.csv` | [Wikipedia - 2026 FIFA World Cup knockout stage](https://en.wikipedia.org/wiki/2026_FIFA_World_Cup_knockout_stage) | All 495 FIFA third-place bracket combinations |

---

## Data Dictionary

### teams
| Column | Type | Description |
|--------|------|-------------|
| team_id | INT | Primary key, assigned alphabetically |
| country_name | VARCHAR | Team name - used as join key across tables |
| fifa_rank | INT | FIFA ranking at time of data collection |
| elo_rating | INT | Elo rating sourced from eloratings.net |
| confederation | VARCHAR | FIFA confederation (UEFA, CONMEBOL, etc.) |
| home_advantage | INT | 1 for USA, Canada, Mexico - 0 for all others |

### matches
| Column | Type | Description |
|--------|------|-------------|
| match_id | INT | Primary key - 1-72 group stage, 73-104 knockout |
| home_team_name | VARCHAR | Home team name |
| away_team_name | VARCHAR | Away team name |
| match_label | VARCHAR | Group label or knockout bracket position (e.g. "1A vs 3CDFGH") |

### squads
| Column | Type | Description |
|--------|------|-------------|
| team_id | INT | Foreign key to teams |
| player_name | VARCHAR | Player full name |
| club_name | VARCHAR | Club at time of squad announcement |

### hist_results
| Column | Type | Description |
|--------|------|-------------|
| date | DATE | Match date |
| home_team | VARCHAR | Home team name |
| away_team | VARCHAR | Away team name |
| home_score | VARCHAR | Home team score - VARCHAR to handle NA values |
| away_score | VARCHAR | Away team score - VARCHAR to handle NA values |
| tournament | VARCHAR | Tournament name - friendlies excluded from form calculation |

### world_elo_ratings
| Column | Type | Description |
|--------|------|-------------|
| country_name | VARCHAR | Country name |
| elo_rating | INT | Current Elo rating |

---

## Composite Score Model - Establishing the Power Ranking for the Tournament

Each team receives a composite score between 0 and 1, which drives all match outcome probabilities in the simulation. All factors are min-max normalized to 0-1 before weighting.

| Factor | Weight | Source | Built in |
|--------|--------|--------|----------|
| Elo rating | 55% | eloratings.net | `07_composite_score.sql` |
| Recent form | 15% | Last 20 competitive matches | `06_teams_recent_performance.sql` |
| Top 5 league concentration | 15% | % of squad in top 5 European leagues | `03_top5_concentration.sql` |
| Club cohesion | 10% | % of squad sharing a club with a teammate | `05_squad_cohesion.sql` |
| Home advantage | 5% | Host nations only | `04_home_advantage.sql` |

**Elo rating (55%)** - the largest weight, reflecting overall historical team strength. Sourced directly from `teams.csv`, normalized in `07_composite_score.sql`.

**Recent form (15%)** - built from each team's last 20 competitive matches (friendlies excluded). `06_teams_recent_performance.sql` calculates `team_recent_form`, joining match results to `world_elo_ratings` to get opponent strength, then `team_form_score` combines average points per game (50%), average goal difference capped at +/-1 (30%), and a win rate weighted by opponent Elo (20%) into a single 0-1 score.

**Top 5 league concentration (15%)** - the percentage of each squad playing in the Premier League, La Liga, Bundesliga, Serie A, or Ligue 1. `03_top5_concentration.sql` flags each player against a list of top 5 league clubs and aggregates to a team-level percentage in `team_top5_concentration`.

**Club cohesion (10%)** - the percentage of each squad that shares a club with at least one teammate on the same national team, as a proxy for tactical familiarity. `05_squad_cohesion.sql` self-joins the squads table to find these pairs and aggregates to `team_cohesion_score`.

**Home advantage (5%)** - a binary flag (1 or 0) applied only to USA, Canada, and Mexico as co-hosts. Added directly to `teams` in `04_home_advantage.sql`.

`07_composite_score.sql` brings all five components together: each is normalized to 0-1 using min-max scaling, then combined into the final `team_composite_score` view using the weights above.

FIFA ranking was considered as a sixth factor but excluded. FIFA adopted an Elo-based system in 2018, making it highly correlated with the Elo component and redundant.

---

## Simulation Design

- **Group stage**: 25% fixed draw probability. Remaining 75% split proportionally by composite score.
- **Knockout stage**: No draws. Win probability = team composite score / sum of both scores.
- **Third-place qualification**: Best 8 of 12 third-place teams advance, ranked by points. Bracket slot assignments follow the official FIFA 495-combination mapping table.
- **Tiebreakers**: Resolved randomly - goal difference is not tracked in this version.
- **Simulations**: 10,000 full tournament runs.

---

## Tools Used

| Tool | Purpose |
|------|---------|
| PostgreSQL | Data cleaning, transformation, and composite score views |
| R (dplyr, RPostgres) | Monte Carlo simulation engine and aggregation |
| Tableau Public | Dashboard visualizations |
| Claude (Anthropic) | Assisted with data collection and debugging throughout the project. All analytical decisions, model design, weight choices, and findings are my own. |

---

## Known Limitations

- Draw probability is fixed at 25% regardless of team parity for simplicity purposes. In reality this varies by matchup.
- Tiebreakers are resolved randomly, since goal difference not tracked in the simulation.
- Current Elo ratings used as proxy for historical opponent strength in form calculation.
- Teams playing mostly weak regional opposition (e.g. Haiti, Jordan) have inflated form scores relative to teams in stronger confederations.
- Third-place bracket combinations not in the FIFA 495-row table are handled with a random slot assignment fallback. This affects a small number of edge case combinations.
