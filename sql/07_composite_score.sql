-- ============================================================
-- 07_COMPOSITE_SCORE.SQL
-- ============================================================
-- Builds the final composite score for all 48 World Cup teams.
-- All factors are min-max normalized to 0-1 before weighting.
--
-- Weights:
--   Elo rating:             55% — historical strength, most reliable signal
--   Recent form:            15% — current momentum
--   Top 5 concentration:    15% — squad quality proxy
--   Club cohesion:          10% — tactical familiarity
--   Home advantage:          5% — host nation bonus (USA, Canada, Mexico only)
--
-- FIFA ranking excluded — highly correlated with Elo since FIFA
-- adopted an Elo-based system in 2018, adding it would double-count the signal.
-- ============================================================

-- Iteration 1: Initial query — norm_elo returned all zeros due to integer division
-- Fixed by casting to NUMERIC before dividing
SELECT
    t1.team_id,
    t1.country_name,
    ROUND((t1.elo_rating - MIN(t1.elo_rating) OVER())::NUMERIC / 
          (MAX(t1.elo_rating) OVER() - MIN(t1.elo_rating) OVER()), 4) AS norm_elo,
    ROUND((t2.form_score - MIN(t2.form_score) OVER()) / 
          (MAX(t2.form_score) OVER() - MIN(t2.form_score) OVER()), 4) AS norm_form_score,
    ROUND((t3.pct_top5 - MIN(t3.pct_top5) OVER()) / 
          (MAX(t3.pct_top5) OVER() - MIN(t3.pct_top5) OVER()), 4) AS norm_pct_top5,
    ROUND((t4.pct_cohesion - MIN(t4.pct_cohesion) OVER()) / 
          (MAX(t4.pct_cohesion) OVER() - MIN(t4.pct_cohesion) OVER()), 4) AS norm_pct_cohesion,
    t1.home_advantage
FROM teams AS t1
JOIN team_form_score AS t2 ON t1.team_id = t2.team_id
JOIN team_top5_concentration AS t3 ON t1.team_id = t3.team_id
JOIN team_cohesion_score AS t4 ON t1.team_id = t4.team_id
ORDER BY t1.team_id;

-- Final view with composite score
CREATE OR REPLACE VIEW team_composite_score AS
SELECT
    t1.team_id,
    t1.country_name,
    ROUND((t1.elo_rating - MIN(t1.elo_rating) OVER())::NUMERIC / 
          (MAX(t1.elo_rating) OVER() - MIN(t1.elo_rating) OVER()), 4) AS norm_elo,
    ROUND((t2.form_score - MIN(t2.form_score) OVER()) / 
          (MAX(t2.form_score) OVER() - MIN(t2.form_score) OVER()), 4) AS norm_form_score,
    ROUND((t3.pct_top5 - MIN(t3.pct_top5) OVER()) / 
          (MAX(t3.pct_top5) OVER() - MIN(t3.pct_top5) OVER()), 4) AS norm_pct_top5,
    ROUND((t4.pct_cohesion - MIN(t4.pct_cohesion) OVER()) / 
          (MAX(t4.pct_cohesion) OVER() - MIN(t4.pct_cohesion) OVER()), 4) AS norm_pct_cohesion,
    t1.home_advantage,
    ROUND(
        ((t1.elo_rating - MIN(t1.elo_rating) OVER())::NUMERIC / 
         (MAX(t1.elo_rating) OVER() - MIN(t1.elo_rating) OVER()) * 0.55) +
        ((t2.form_score - MIN(t2.form_score) OVER()) / 
         (MAX(t2.form_score) OVER() - MIN(t2.form_score) OVER()) * 0.15) +
        ((t3.pct_top5 - MIN(t3.pct_top5) OVER()) / 
         (MAX(t3.pct_top5) OVER() - MIN(t3.pct_top5) OVER()) * 0.15) +
        ((t4.pct_cohesion - MIN(t4.pct_cohesion) OVER()) / 
         (MAX(t4.pct_cohesion) OVER() - MIN(t4.pct_cohesion) OVER()) * 0.10) +
        (t1.home_advantage * 0.05) -- binary flag — 1 for host nations, 0 for all others
    , 4) AS composite_score
FROM teams AS t1
JOIN team_form_score AS t2 ON t1.team_id = t2.team_id
JOIN team_top5_concentration AS t3 ON t1.team_id = t3.team_id
JOIN team_cohesion_score AS t4 ON t1.team_id = t4.team_id
ORDER BY composite_score DESC;
