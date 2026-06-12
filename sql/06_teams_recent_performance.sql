-- ============================================================
-- 06_TEAMS_RECENT_PERFORMANCE.SQL
-- ============================================================
-- Builds team_recent_form and team_form_score views using
-- historical match results from hist_results.
-- Covers the last 20 competitive matches per team,
-- excluding friendlies and any matches on or after June 11 2026.
-- ============================================================

-- Exploration Queries
SELECT * FROM hist_results LIMIT 10;

-- See all distinct tournaments to understand what to filter
SELECT DISTINCT tournament
FROM hist_results
ORDER BY tournament ASC;

-- Sample recent matches for Argentina and Spain
SELECT *
FROM hist_results
WHERE home_team = 'Argentina' OR away_team = 'Argentina'
ORDER BY date DESC
LIMIT 20;

SELECT *
FROM hist_results
WHERE home_team = 'Spain' OR away_team = 'Spain'
ORDER BY date DESC
LIMIT 20;

/* Findings: 
- Dataset includes upcoming World Cup matches — filter out dates >= June 11th, 2026
- Must exclude 'Friendly' tournament type — only competitive matches used for form */

-- Initial attempt — returned 860 rows, expected 960 (48 teams x 20 matches)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY team ORDER BY date DESC) AS row_num
    FROM (
        SELECT date, home_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
        UNION ALL
        SELECT date, away_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
    ) AS all_matches
    WHERE team IN (SELECT country_name FROM teams)
) AS ranked_matches
WHERE row_num <= 20
ORDER BY team, date DESC;
-- Findings: only returned 860 matches, expected 960 matches. Either caused by missing match data, or, mismatches between team names across tables

-- Count matches per team to confirm which teams are missing
SELECT team, COUNT(*) as match_count
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY team ORDER BY date DESC) AS row_num
    FROM (
        SELECT date, home_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
        UNION ALL
        SELECT date, away_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
    ) AS all_matches
    WHERE team IN (SELECT country_name FROM teams)
) AS ranked_matches
WHERE row_num <= 20
GROUP BY team
ORDER BY match_count ASC;
-- Findings: Returned 43 teams, with each team having 20 games. This means that there are 5 teams that had mismatches in naming conventions between tables.

-- Identify the 5 missing teams
SELECT country_name
FROM teams
WHERE country_name NOT IN (
    SELECT DISTINCT team
    FROM (
        SELECT home_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
        UNION ALL
        SELECT away_team AS team FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
    ) AS all_matches
    WHERE team IN (SELECT country_name FROM teams)
);

-- Confirm Cape Verde naming in hist_results
SELECT DISTINCT home_team 
FROM hist_results 
WHERE home_team ILIKE '%verde%' OR home_team ILIKE '%cabo%';

/* Findings: 5 teams were missing due to naming mismatches between teams and hist_results tables
- Congo DR -> DR Congo
- Czechia -> Czech Republic
- Türkiye -> Turkey
- USA -> United States
- Cabo Verde -> Cape Verde
- Resolution: used CASE WHEN in the subquery to map team names on the fly instead of updating teams table
  to maintain consistency with match_schedule view which was already created previously */

-- ============================================================
-- FINAL VIEW: team_recent_form
-- ============================================================
-- Includes full match details: date, opponent, scores, goal difference, result, team Elo, and opponent Elo.
-- team_elo and opponent_elo sourced from world_elo_ratings (242 nations), providing much better
-- coverage than the 48-team teams table.
-- Note: current Elo used as proxy for historical opponent strength — acknowledged limitation.
-- Elo changes over time but is relatively stable over a 2-3 year window.
-- ============================================================
CREATE OR REPLACE VIEW team_recent_form AS
SELECT 
    f.team,
    f.date,
    f.opponent,
    f.home_score,
    f.away_score,
    CAST(f.home_score AS INT) - CAST(f.away_score AS INT) AS goal_difference, -- CAST needed — scores stored as VARCHAR to handle NA values
    CASE
        WHEN CAST(f.home_score AS INT) > CAST(f.away_score AS INT) THEN 'W'
        WHEN CAST(f.home_score AS INT) = CAST(f.away_score AS INT) THEN 'D'
        ELSE 'L'
    END AS result,
    wt.elo_rating AS team_elo,
    wo.elo_rating AS opponent_elo, -- NULL for opponents not in world_elo_ratings
    f.row_num
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY team ORDER BY date DESC) AS row_num
    FROM (
        -- each team appears as both home and away — UNION both perspectives
        -- scores are swapped for away team so home_score always = team's score
        SELECT date, home_team AS team, away_team AS opponent,
               home_score, away_score
        FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
        UNION ALL
        SELECT date, away_team AS team, home_team AS opponent,
               away_score AS home_score, home_score AS away_score -- swap scores for away perspective
        FROM hist_results
        WHERE tournament != 'Friendly' AND date < '2026-06-11'
    ) AS all_matches
    WHERE team IN (
        -- CASE WHEN maps teams table names to hist_results names on the fly
        -- avoids updating teams table which would break match_schedule view
        SELECT CASE country_name
            WHEN 'Congo DR' THEN 'DR Congo'
            WHEN 'Czechia' THEN 'Czech Republic'
            WHEN 'Türkiye' THEN 'Turkey'
            WHEN 'USA' THEN 'United States'
            WHEN 'Cabo Verde' THEN 'Cape Verde'
            ELSE country_name
        END
        FROM teams
    )
) AS f
LEFT JOIN world_elo_ratings wt ON wt.country_name = f.team
LEFT JOIN world_elo_ratings wo ON wo.country_name = f.opponent
WHERE row_num <= 20
ORDER BY team, date DESC;

-- ============================================================
-- TEAM FORM SCORE
-- ============================================================
-- Aggregates each team's last 20 competitive matches into a
-- single form_score for use in the composite score model.
--
-- Three components weighted as follows:
--   avg_points (0.5): points per game, normalized to 0-1
--   avg_goal_diff (0.3): goal difference per game, capped at ±1
--   weighted_win_rate (0.2): win rate adjusted for opponent Elo strength
--
-- form_score = (avg_points / 3.0 * 0.5)
--            + (capped_avg_goal_diff * 0.3)
--            + (weighted_win_rate * 0.2)
--
-- Known limitations:
-- - Current Elo used as proxy for historical opponent strength
-- - Teams playing mostly weak regional opposition (Haiti, Jordan) have
--   inflated form scores relative to stronger confederations
-- - 20 match window captures ~2-3 years of recent form
-- ============================================================
CREATE OR REPLACE VIEW team_form_score AS
SELECT
    t.team_id,
    f.team,
    COUNT(*) AS matches_played,
    ROUND(AVG(CASE result WHEN 'W' THEN 3 WHEN 'D' THEN 1 ELSE 0 END), 2) AS avg_points,
    ROUND(AVG(CAST(goal_difference AS NUMERIC)), 2) AS avg_goal_diff,
    ROUND(AVG(
        CASE 
            WHEN result = 'W' AND opponent_elo IS NOT NULL 
                THEN LEAST(CAST(opponent_elo AS NUMERIC) / 2000.0, 1.0) -- capped at 1.0 to keep within 0-1 scale
            WHEN result = 'W' AND opponent_elo IS NULL 
                THEN 0.7 -- mid-tier fallback for opponents not in world_elo_ratings
            ELSE 0
        END
    ), 4) AS weighted_win_rate,
    ROUND(
        (AVG(CASE result WHEN 'W' THEN 3 WHEN 'D' THEN 1 ELSE 0 END) / 3.0 * 0.5) +
        (LEAST(GREATEST(AVG(CAST(goal_difference AS NUMERIC)) / 5.0, -1.0), 1.0) * 0.3) + -- GREATEST/LEAST caps between -1 and 1
        (AVG(
            CASE 
                WHEN result = 'W' AND opponent_elo IS NOT NULL 
                    THEN LEAST(CAST(opponent_elo AS NUMERIC) / 2000.0, 1.0)
                WHEN result = 'W' AND opponent_elo IS NULL 
                    THEN 0.7
                ELSE 0
            END
        ) * 0.2)
    , 4) AS form_score
FROM team_recent_form f
-- reverse CASE WHEN to join back to teams table using teams naming convention
LEFT JOIN teams t ON t.country_name = CASE f.team
    WHEN 'DR Congo' THEN 'Congo DR'
    WHEN 'Czech Republic' THEN 'Czechia'
    WHEN 'Turkey' THEN 'Türkiye'
    WHEN 'United States' THEN 'USA'
    WHEN 'Cape Verde' THEN 'Cabo Verde'
    ELSE f.team
END
WHERE home_score != 'NA' AND away_score != 'NA' -- exclude matches with missing score data
GROUP BY t.team_id, f.team
ORDER BY form_score DESC;