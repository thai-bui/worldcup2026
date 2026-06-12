-- ============================================================
-- 03_TOP5_CONCENTRATION.SQL
-- ============================================================
-- Calculates the percentage of each squad playing in a top 5
-- European league (Premier League, La Liga, Bundesliga, Serie A, Ligue 1).
-- Higher concentration = stronger squad quality assumption.
-- ============================================================

-- Exploration Queries
SELECT * FROM squads LIMIT 10;
SELECT * FROM top5_leagues_clubs LIMIT 10;

SELECT s.team_id, s.player_name, club_name,
    CASE 
        WHEN s.club_name = t.club THEN 1
        ELSE 0
    END AS in_top5_league
FROM squads AS s
LEFT JOIN top5_leagues_clubs AS t ON s.club_name = t.club;

-- Verify logic for a few players
SELECT s.team_id, s.player_name, club_name,
    CASE 
        WHEN s.club_name = t.club THEN 1
        ELSE 0
    END AS in_top5_league
FROM squads AS s
LEFT JOIN top5_leagues_clubs AS t ON s.club_name = t.club
WHERE s.player_name IN ('Lionel Messi', 'Bruno Fernandes');

-- Check for clubs not flagged as top 5 — catches naming mismatches between squads and top5_leagues_clubs
SELECT DISTINCT s.club_name
FROM squads AS s
LEFT JOIN top5_leagues_clubs AS t ON s.club_name = t.club
WHERE t.club IS NULL
ORDER BY s.club_name;
/* Identified naming mismatches between squads.club_name and top5_leagues_clubs.club using AI assistance (Claude)
to cross-reference club names against known top 5 league clubs, given the volume of 487 unique clubs across 48 squads. */

UPDATE squads SET club_name = 'Brighton & Hove Albion' WHERE club_name = 'Brighton';
UPDATE squads SET club_name = 'Newcastle United' WHERE club_name = 'Newcastle';
UPDATE squads SET club_name = 'VfB Stuttgart' WHERE club_name = 'Stuttgart';
UPDATE squads SET club_name = 'TSG Hoffenheim' WHERE club_name = 'Hoffenheim';
UPDATE squads SET club_name = 'Inter Milan' WHERE club_name = 'Internazionale';
UPDATE squads SET club_name = 'Rennes' WHERE club_name = 'Stade Rennais';
UPDATE squads SET club_name = 'Monaco' WHERE club_name = 'AS Monaco';
/* Mismatches identified and corrected:
- 'Brighton'       -> 'Brighton & Hove Albion'  (Premier League)
- 'Newcastle'      -> 'Newcastle United'         (Premier League)
- 'Stuttgart'      -> 'VfB Stuttgart'            (Bundesliga)
- 'Hoffenheim'     -> 'TSG Hoffenheim'           (Bundesliga)
- 'Internazionale' -> 'Inter Milan'              (Serie A)
- 'Stade Rennais'  -> 'Rennes'                   (Ligue 1)
- 'AS Monaco'      -> 'Monaco'                   (Ligue 1) */

-- Player level top 5 flag
CREATE OR REPLACE VIEW squad_top5 AS
SELECT s.team_id, s.player_name, s.club_name,
    CASE 
        WHEN t.club IS NOT NULL THEN 1 -- NULL means club not in top 5 leagues list
        ELSE 0
    END AS in_top5_league
FROM squads AS s
LEFT JOIN top5_leagues_clubs AS t ON s.club_name = t.club;

-- Team level top 5 concentration aggregated from player level
CREATE OR REPLACE VIEW team_top5_concentration AS
SELECT 
    s.team_id,
    t.country_name,
    ROUND((SUM(s.in_top5_league)::NUMERIC / COUNT(*)) * 100, 2) AS pct_top5 -- % of squad in top 5 leagues
FROM squad_top5 s
JOIN teams t ON s.team_id = t.team_id
GROUP BY s.team_id, t.country_name
ORDER BY pct_top5 DESC;