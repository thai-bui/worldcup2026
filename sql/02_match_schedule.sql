-- ============================================================
-- 02_MATCH_SCHEDULE.SQL
-- ============================================================
-- Joins team_ids from teams table into the matches table.
-- Knockout matches (match_id > 72) have NULL team_ids by design —
-- participants are determined dynamically during simulation.
-- ============================================================

-- Exploration Queries
SELECT * FROM teams LIMIT 10;
SELECT * FROM matches LIMIT 10;

-- Match team_ids to teams in matches table
SELECT m.match_id, t1.team_id AS home_team_id, m.home_team_name, t2.team_id AS away_team_id, m.away_team_name, m.match_label
FROM matches AS m
LEFT JOIN teams AS t1 ON t1.country_name = m.home_team_name
LEFT JOIN teams AS t2 ON t2.country_name = m.away_team_name
ORDER BY m.match_id;

-- Check for NULL team_ids in group stage matches only — knockout NULLs are expected
SELECT * FROM (
    SELECT m.match_id, t1.team_id AS home_team_id, m.home_team_name, t2.team_id AS away_team_id, m.away_team_name, m.match_label
    FROM matches AS m
    LEFT JOIN teams AS t1 ON t1.country_name = m.home_team_name
    LEFT JOIN teams AS t2 ON t2.country_name = m.away_team_name
    ORDER BY m.match_id)
WHERE match_label ILIKE '%Group%' AND (home_team_id IS NULL OR away_team_id IS NULL);
-- Findings: Cabo Verde spelled differently between matches and teams tables

-- Verify Cabo Verde's name in teams table
-- SELECT * FROM teams WHERE country_name ILIKE '%cabo%' OR country_name ILIKE '%verde%' OR country_name ILIKE '%cape%';
-- Findings: stored as 'Cape Verde' in teams, 'Cabo Verde' in matches — updated teams to match international convention
UPDATE teams
SET country_name = 'Cabo Verde'
WHERE country_name = 'Cape Verde'

CREATE OR REPLACE VIEW match_schedule AS
SELECT 
    m.match_id,
    t1.team_id AS home_team_id,
    m.home_team_name,
    t2.team_id AS away_team_id,
    m.away_team_name,
    m.match_label
FROM matches AS m
LEFT JOIN teams AS t1 ON t1.country_name = m.home_team_name
LEFT JOIN teams AS t2 ON t2.country_name = m.away_team_name
ORDER BY m.match_id;