# Cyclomatic Complexity: Extraction + Process
This analysis is part of [CSE3000 - TU Delft Research Project][https://github.com/TU-Delft-CSE/Research-Project] of 2024/25.

Scripts used to extract and calculate cyclomatic complexity of student software projects, they can be used as follows.

Order of use
1. Bash extraction scripts
2. Python aggregation scripts
3. R analysis scripts

# Bash Extraction
To be run from the terminal. The bash script extracts the commit history for a selected branch: either a commit or branch analysis. Changed files identified, and two copies are extracted: before and after the changes, which are then and analysed with Lizard. A cyclomatic complexity score is calculated per method within each changed file. 


