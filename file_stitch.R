# Quick R code to loop through the SLs (make sure that the other 
# ancillary files are outside of the output directory first!), stitch
# them together and then write out a CSV/FST file of the consolidated
# data.
#
# Code author: Russell A. Edson, Biometry Hub
# Date last modified: 02/05/2022


library(tidyverse)
#library(writexl)
library(fst)

# Instantiate empty table
tablerows <- data.frame(
  SL_num = integer(), SLs = character(), ATE_hat = double(), ATEtmle = double(), 
  ATEtmle_var = double(), ATEtmle_low = double(), ATEtmle_upp = double(), 
  ATEtmle_pval = double(), random_seed = integer(), elapsed_time = double()
)

for (filename in list.files()) {
  # Load RData files
  parts <- strsplit(filename, '_')[[1]]
  slnum <- as.numeric(parts[1])
  slstr <- paste(parts[-1], collapse = '_')
  
  load(filename)
  tablerows <- rbind(tablerows, mutate(dt_out, SL_num = slnum, SLs = slstr))
  print(slnum)
}

# Reorder columns
tablerows <- tablerows[ 
  , 
  c('SL_num', 'SLs', 'random_seed', 'ATE_hat', 'ATEtmle', 'ATEtmle_var', 
    'ATEtmle_low', 'ATEtmle_upp', 'ATEtmle_pval', 'elapsed_time')
]

# Reorder rows
tablerows <- arrange(tablerows, SL_num)

write.csv(tablerows, 'TMLEdata.csv')
#write_xlsx(tablerows, 'TMLEdata.xlsx', format_headers = FALSE)
write.fst(tablerows, 'TMLEdata.fst')
