library(dplyr)

## ============================================================
## 02_SIMULATION.R
## Monte Carlo Simulation Script
## ============================================================
## Goal: Simulate the full 2026 World Cup tournament using
## composite team scores built in SQL. Runs a Monte Carlo
## simulation to generate championship and advancement probabilities.
##
## Functions built in this script:
##   simulate_match(): simulates a single match outcome
##   simulate_group_stage(): simulates all 72 group stage matches
##   calculate_standings(): calculates group standings and rankings
##   determine_qualifiers(): selects top 2 + best 8 third-place teams
##   get_third_place_slots(): maps third-place teams to R32 bracket slots
##   resolve_knockout_participants(): builds position lookup for knockout bracket
##   resolve_match_label(): parses match labels to team_ids
##   simulate_knockout_stage(): simulates all knockout rounds
##   simulate_tournament(): wraps full tournament into one function
## ============================================================


## ============================================================
## MATCH SIMULATION ASSUMPTIONS
## ============================================================
## Win probabilities are derived from each team's composite score.
## A draw probability of 25% is applied for group stage matches.
## The remaining 75% is split proportionally based on composite scores.
##
## Iteration 1: Basic version used for initial testing with
## hardcoded composite scores (Spain vs Congo DR).
## Iteration 2: Integrated with full composite score model from SQL.
##
## Known limitation: draw probability is set at 25% regardless
## of match context. In reality draw probability varies with
## the difference in parity between teams. This limitation is acknowledged.
## ============================================================

simulate_match <- function(home_score, away_score) {
  
  total <- home_score + away_score
  home_win_prob <- home_score / total  ## share of combined strength
  away_win_prob <- away_score / total
  
  draw_prob <- 0.25  ## fixed — no data to calibrate dynamically
  home_win_prob <- home_win_prob * (1 - draw_prob)  ## scales down to leave room for draw
  away_win_prob <- away_win_prob * (1 - draw_prob)
  
  outcome <- sample(
    c("home", "draw", "away"),
    size = 1,
    prob = c(home_win_prob, draw_prob, away_win_prob)  ## weighted random draw
  )
  
  return(outcome)
}

## Initial test - verified randomness across 100 simulations
## Spain (0.9058) vs Congo DR (0.3636): ~52% home, 28% draw, 20% away
## results <- replicate(100, simulate_match(0.9058, 0.3636))
## table(results)


## ============================================================
## GROUP STAGE SIMULATION
## ============================================================
## This section simulates all 72 group stage matches using the match schedule
## from PostgreSQL. Each match pulls composite scores by team_id.
## ============================================================

simulate_group_stage <- function(matches, team_scores) {
  
  group_matches <- matches %>% filter(match_id <= 72)  ## match_ids 73+ are knockout game
  
  results <- data.frame(
    match_id = integer(),
    home_team_id = integer(),
    away_team_id = integer(),
    outcome = character(),
    stringsAsFactors = FALSE  ## prevents factor conversion which breaks rbind
  )
  
  for (i in 1:nrow(group_matches)) {
    match <- group_matches[i, ]
    
    home_score <- team_scores$composite_score[team_scores$team_id == match$home_team_id]
    away_score <- team_scores$composite_score[team_scores$team_id == match$away_team_id]
    
    outcome <- simulate_match(home_score, away_score)
    
    results <- rbind(results, data.frame(
      match_id = match$match_id,
      home_team_id = match$home_team_id,
      away_team_id = match$away_team_id,
      outcome = outcome,
      stringsAsFactors = FALSE
    ))
  }
  
  return(results)
}


## ============================================================
## STANDINGS CALCULATION
## ============================================================
## This section calculates points, wins, draws, losses for all 48 teams for 
## the group stage.
## Teams are ranked within their group using points.
## Tiebreaker: random (ties.method = "random") since goal
## difference is not a factor in this project.
##
## Iteration 1: Basic standings without group labels.
## Iteration 2: Added group assignments from matches table
## and group_rank to support qualifier determination.
##
## Known limitation: tiebreakers are resolved randomly rather than by goal
## difference. Over 10,000 simulations this averages out and does not
## significantly affect results.
## ============================================================

calculate_standings <- function(group_results, matches, team_scores) {
  
  ## Pull group assignments from match schedule
  ## each team appears as both home and away — union both sides to get full list
  group_assignments <- matches %>%
    filter(match_id <= 72) %>%
    select(home_team_id, match_label) %>%
    rename(team_id = home_team_id, group_label = match_label) %>%
    bind_rows(
      matches %>%
        filter(match_id <= 72) %>%
        select(away_team_id, match_label) %>%
        rename(team_id = away_team_id, group_label = match_label)
    ) %>%
    distinct(team_id, .keep_all = TRUE)  ## one row per team, keeps first occurrence
  
  standings <- team_scores %>%
    select(team_id, country_name) %>%
    left_join(group_assignments, by = "team_id") %>%
    mutate(
      played = 0,
      wins = 0,
      draws = 0,
      losses = 0,
      points = 0
    )
  
  for (i in 1:nrow(group_results)) {
    result <- group_results[i, ]
    
    if (result$outcome == "home") {
      standings$wins[standings$team_id == result$home_team_id] <-
        standings$wins[standings$team_id == result$home_team_id] + 1
      standings$losses[standings$team_id == result$away_team_id] <-
        standings$losses[standings$team_id == result$away_team_id] + 1
    } else if (result$outcome == "away") {
      standings$wins[standings$team_id == result$away_team_id] <-
        standings$wins[standings$team_id == result$away_team_id] + 1
      standings$losses[standings$team_id == result$home_team_id] <-
        standings$losses[standings$team_id == result$home_team_id] + 1
    } else {  ## draw — both teams get a draw
      standings$draws[standings$team_id == result$home_team_id] <-
        standings$draws[standings$team_id == result$home_team_id] + 1
      standings$draws[standings$team_id == result$away_team_id] <-
        standings$draws[standings$team_id == result$away_team_id] + 1
    }
    
    standings$played[standings$team_id == result$home_team_id] <-
      standings$played[standings$team_id == result$home_team_id] + 1
    standings$played[standings$team_id == result$away_team_id] <-
      standings$played[standings$team_id == result$away_team_id] + 1
  }
  
  standings <- standings %>%
    mutate(points = wins * 3 + draws * 1) %>%
    group_by(group_label) %>%
    mutate(group_rank = rank(-points, ties.method = "random")) %>%  ## random tiebreaker — GD not tracked
    ungroup()
  
  return(standings)
}


## ============================================================
## QUALIFIER DETERMINATION
## ============================================================
## Top 2 from each of 12 groups = 24 teams qualify automatically.
## Best 8 third-place teams (ranked by points) = 8 more qualify.
## Total: 32 teams advance to the Round of 32.
##
## Known limitation: third-place tiebreakers are resolved by points only.
## FIFA rules use goal difference, goals scored, and fair play points as
## further tiebreakers. Simplified here due to absence of goal scoring
## data in the simulation.
## ============================================================

determine_qualifiers <- function(standings) {
  
  top2 <- standings %>%
    filter(group_rank <= 2) %>%
    select(team_id, country_name, group_label, group_rank, points)
  
  third_place <- standings %>%
    filter(group_rank == 3) %>%
    arrange(desc(points)) %>%
    slice(1:8) %>%  ## best 8 of 12 third-place teams advance
    select(team_id, country_name, group_label, group_rank, points)
  
  qualifiers <- bind_rows(top2, third_place) %>%
    arrange(group_label, group_rank)
  
  return(qualifiers)
}


## ============================================================
## THIRD PLACE BRACKET SLOT MAPPING
## ============================================================
## FIFA has 495 predetermined bracket combinations that determine
## which R32 slot each third-place team fills based on which 8
## of the 12 groups produced qualifying third-place teams.
## The full mapping table was loaded into PostgreSQL as third_place_bracket
## and pulled into R in 01_data_load.R as third_place_combinations.
##
## This function:
##   1. Identifies the 8 qualifying third-place teams
##   2. Builds the group combination key (e.g. "ABCDEFGH")
##   3. Looks up the correct row in the bracket mapping table
##   4. Returns slot assignments (which slot each team fills)
## ============================================================

get_third_place_slots <- function(standings, third_place_combinations) {
  
  third_place_teams <- standings %>%
    filter(group_rank == 3) %>%
    arrange(desc(points)) %>%
    slice(1:8)
  
  advancing_groups <- third_place_teams %>%
    mutate(group_letter = gsub("Group ", "", group_label)) %>%
    pull(group_letter) %>%
    sort() %>%  ## must be sorted alphabetically to match bracket table keys
    paste(collapse = "")
  
  bracket_row <- third_place_combinations %>% 
    filter(groups_advancing == advancing_groups)
  
  if (nrow(bracket_row) == 0) {
    stop(paste("No bracket mapping found for groups:", advancing_groups))
  }
  
  slot_mapping <- data.frame(
    slot = c("slot_1a", "slot_1b", "slot_1d", "slot_1e",
             "slot_1g", "slot_1i", "slot_1k", "slot_1l"),  ## slots c and f have no third-place opponents
    group_assignment = c(
      bracket_row$slot_1a, bracket_row$slot_1b, bracket_row$slot_1d,
      bracket_row$slot_1e, bracket_row$slot_1g, bracket_row$slot_1i,
      bracket_row$slot_1k, bracket_row$slot_1l
    ),
    stringsAsFactors = FALSE
  )
  
  slot_mapping <- slot_mapping %>%
    mutate(
      group_label = paste0("Group ", gsub("3", "", group_assignment)),  ## "3E" -> "Group E"
      team_id = sapply(group_label, function(g) {
        third_place_teams$team_id[third_place_teams$group_label == g]
      })
    )
  
  return(slot_mapping)
}


## ============================================================
## KNOCKOUT PARTICIPANT LOOKUP
## ============================================================
## Builds a position -> team_id lookup table for the knockout
## bracket. Keys are in the format "1A", "2B", "3C" etc.
## Third-place slot keys use the group letter of the team they
## face (e.g. "3E" = third-place team assigned to face the Group E winner).
## The gsub on the slot column converts "slot_1a" format to "3A" to match
## the position keys used in resolve_match_label().
## Only includes 1st, 2nd, and qualifying 3rd place teams.
## 4th place teams are excluded.
## ============================================================

resolve_knockout_participants <- function(standings, slots) {
  
  position_lookup <- standings %>%
    filter(group_rank <= 2) %>%  ## 4th place teams excluded here
    mutate(
      group_letter = gsub("Group ", "", group_label),
      position_key = paste0(group_rank, group_letter)  ## e.g. "1A", "2B"
    ) %>%
    select(position_key, team_id)
  
  third_place_lookup <- slots %>%
    mutate(
      position_key = toupper(gsub("slot_1", "3", slot))  ## "slot_1a" -> "3A"
    ) %>%
    select(position_key, team_id)
  
  full_lookup <- bind_rows(position_lookup, third_place_lookup)  ## 32 teams total
  
  return(full_lookup)
}


## ============================================================
## MATCH LABEL RESOLVER
## ============================================================
## Parses R32 match labels from the match schedule and resolves
## them to team_ids using the position lookup.
##
## Match label formats:
##   "2A vs 2B"      - 2nd place Group A vs 2nd place Group B
##   "1E vs 3ABCDF"  - 1st place Group E vs third-place slot
##
## Important: "3ABCDF" in a match label does NOT mean the
## third-place team from Groups A, B, C, D, or F. It indicates
## which groups were eligible for that slot per FIFA rules.
## The actual team assigned to that slot is stored in the lookup
## under key "3E" (the slot facing the Group E winner).
## We extract the group letter from the opponent key to find
## the correct third-place team.
## ============================================================

resolve_match_label <- function(label, lookup) {
  
  parts <- strsplit(label, " vs ")[[1]]
  home_key <- trimws(parts[1])
  away_key <- trimws(parts[2])
  
  get_team <- function(key, lookup) {
    match <- lookup$team_id[lookup$position_key == key]
    if (length(match) > 0) return(match[1])
    return(NA)
  }
  
  home_id <- get_team(home_key, lookup)
  away_id <- get_team(away_key, lookup)
  
  if (grepl("^3[A-Z]{2,}", away_key)) {  ## away team is a third-place slot e.g. "3ABCDF"
    third_key <- paste0("3", substring(home_key, 2))  ## extract group letter from home key e.g. "1E" -> "3E"
    away_id <- get_team(third_key, lookup)
  }
  
  if (grepl("^3[A-Z]{2,}", home_key)) {  ## same logic when home team is the third-place slot
    third_key <- paste0("3", substring(away_key, 2))
    home_id <- get_team(third_key, lookup)
  }
  
  return(list(home_id = home_id, away_id = away_id))
}


## ============================================================
## KNOCKOUT STAGE SIMULATION
## ============================================================
## Simulates all knockout rounds from Round of 32 to Final.
## There are no draws in the knockout stage - each match produces one winner.
## Win probability = (team composite score) / (sum of both scores).
##
## Iteration 1: Single loop — failed because later rounds
## (R16, QF, SF) depend on earlier round winners being resolved
## first. Processing all W vs W matches in one pass caused
## missing participants errors.
##
## Iteration 2 (final): Two-loop approach:
##   Loop 1 — resolves all R32 matches (group position labels)
##   Loop 2 — resolves W vs W matches in match_id order,
##             ensuring each round is resolved before the next
##
## match_participants tracks both teams in each match to support
## champion path analysis in the aggregation script.
## ============================================================

simulate_knockout_stage <- function(r32_matches, lookup, team_scores) {
  
  match_winners <- list()
  match_participants <- list()  ## both teams per match — needed for path analysis
  
  ## Loop 1: Resolve R32 matches using group position labels
  for (i in 1:nrow(r32_matches)) {
    match <- r32_matches[i, ]
    label <- match$match_label
    
    if (grepl("^W|^RU", label)) next  ## skip W vs W and third-place match — handled separately
    
    participants <- resolve_match_label(label, lookup)
    home_id <- participants$home_id
    away_id <- participants$away_id
    
    if (is.na(home_id) || is.na(away_id)) next  ## skip if label couldn't be resolved
    
    home_score <- team_scores$composite_score[team_scores$team_id == home_id]
    away_score <- team_scores$composite_score[team_scores$team_id == away_id]
    
    total <- home_score + away_score
    home_win_prob <- home_score / total  ## no draw in knockout — full probability split
    winner_id <- ifelse(runif(1) < home_win_prob, home_id, away_id)  ## single random draw
    match_winners[[as.character(match$match_id)]] <- winner_id
    match_participants[[as.character(match$match_id)]] <- c(home_id, away_id)
  }
  
  ## Loop 2: Resolve W vs W matches in order (R16 -> QF -> SF -> Final)
  ## must be sorted by match_id — later rounds depend on earlier round winners
  w_matches <- r32_matches %>% filter(grepl("^W", match_label)) %>% arrange(match_id)
  
  for (i in 1:nrow(w_matches)) {
    match <- w_matches[i, ]
    label <- match$match_label
    
    parts <- strsplit(label, " vs ")[[1]]
    home_match <- as.integer(gsub("W", "", trimws(parts[1])))  ## extract match_id from "W73"
    away_match <- as.integer(gsub("W", "", trimws(parts[2])))
    
    home_id <- match_winners[[as.character(home_match)]]
    away_id <- match_winners[[as.character(away_match)]]
    
    if (is.null(home_id) || is.null(away_id)) next  ## prior match not resolved — skip
    
    home_score <- team_scores$composite_score[team_scores$team_id == home_id]
    away_score <- team_scores$composite_score[team_scores$team_id == away_id]
    
    total <- home_score + away_score
    home_win_prob <- home_score / total
    winner_id <- ifelse(runif(1) < home_win_prob, home_id, away_id)
    match_winners[[as.character(match$match_id)]] <- winner_id
    match_participants[[as.character(match$match_id)]] <- c(home_id, away_id)
  }
  
  return(list(
    winners = match_winners,
    participants = match_participants
  ))
}


## ============================================================
## FULL TOURNAMENT WRAPPER
## ============================================================
## Wraps the full tournament pipeline into a single function
## for use in the Monte Carlo loop.
## Returns standings, knockout results, match participants,
## and champion team_id.
## ============================================================

simulate_tournament <- function(matches, team_scores, third_place_combinations) {
  
  group_results <- simulate_group_stage(matches, team_scores)
  standings <- calculate_standings(group_results, matches, team_scores)
  slots <- get_third_place_slots(standings, third_place_combinations)
  lookup <- resolve_knockout_participants(standings, slots)
  qualifiers <- determine_qualifiers(standings)
  
  knockout_matches <- matches %>% filter(match_id > 72)  ## R32 onwards
  knockout_results <- simulate_knockout_stage(knockout_matches, lookup, team_scores)
  
  champion_id <- knockout_results$winners[["104"]]  ## match 104 is the final
  
  return(list(
    standings = standings,
    knockout_results = knockout_results$winners,
    match_participants = knockout_results$participants,
    qualifiers = qualifiers,
    champion_id = champion_id
  ))
}

## Single run test - seed 42 returns France as champion
## set.seed(42)
## result <- simulate_tournament(matches, team_scores, third_place_combinations)
## print(paste("Champion:", team_scores$country_name[team_scores$team_id == result$champion_id]))


## ============================================================
## MONTE CARLO SIMULATION
## ============================================================
## Runs 10,000 full tournament simulations and aggregates
## championship probabilities for each of the 48 teams.
## Each simulation is fully independent — group draws, knockout
## bracket, and match outcomes are all re-randomized each run.
##
## Output: multiple aggregated dataframes for Tableau dashboards
##   - champions: vector of champion team_ids per simulation
##   - advancement_tracker: round reached per team per simulation
##   - group_tracker: group standings per simulation
##   - third_place_points_tracker: qualifying third-place points per simulation
##   - champion_path_tracker: average opponent strength faced by champion
## ============================================================

n_simulations <- 10000

## Storage for all metrics
champions               <- integer(n_simulations)
advancement_tracker     <- list()
group_tracker           <- list()
third_place_points_tracker <- list()
champion_path_tracker   <- list()

## Round definitions by match_id — used to extract winners from knockout_results
r32_matches_ids <- 73:88
r16_matches_ids <- 89:96
qf_matches_ids  <- 97:100
sf_matches_ids  <- 101:102
final_match_id  <- 104

cat("Running", n_simulations, "simulations...\n")

for (i in 1:n_simulations) {
  if (i %% 1000 == 0) cat("Simulation", i, "complete\n")
  
  result <- simulate_tournament(matches, team_scores, third_place_combinations)
  ko <- result$knockout_results
  ko_participants <- result$match_participants
  standings <- result$standings
  champion_id <- result$champion_id
  
  champions[i] <- champion_id
  
  ## winners of each round = teams that advanced to the next round
  r32_teams <- result$qualifiers$team_id                  ## qualified from group stage = reached R32
  r16_teams <- unlist(ko[as.character(r32_matches_ids)])  ## won R32 = reached R16
  qf_teams  <- unlist(ko[as.character(r16_matches_ids)])  ## won R16 = reached QF
  sf_teams  <- unlist(ko[as.character(qf_matches_ids)])   ## won QF = reached SF
  finalists <- unlist(ko[as.character(sf_matches_ids)])   ## won SF = reached Final
  
  advancement_tracker[[i]] <- data.frame(
    sim = i,
    team_id = c(r32_teams, r16_teams, qf_teams, sf_teams, finalists, champion_id),
    round = c(
      rep("R32", length(r32_teams)),
      rep("R16", length(r16_teams)),
      rep("QF",  length(qf_teams)),
      rep("SF",  length(sf_teams)),
      rep("Final", length(finalists)),
      "Champion"
    ),
    stringsAsFactors = FALSE
  )
  
  ## Track group finish positions and points per team
  group_tracker[[i]] <- standings %>%
    select(team_id, group_label, group_rank, points) %>%
    mutate(sim = i)
  
  ## Track points of qualifying third-place teams
  ## Used for "How safe is 4 points?" analysis
  third_place_qualifying <- standings %>%
    filter(group_rank == 3) %>%
    arrange(desc(points)) %>%
    slice(1:8) %>%
    pull(points)
  
  third_place_points_tracker[[i]] <- data.frame(
    sim = i,
    min_points = min(third_place_qualifying),
    max_points = max(third_place_qualifying),
    cutoff_points = min(third_place_qualifying)  ## lowest points that still qualified
  )
  
  ## Track champion's path — average composite score of opponents beaten
  ## Used for hardest path to champion analysis
  opponent_scores <- c()
  
  for (match_id in c(r32_matches_ids, r16_matches_ids, qf_matches_ids,
                     sf_matches_ids, final_match_id)) {
    participants <- ko_participants[[as.character(match_id)]]
    winner <- ko[[as.character(match_id)]]
    
    if (!is.null(participants) && !is.null(winner)) {
      opponent_id <- participants[participants != winner]  ## the team that lost
      if (length(opponent_id) > 0 && winner == champion_id) {  ## only track champion's matches
        opp_score <- team_scores$composite_score[team_scores$team_id == opponent_id]
        if (length(opp_score) > 0) opponent_scores <- c(opponent_scores, opp_score)
      }
    }
  }
  
  champion_path_tracker[[i]] <- data.frame(
    sim = i,
    champion_id = champion_id,
    avg_opponent_strength = ifelse(length(opponent_scores) > 0,
                                   round(mean(opponent_scores), 4), NA)  ## NA if path not fully resolved
  )
}

cat("Simulations complete.\n")

result <- simulate_tournament(matches, team_scores, third_place_combinations)

group_matches <- matches %>% filter(match_id <= 72)

for (i in 1:nrow(group_matches)) {
  match <- group_matches[i, ]
  home_score <- team_scores$composite_score[team_scores$team_id == match$home_team_id]
  away_score <- team_scores$composite_score[team_scores$team_id == match$away_team_id]
  
  if (length(home_score) == 0 || length(away_score) == 0 || is.na(home_score) || is.na(away_score)) {
    cat("Problem match:", match$match_id, 
        "home_team_id:", match$home_team_id, "score:", length(home_score),
        "away_team_id:", match$away_team_id, "score:", length(away_score), "\n")
  }
}