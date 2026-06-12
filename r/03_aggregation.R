library(dplyr)

## ============================================================
## 03_AGGREGATION.R
## ============================================================
## Aggregates raw simulation output from 02_simulation.R into
## analytical dataframes for export to PostgreSQL and Tableau.
## Must be run in the same R session as 02_simulation.R.
## ============================================================


## Championship probabilities per team
champion_probs <- data.frame(team_id = champions) %>%
  group_by(team_id) %>%
  summarise(championships = n()) %>%
  mutate(champion_pct = round(championships / n_simulations * 100, 2)) %>%  ## out of 10,000 runs
  left_join(team_scores %>% select(team_id, country_name, composite_score), by = "team_id") %>%
  arrange(desc(champion_pct))

## Advancement probabilities by round for each team
## round_order enforces Champion -> R32 sort, overrides default alphabetical
round_order <- c("Champion", "Final", "SF", "QF", "R16", "R32")

advancement_all <- bind_rows(advancement_tracker)  ## collapse list of 10,000 dataframes into one
advancement_probs <- advancement_all %>%
  group_by(team_id, round) %>%
  summarise(appearances = n(), .groups = "drop") %>%
  mutate(
    probability = round(appearances / n_simulations * 100, 2),  ## appearances as % of total simulations
    round = factor(round, levels = round_order)  ## enforces Champion -> R32 order
  ) %>%
  left_join(team_scores %>% select(team_id, country_name), by = "team_id") %>%
  select(team_id, country_name, round, appearances, probability) %>%
  arrange(team_id, round)

## Expected round reached per team
## weighted average of round values by probability — single number summarising tournament trajectory
## Round values: R32=1, R16=2, QF=3, SF=4, Final=5, Champion=6
round_values <- c("R32" = 1, "R16" = 2, "QF" = 3, "SF" = 4, "Final" = 5, "Champion" = 6)

expected_round <- advancement_probs %>%
  mutate(round_value = round_values[as.character(round)]) %>%  ## as.character needed since round is now a factor
  group_by(team_id, country_name) %>%
  summarise(
    expected_round = round(sum(round_value * probability / 100), 3),  ## probability/100 converts pct to proportion
    .groups = "drop"
  ) %>%
  arrange(desc(expected_round))

## Group stage stats — qualification rate and group winner rate by team
group_all <- bind_rows(group_tracker)
group_stats <- group_all %>%
  group_by(team_id) %>%
  summarise(
    avg_points        = round(mean(points), 2),
    group_win_pct     = round(mean(group_rank == 1) * 100, 2),  ## % of sims where team finished 1st
    qualification_pct = round(mean(group_rank <= 2) * 100, 2),  ## % of sims where team finished top 2
    .groups = "drop"
  ) %>%
  left_join(team_scores %>% select(team_id, country_name, composite_score), by = "team_id") %>%
  arrange(desc(qualification_pct))

## Third place cutoff points distribution
## Answers: "How safe is 4 points for a third place team?"
third_place_all <- bind_rows(third_place_points_tracker)
third_place_cutoff <- third_place_all %>%
  summarise(
    avg_cutoff   = round(mean(cutoff_points), 2),
    pct_4_points = round(mean(cutoff_points <= 4) * 100, 2),  ## % of sims where 4 pts was enough to qualify
    pct_3_points = round(mean(cutoff_points <= 3) * 100, 2),  ## % of sims where 3 pts was enough to qualify
    min_cutoff   = min(cutoff_points),  ## lowest points that ever qualified across all sims
    max_cutoff   = max(cutoff_points)
  )

## Group of death — measures how closely the top 3 teams in each group
## are matched in strength. A small gap between the strongest (max_composite)
## and 3rd strongest (third_composite) team means all 3 are competing on
## roughly even footing — multiple genuinely strong teams fighting for 2 spots.
## A large gap means one dominant team plus weaker competition (e.g. Spain's group).
##
## Known limitation: this metric alone doesn't account for absolute strength —
## a group where all 3 top teams are weak but evenly matched would also produce
## a small gap. Cross-reference with avg_top3 (overall top-3 strength) when
## interpreting results.
group_of_death <- team_scores %>%
  left_join(
    matches %>%
      filter(match_id <= 72) %>%
      select(home_team_id, match_label) %>%
      rename(team_id = home_team_id, group_label = match_label) %>%
      bind_rows(
        matches %>%
          filter(match_id <= 72) %>%
          select(away_team_id, match_label) %>%
          rename(team_id = away_team_id, group_label = match_label)
      ) %>%
      distinct(team_id, .keep_all = TRUE),
    by = "team_id"
  ) %>%
  group_by(group_label) %>%
  summarise(
    avg_composite = round(mean(composite_score), 4),
    max_composite = round(max(composite_score), 4),
    third_composite = round(sort(composite_score, decreasing = TRUE)[3], 4),  ## 3rd strongest team — defines top-3 cluster
    .groups = "drop"
  ) %>%
  mutate(
    top1_top3_gap = round(max_composite - third_composite, 4)  ## small gap = top 3 closely matched
  ) %>%
  arrange(top1_top3_gap)  ## ascending — smallest gap first = most competitive

## Confederation performance — advancement rates aggregated by confederation
## round already factored in advancement_probs — sorts correctly here
confederation_performance <- advancement_probs %>%
  left_join(teams %>% select(team_id, confederation), by = "team_id") %>%
  group_by(confederation, round) %>%
  summarise(
    avg_probability = round(mean(probability), 2),  ## avg % of teams from this confederation reaching each round
    .groups = "drop"
  ) %>%
  arrange(confederation, round)

## Hardest path to champion — top 10 teams by champion_pct only
## avg opponent strength = mean composite score of all knockout opponents beaten
champion_path_all <- bind_rows(champion_path_tracker)
top10_team_ids <- champion_probs %>% slice(1:10) %>% pull(team_id)  ## restrict to top 10 most likely champions

hardest_path <- champion_path_all %>%
  filter(champion_id %in% top10_team_ids) %>%
  group_by(champion_id) %>%
  summarise(
    simulations_won       = n(),
    avg_opponent_strength = round(mean(avg_opponent_strength, na.rm = TRUE), 4),  ## na.rm handles edge cases where path wasn't fully resolved
    .groups = "drop"
  ) %>%
  left_join(team_scores %>% select(team_id, country_name, composite_score),
            by = c("champion_id" = "team_id")) %>%
  arrange(desc(avg_opponent_strength))

## Print summaries
cat("\nTop 10 champions:\n")
print(head(champion_probs, 10))

cat("\nExpected round reached:\n")
print(head(expected_round, 10))

cat("\nGroup of death:\n")
print(group_of_death)

cat("\nThird place cutoff:\n")
print(third_place_cutoff)

cat("\nConfederation performance:\n")
print(confederation_performance)

cat("\nHardest path to champion:\n")
print(hardest_path)