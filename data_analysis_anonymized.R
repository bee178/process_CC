# Script for data analysis Research Project

rm(list = ls())
setwd("C:/Users/bgonz/University/year5/RP")

#install.packages(c("sf", "dplyr", "viridis", "paletteer", "naturalsort", "ggrepel", 'readxl', "tidyverse"))
#install.packages('ggplot2', dep=TRUE, lib=NULL)


library(sf) # handle spatial data conveniently as simple features
library(ggplot2)
library(dplyr)
library(viridis) # compilation of palettes
library(paletteer) # compilation of palettes
library(naturalsort) # read *.tif files in the right order
library(readxl)
library(ggrepel)
library(tidyverse)
library(ppcor)
library(xtable)


#FOR DATA POINTS: TOTAL, AVERAGE_COMMIT, MAX
#Retrieve and set up the csv data

#TODO: SET DATA EXTRACTION FOR EACH CSV: COMMIT DATA
results_G1 <- as_tibble(read.csv(""))
#results_G2 (...)


colnames(results_G1) <- c("sha", "author", "complexity", "line_nr")
#colnames(results_G2) <- (...)

#TODO: Set how many groups to analyse and which ones, use bind for multiple
results <- results_G1


results <- results %>%
  mutate(author = str_trim(author))


#TODO: Check if the git author names are the same in all data sources (experience form and git)
#If yes: PROCESS! Make sure the names are the same in both columns


#Summarizes data for commits
comp_by_author <- results %>%
  group_by(author) %>% #Allows for multiple authors per branch
  summarise(
    complexity_sum = sum(complexity),
    complexity_avg_commit = mean(complexity),
    complexity_max = max(complexity),
    .groups = "drop"
  )



#GET AVERAGE PER ISSUE/BRANCH



#TODO: SET DATA EXTRACTION FOR EACH CSV: BRANCH DATA
results2_G1 <- as_tibble(read.csv(""))
#results2_G2 (...)


colnames(results2_G1) <- c("branch_name", "sha", "author", "complexity", "line_nr")
#colnames(results2_G2) <- (...)


#TODO: Set how many groups to analyse and which ones, use bind for multiple
results2 <- results2_G1


#Current result analysis 
results_1 <-results2

#TODO: Update this line according with base branch
results_1 <- subset(results_1, branch_name != "dev")

results_1 <- results_1 %>%
  mutate(author = str_trim(author))


#TODO: Check if the git author names are the same in all data sources (experience form and git)
#If yes: PROCESS! Make sure the names are the same in both columns


# Define non-authors
non_authors <- c("unknown", "lost", "lost or merged from dev?")

# Step 1: Identify valid authors per branch
branch_author_counts <- results_1 %>%
  filter(!author %in% non_authors) %>%
  distinct(sha, author) %>%
  count(sha, name = "n_authors")

results_1_classified <- results_1 %>%
  left_join(branch_author_counts, by = "sha") %>%
  mutate(n_authors = ifelse(is.na(n_authors), 0, n_authors))

results_1_reinspect <- results_1_classified %>%
  filter(n_authors > 1)


#TODO: Important reinspect these commits MANUALLY!!
reinspect_commits <- results_1_reinspect %>% 
  distinct(sha)

#After reinspection decide if manually add if needed
#grouped <- c()
#results_1_to_add <- results_1_reinspect[results_1_reinspect$sha %in% grouped,]
#all
#results_1_to_add <- subset(results_1_to_add, complexity > 0)

#TODO: if commits were manually added, it is necessary to add authorship manually too.

#Takes only single authorship
results_1_single_author <- results_1_classified %>%
  filter(n_authors < 2) 

#Who are the commits from in that branch
single_author_map <- results_1 %>%
  filter(!author %in% non_authors) %>%
  group_by(sha) %>%
  summarise(single_author = unique(author)[1], .groups = "drop")


results_1_processed <- results_1_single_author %>%
  left_join(single_author_map, by = "sha") %>%
  mutate(author = ifelse(author %in% non_authors & !is.na(single_author), single_author, author)) %>%
  select(-single_author)

#From manual inspection are there any other weird branches to drop?

#Merge with filtered branches
#results_1_processed <- merge(results_1_processed, results_1_to_add, all = TRUE)

#TODO: If there are any svelte files, it is likely authorship was lost in the conversion. Manual inspection is needed for every branch



# complexity added per branch
# Step 1: Total complexity per branch
branch_total <- results_1_processed %>%
  group_by(sha) %>%
  summarise(branch_complexity = sum(complexity), .groups = "drop")

# Step 2: Total complexity each author added per branch
author_branch_contrib <- results_1_processed %>%
  group_by(sha, author) %>%
  summarise(author_complexity = sum(complexity), .groups = "drop")

# Step 3: Average complexity added by each author per branch they contributed to
author_avg_complexity <- author_branch_contrib %>%
  group_by(author) %>%
  summarise(complexity_avg_branch = mean(author_complexity), .groups = "drop")


comp_by_author_1 <- results_1_processed %>%
  group_by(author) %>%
  summarise(
    complexity_sum = sum(complexity),
    complexity_max = max(complexity),
    .groups = "drop"
  )


#COMMITS AND BRANCHES JOINED
final_df <-left_join(comp_by_author, author_avg_complexity %>% dplyr::select(author, complexity_avg_branch), 
                                   by = "author")
final_df <- final_df %>% relocate(complexity_avg_branch, .after = complexity_avg_commit)




#Process prior experience form results
#TODO: SET THE LOCATION OF FORM RESULTS AND adjust column positions if necessary
prior_exp_to_process <- read_xlsx("")

groups <- prior_exp_to_process[c(5,6)]

colnames <- colnames(prior_exp_to_process)
chosen_cols <- colnames[c(5, 13,14,15,16,17,19,20,21,22, 23, 24, 9)]

prior_exp <- prior_exp_to_process[chosen_cols]
prior_exp <- prior_exp[-c(7,11, 12, 13, 15, 18,21, 22), ]

#Score of each
experience_map <- c(
  "Very inexperienced" = 1,
  "Inexperienced" = 3,
  "Neutral" = 5,
  "Experienced" = 7,
  "Very experienced" = 10
)


#Indices of columns with Very inexperienced ... Very experienced
cols_to_map <- c(3, 4, 5, 6)
# Scale column 2 (0-21) to new column (0-10)
print(prior_exp[,9]) 


prior_exp <- prior_exp %>%
  mutate(across(all_of(names(.)[cols_to_map]), ~ experience_map[as.character(.)]))%>%
  mutate_all(~replace(., is.na(.), 0)) %>%
  mutate(across(c(2, 3, 4, 5, 6, 7,8,9, 10, 11, 13), ~ as.numeric(.))) %>%
  mutate(
    scaled_value = round(.[[9]] * (10 / 21), 0)  # Column 9 → 0-10
  )

prior_exp_metrics <- prior_exp %>%
  
  mutate(across(c(2, 3, 4, 5, 8, 9), ~replace(., is.na(.), 0))) %>%
  # Step 1: Row-wise average across columns 2, 3, 4, 5, and 8 (after relocate)
  rowwise() %>%
  mutate(
    average_score = mean(c_across(c(2, 3, 4, 5, 8)), na.rm = TRUE)
  ) %>%
  ungroup() %>%
  dplyr::select(c(1, 7, 11, 13, 15, 6))

names(prior_exp_metrics)[1:6] <- c("name", "years", "years_job", "years_TUDelft", "exp_score", "complexity")
names(groups)[1:2] <- c("name", "group")

library("xlsx")
#

prior_exp_metrics <- prior_exp_metrics %>%
  inner_join(groups, by = "name")



#Correlation plots
joined_df <- prior_exp_metrics %>%
  rename(author = name) %>%
  inner_join(final_df, by = "author")

cols_table2 <- c("years", "years_job","years_TUDelft", "exp_score", "complexity")
cols_table1 <- c("complexity_sum", "complexity_avg_commit", "complexity_avg_branch", "complexity_max")

write.xlsx(joined_df, "prior_exp_full.xlsx")

#TODO: set one per group if necessary 
#group_A <- joined_df %>%
#  filter(joined_df$group == "")
#(..)


plot <- joined_df


#ALL GROUPS 
cor_results_ALL <- data.frame()

for (x in cols_table2) {
  for (y in cols_table1) {    
    test <- cor.test(plot[[x]], plot[[y]], method = "spearman")
    cor_results_ALL <- rbind(cor_results_ALL, data.frame(
      var_table2 = x,
      var_table1 = y,
      correlation = test$estimate,
      p_value = test$p.value
    ))
  }
}


#TEST PARTIAL CORRELATIONS


# Define complexity metrics
metrics <- c("complexity_sum", "complexity_avg_commit", "complexity_avg_branch", "complexity_max")
df <- plot

# Store results
results <- data.frame()

for (metric in metrics) {
  # 1. Partial correlation of years_job ~ complexity | years_uni
  pcor1 <- pcor.test(df[[metric]], df$years_job, df$years_TUDelft, method = "spearman")
  
  # 2. Partial correlation of years_uni ~ complexity | years_job
  pcor2 <- pcor.test(df[[metric]], df$years_TUDelft, df$years_job, method = "spearman")
  
  # Append results
  results <- rbind(results,
                   data.frame(comparison = paste0("years_job vs ", metric, " | control years_uni"),
                              estimate = pcor1$estimate,
                              p.value = pcor1$p.value),
                   data.frame(comparison = paste0("years_uni vs ", metric, " | control years_job"),
                              estimate = pcor2$estimate,
                              p.value = pcor2$p.value))
}

# Required libraries
# Define metrics
metrics <- c("complexity_sum", "complexity_avg_commit", "complexity_avg_branch", "complexity_max")

# Initialize empty data frame
results <- data.frame(
  Variable = character(),
  Metric = character(),
  Control = character(),
  Estimate = numeric(),
  P_value = numeric(),
  stringsAsFactors = FALSE
)

# Loop through metrics
for (metric in metrics) {
  # Partial correlation: years_job vs metric | control years_TUDelft
  pcor1 <- pcor.test(df[[metric]], df$years_job, df$years_TUDelft, method = "spearman")
  
  # Partial correlation: years_TUDelft vs metric | control years_job
  pcor2 <- pcor.test(df[[metric]], df$years_TUDelft, df$years_job, method = "spearman")
  
  # Append both results
  results <- rbind(results,
                   data.frame(
                     Variable = "Years Job",
                     Metric = metric,
                     Control = "Years Uni",
                     Estimate = pcor1$estimate,
                     P_value = pcor1$p.value
                   ),
                   data.frame(
                     Variable = "Years Uni",
                     Metric = metric,
                     Control = "Years Job",
                     Estimate = pcor2$estimate,
                     P_value = pcor2$p.value
                   )
  )
}

# Add significance markers
results$Significance <- ifelse(results$P_value < 0.01, "**",
                               ifelse(results$P_value < 0.05, "*", ""))

# Create formatted estimate with significance
results$EstimateFormatted <- sprintf("%.3f%s", round(results$Estimate, 3), results$Significance)

# Sort by Control variable then Metric
results <- results[order(results$Control, results$Metric), ]

# Select final display columns
final_table <- results[, c("Variable", "Metric", "Control", "EstimateFormatted", "P_value")]
colnames(final_table) <- c("Variable", "Metric", "Control", "Estimate", "p-value")

print(final_table)

latex_table <- xtable(
  final_table,
  caption = "Partial Spearman Correlations by Experience Metric, Marked by Significance (* p < 0.05, ** p < 0.01)",
  label = "tab:partial_corr_signif"
)

print(latex_table, type = "latex", file = "partial_correlations_table.tex", include.rownames = FALSE)



df$group_numeric <- as.numeric(as.factor(df$group))
weird <- pcor.test(df$years_TUDelft, df$complexity_sum, df$group_numeric, method = "spearman")

print(weird)




#Save results
#write.xlsx(cor_results, "correlation_results_All_final.xlsx", row.names = FALSE)
#install.packages("xtable")
#library(xtable)
#print(xtable(cor_results, type = "latex"), file = "correlations.tex")

#Make results prettier and more readable
pretty_labels_table2 <- c(
  years = "Years of Experience",
  years_job = "Years in Industry",
  years_TUDelft = "Years at TU Delft",
  exp_score = "Experience Score",
  complexity = "Self-Reported Complexity"
)

pretty_labels_table1 <- c(
  complexity_sum = "Total",
  complexity_avg_commit = "Average p/ Commit",
  complexity_avg_branch = "Average p/ Branch",
  complexity_max = "Max"
)


cor_results_ALL <- cor_results_ALL %>%
  mutate(
    var_table2 = factor(var_table2, levels = names(pretty_labels_table2), labels = pretty_labels_table2),
    var_table1 = factor(var_table1, levels = names(pretty_labels_table1), labels = pretty_labels_table1)
  )





#YEARS IN INDUSTRY GRAPH
filter_1 <- cor_results_ALL %>% filter(cor_results_ALL$var_table2 == "Years in Industry") %>% mutate(var_table2 = "All groups")
#TODO: do this per group if necessary

#Years in tud
filter_2 <- cor_results_ALL %>% filter(cor_results_ALL$var_table2 == "Years at TU Delft") %>% mutate(var_table2 = "All groups")
#TODO: do this per group if necessary


industry <- bind_rows(filter_1)
academia <- bind_rows(filter_2)
xtab1 <- xtable(industry)
xtab2 <- xtable(academia)

write.xlsx(industry, "correlation_results_industry_final.xlsx", row.names = FALSE)
write.xlsx(industry, "correlation_results_academia_final.xlsx", row.names = FALSE)
#install.packages("xtable")

print(xtab1, include.rownames=TRUE, type = "latex", file = "correlations_industry.tex")
print(xtab2, include.rownames=TRUE, type = "latex", file = "correlations_academia.tex")


#Heatmap Industry
ggplot(industry, aes(x = var_table1, y = var_table2, fill = correlation)) +
  geom_tile(color = "white") +
  geom_text(aes(label = ifelse(p_value < 0.05, sprintf("%.2f*", correlation), sprintf("%.2f", correlation))), 
            size = 4, color = "black") +
  scale_fill_gradient2(low = "#5042d4", high = "#d44242", mid = "white",
                       midpoint = 0, limit = c(-1,1), space = "Lab",
                       name = "Spearman's\n rank\nCorrelation") +
  labs(title = "Correlation heatmap of Years in Industry vs Complexity performance", x = "Complexity Metrics", y = "Years of experience score by group") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1),
        plot.title = element_text(hjust = 0.5))
ggsave(filename = "Analysis/graphs/heatmap_industry.png", bg = "white")






#Heatmap All
ggplot(cor_results_C, aes(x = var_table1, y = var_table2, fill = correlation)) +
  geom_tile(color = "white") +
  geom_text(aes(label = ifelse(p_value < 0.05, sprintf("%.2f*", correlation), sprintf("%.2f", correlation))), 
            size = 4, color = "black") +
  scale_fill_gradient2(low = "#5042d4", high = "#d44242", mid = "white",
                       midpoint = 0, limit = c(-1,1), space = "Lab",
                       name = "Spearman's\n rank\nCorrelation") +
  labs(title = "Correlation heatmap of Complexity performance - Group C", x = "Complexity Metrics", y = "Prior Experience Metrics") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1),
        plot.title = element_text(hjust = 0.5))
ggsave(filename = "Analysis/graphs/heatmap_C.png", bg = "white")



#DATA VISUALIZATIONS

#X and y scatter plots
# One plot per complexity metric
ggplot(joined_df, aes(x = years, y = complexity_sum)) +
  geom_point() +
  geom_smooth(method = "lm") +
  labs(title = "Years vs Complexity Sum", x = "Years", y = "Complexity Sum")

ggplot(joined_df, aes(x = years, y = complexity_avg)) +
  geom_point() +
  geom_smooth(method = "lm") +
  labs(title = "Years vs Complexity Avg", x = "Years", y = "Complexity Avg")

ggplot(joined_df, aes(x = years, y = complexity_max)) +
  geom_point() +
  geom_smooth(method = "lm") +
  labs(title = "Years vs Complexity Max", x = "Years", y = "Complexity Max")




# Convert to long format
plot_data <- joined_df %>%
  rename(Total = complexity_sum,
         Average_commit = complexity_avg_commit,
         Average_branch = complexity_avg_branch,
         Maximum = complexity_max) %>% 
  pivot_longer(cols = c(Average_commit, Average_branch, Maximum),
               names_to = "metrics", values_to = "value")

ggplot(plot_data, aes(x = years, y = value, color = metrics)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  labs(title = "Total years of experience vs Complexity Metrics", x = "Years", y = "Complexity recorded", color="Complexity Metrics") +
  theme_minimal()
ggsave(filename = "Analysis/graphs/years_scatter.png", bg = "white")


#HISTOGRAM AND SCATTER PLOT ANALYSIS
# Figure 1: Histograms of complexity metrics
p1 <- ggplot(joined_df, aes(x = complexity_sum)) + 
  geom_histogram(bins = 30, fill = "skyblue", color = "black") +
  ggtitle("Complexity Sum")

p2 <- ggplot(joined_df, aes(x = complexity_avg_commit)) + 
  geom_histogram(bins = 30, fill = "skyblue", color = "black") +
  ggtitle("Avg Commit Complexity")

p3 <- ggplot(joined_df, aes(x = complexity_avg_branch)) + 
  geom_histogram(bins = 30, fill = "skyblue", color = "black") +
  ggtitle("Avg Branch Complexity")

p4 <- ggplot(joined_df, aes(x = complexity_max)) + 
  geom_histogram(bins = 30, fill = "skyblue", color = "black") +
  ggtitle("Max Complexity")

figure1 <- grid.arrange(p1, p2, p3, p4, ncol = 2, nrow = 2)
print(figure1)

# Figure 2: Histograms of experience metrics
p5 <- ggplot(joined_df, aes(x = years)) + 
  geom_histogram(bins = 30, fill = "salmon", color = "black") +
  ggtitle("Years")

p6 <- ggplot(joined_df, aes(x = years_job)) + 
  geom_histogram(bins = 30, fill = "salmon", color = "black") +
  ggtitle("Years in Job")

p7 <- ggplot(joined_df, aes(x = years_TUDelft)) + 
  geom_histogram(bins = 30, fill = "salmon", color = "black") +
  ggtitle("Years study")


p8 <- ggplot(joined_df, aes(x = exp_score)) + 
  geom_histogram(bins = 30, fill = "salmon", color = "black") +
  ggtitle("Experience Score")

p9 <- ggplot(joined_df, aes(x = complexity)) + 
  geom_histogram(bins = 30, fill = "salmon", color = "black") +
  ggtitle("Complexity")



figure2 <- grid.arrange(p5, p6, p7, p8, p9, ncol = 2, nrow = 3)
print(figure2)

# Figure 3: Scatter plots of complexity metrics
# Using pairs() for quick visualization
figure3 <- pairs(joined_df[, c("complexity_sum", "complexity_avg_commit", 
                              "complexity_avg_branch", "complexity_max")],
                 main = "Scatterplot Matrix of Complexity Metrics")
print(figure3)

# Figure 4: Scatter plots of experience metrics
figure4 <- pairs(joined_df[, c("years", "years_job", "years_TUDelft", 
                              "exp_score", "complexity")],
                 main = "Scatterplot Matrix of Experience Metrics")
print(figure4)



#SHAPIRO-WILK TEST
# Simplified Shapiro-Wilk test for small dataset
variables_to_test <- c("complexity_sum", "complexity_avg_commit", "complexity_avg_branch",
                       "complexity_max", "years", "years_job", "years_TUDelft",
                       "exp_score", "complexity")

all(sapply(joined_df[-1], is.numeric))

# Run tests and store results
normality_results <- lapply(variables_to_test, function(var) {
  test <- shapiro.test(joined_df[[var]])
  data.frame(
    Variable = var,
    W = round(test$statistic, 4),
    p.value = round(test$p.value, 4),
    Normality = ifelse(test$p.value > 0.05, "Normal", "Non-normal")
  )
})

# Combine results into a clean data frame
normality_table <- do.call(rbind, normality_results)

# Print the results in a clean format
print(normality_table, row.names = FALSE)

write.csv(normality_results, "normality_test_results.csv", row.names = FALSE)
