-- ============================================================
-- 05_SQUAD_COHESION.SQL
-- ============================================================
-- Flags players who share a club with at least one teammate
-- on the same national team. Used as a proxy for tactical
-- familiarity and club chemistry within the squad.
-- ============================================================

-- Player level cohesion flag using self-join on squads
-- counts teammates at the same club within the same national team
SELECT s1.team_id, s1.player_name, s1.club_name,
    CASE 
        WHEN COUNT(s2.player_name) > 0 THEN 1
        ELSE 0
    END AS same_club_teammate
FROM squads AS s1
LEFT JOIN squads AS s2 
    ON s1.team_id = s2.team_id  -- same national team
    AND s1.club_name = s2.club_name  -- same club
    AND s1.player_name != s2.player_name  -- exclude self-join
GROUP BY s1.team_id, s1.player_name, s1.club_name
ORDER BY s1.team_id, s1.club_name;

-- Player level cohesion view
CREATE OR REPLACE VIEW squad_cohesion AS
SELECT s1.team_id, s1.player_name, s1.club_name,
    CASE 
        WHEN COUNT(s2.player_name) > 0 THEN 1
        ELSE 0
    END AS same_club_teammate
FROM squads AS s1
LEFT JOIN squads AS s2 
    ON s1.team_id = s2.team_id
    AND s1.club_name = s2.club_name
    AND s1.player_name != s2.player_name
GROUP BY s1.team_id, s1.player_name, s1.club_name
ORDER BY s1.team_id, s1.club_name;

-- Team level cohesion score aggregated from player level
CREATE OR REPLACE VIEW team_cohesion_score AS
SELECT
    sc.team_id,
    t.country_name,
    ROUND((SUM(same_club_teammate)::NUMERIC / COUNT(*)) * 100, 2) AS pct_cohesion -- % of squad sharing a club with a teammate
FROM squad_cohesion sc
JOIN teams t ON t.team_id = sc.team_id
GROUP BY sc.team_id, t.country_name
ORDER BY pct_cohesion DESC;