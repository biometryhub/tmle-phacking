# Based on: Luque-Fernandez, M. A., Schomaker, M., Rachet, B., & Schnitzer, 
# M. E. (2018). Targeted maximum likelihood estimation for a binary treatment: 
# A tutorial. Statistics in medicine, 37(16), 2530-2546.
#
# Code authors: Max Moldovan, Russell Edson (Biometry Hub)
# Date last modified: 04/03/2022

# Loading all libraries (per VM)
library(data.table)
library(tmle)
library(SuperLearner)
library(arm)
library(rpart)
library(ranger)

require(parallel)


RNG_SEED <- 2022


# Ancillary functions ##########################################################

# Function to generate data, as in the paper
generateData <- function(n) {
  w1 <- rbinom(n, size = 1, prob = 0.5) 
  w2 <- rbinom(n, size = 1, prob = 0.65) 
  w3 <- round(runif(n, min = 0, max = 4), digits = 0)
  w4 <- round(runif(n, min = 0, max = 5), digits = 0)
  A <- rbinom(n, size = 1, prob = plogis(-5 + 0.05*w2 + 0.25*w3 + 0.6*w4 + 0.4*w2*w4)) 
  
  # counterfactual
  Y.1 <- rbinom(n, size = 1, prob = plogis(-1 + 1 - 0.1*w1 + 0.35*w2 + 0.25*w3 + 0.20*w4 + 0.15*w2*w4)) 
  Y.0 <- rbinom(n, size = 1, prob = plogis(-1 + 0 - 0.1*w1 + 0.35*w2 + 0.25*w3 + 0.20*w4 + 0.15*w2*w4)) 
  
  # observed outcome
  Y <- Y.1*A + Y.0*(1 - A)

  data.table(w1, w2, w3, w4, A, Y, Y.1, Y.0)
}


# function to parallelise the computations across a set of alternative random seeds (the main function to parallelise)
tmle_rnd_seeds <- function(rnd_seeds = 1, Y, A, W, family_c = 'binomial', SL_lib = 'SL.glm') {
  # Input:
  # rnd_seeds is the random seed to be used, a single numeric or integer
  # Y, A, W, family_c and SL_lib are arguments in the tmle::tmle function
  
  # Output:
  # A one row data.table reporting TMLE estimates, computational times etc.
  
  # Version: v0.03
  # Author: Max Moldovan (max.moldovan@gmail.com), 25 Feb 2022
  
  set.seed(rnd_seeds)
  ptm0 <- proc.time()
  TMLE <- tmle(Y = Y, A = A, W = W, family = family_c, Q.SL.library = SL_lib, g.SL.library = SL_lib)
  exec_time <- proc.time() - ptm0

  dt_out <- data.table(ATEtmle = TMLE$estimates$ATE$psi,
                       ATEtmle_low = TMLE$estimates$ATE$CI[1],
                       ATEtmle_upp = TMLE$estimates$ATE$CI[2],
                       ATEtmle_pval = TMLE$estimates$ATE$pvalue,
                       MORtmle = TMLE$estimates$OR$psi,
                       ATEtmle_low = TMLE$estimates$OR$CI[1],
                       ATEtmle_upp = TMLE$estimates$OR$CI[2],
                       ATEtmle_pval = TMLE$estimates$OR$pvalue, 
                       random_seed = rnd_seeds,
                       elapsed_time = as.vector(exec_time[3])
  )
  
  return(dt_out)
}


# Main function (pass ARGIN from shell script) #################################

# function to parallelize (across VMs/instances) computation of estimates
# based on a given sample size N and a specified output directory
run_compute <- function(N, output_dir) {
  # Log process running time
  start_time <- proc.time()
  log_file <- file(file.path(output_dir, 'R_log.txt'), 'w')
  log_lines <- function(lines) {
    cat(lines, sep = '\n', file = log_file, append = TRUE)
  }
  
  log_lines(c('Start time:', capture.output(start_time), ''))
  
  # Generate dataset (same seed, so this should be the exact same
  # dataset across all of the VMs for different N)
  set.seed(RNG_SEED)
  NN <- 5000000
  ObsData_ALL <- generateData(n = NN)
  True_EY.1 <- mean(ObsData_ALL$Y.1)
  True_EY.0 <- mean(ObsData_ALL$Y.0)
  True_ATE <- True_EY.1 - True_EY.0
  True_MOR <- (True_EY.1*(1 - True_EY.0))/((1 - True_EY.1)*True_EY.0)
  
  log_lines(paste0('TRUE ATE: ', True_ATE))
  log_lines(paste0('TRUE MOR: ', True_MOR))
  
  # Sample data for the given N sample size
  set.seed(RNG_SEED)
  index_vec <- sample(1:NN, N, replace = FALSE)
  ObsData_local <- ObsData_ALL[index_vec, ]
  m <- glm(Y ~ A + w1 + w2 + w3 + w4, family = binomial, data = ObsData_local)
  
  #Prediction for A, A = 1 and, A = 0
  QAW <- predict(m, type = 'response')
  Q1W <- predict(m, newdata = data.frame(A = 1, ObsData_local[,c('w1','w2','w3','w4')]), type = 'response') 
  Q0W <- predict(m, newdata = data.frame(A = 0, ObsData_local[,c('w1','w2','w3','w4')]), type = 'response')
  
  # Estimated mortality risk difference
  ATE_hat <- mean(Q1W - Q0W)
  
  # Estimated Marginal Odds Ratio (MOR)
  MOR_hat <- mean(Q1W)*(1 - mean(Q0W)) / ((1 - mean(Q1W))*mean(Q0W))
  
  # Super learners, used within tmle::tmle
  sl_libs_ALL <- c(
    'SL.glm', 'SL.glm.interaction', 'SL.bayesglm'#, 'SL.rpart', 'SL.rpartPrune',
    #'SL.ranger', 'SL.glmnet', 'SL.gam'
  )
  
  # Get all combinations of superlearners
  M <- length(sl_libs_ALL)
  list_comb_indx <- vector('list', M)
  mm <- 0
  for (i in 1:M) {
    list_comb_indx[[i]] <- combn(1:M, i)
    mm <- mm + dim(list_comb_indx[[i]])[2]
  }
  
  log_lines(paste0('Number of unique SuperLearners: ', M))
  log_lines(paste0('Number of SL combinations overall: ', mm))
  
  list_ALL_SLs <- vector('list', mm)
  SL_library_char_vec <- 1:mm*0
  SL_index <- 1

  for (i in 1:length(list_comb_indx)) {
    index_set <- list_comb_indx[[i]]
    
    for (j in 1:ncol(index_set)) {
      index_vec <- as.vector(index_set[ , j])
      SL_lib_local <- sl_libs_ALL[index_vec]
      
      SL_library_char_vec[SL_index] <- paste(SL_lib_local, collapse = '_')
      list_ALL_SLs[[SL_index]] <- SL_lib_local
      SL_index <- SL_index + 1
    }
  }
  
  # Pre-define random seeds to run through
  KK <- 10000
  KK <- 50
  set.seed(RNG_SEED)
  rs_vec <- sample(1:10000000, KK, replace = FALSE)
  
  cores <- detectCores() - 1
  cores <- 1
  log_lines(paste0('Parallel cores avaliable: ', detectCores()))
  log_lines(paste0('Parallel cores to be used: ', cores))
  
  vars_explanatory <- c('w1', 'w2', 'w3', 'w4')
  list_all_DTs <- vector('list', mm)
  names_for_list_all_DTs <- vector('character', mm)
  DT_index <- 1
  
  Y <- ObsData_local$Y
  A <- ObsData_local$A
  W <- ObsData_local[ , ..vars_explanatory]
  
  for (i in 1:length(list_ALL_SLs)) {
    SL_lib_local <- list_ALL_SLs[[i]]
    
    # Parallelise random seeds over cores
    list_out <- mclapply(
      1:length(rs_vec), 
      function(j) {
        tmle_rnd_seeds(rnd_seeds = rs_vec[j], Y = Y, A = A, W = W, 
                       family = 'binomial', SL_lib = SL_lib_local)
      },
      mc.cores = cores
    )
    
    dt_out <- rbindlist(list_out)
    list_all_DTs[[DT_index]] <- dt_out
    DT_index <- DT_index + 1
  }
  
  # Log session info and execution time
  session_info <- sessionInfo()
  log_lines(c('', capture.output(sessionInfo())))
  
  run_time <- proc.time() - start_time
  log_lines(c('', 'Execution time:', capture.output(run_time)))
  
  # Close file connections, save workspace variables and done.
  close(log_file)
  save(
    list_all_DTs, names_for_list_all_DTs, 
    ObsData_ALL, index_vec, sl_libs_ALL, rs_vec, session_info, 
    file = file.path(output_dir, 'r_out_ALL_outputs.RData')
  )
}
