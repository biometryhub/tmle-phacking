# Based on: Luque-Fernandez, M. A., Schomaker, M., Rachet, B., & Schnitzer, 
# M. E. (2018). Targeted maximum likelihood estimation for a binary treatment: 
# A tutorial. Statistics in medicine, 37(16), 2530-2546.
#
# Code authors: Max Moldovan, Russell Edson (Biometry Hub)
# Date last modified: 30/03/2022

# Loading all libraries (per VM)
library(pryr)
library(data.table)
library(tmle)
library(SuperLearner)
library(arm)
library(rpart)
library(ranger)

require(parallel)


RNG_SEED <- 612022
SUPERLEARNERS <- c(
  'SL.glm', 'SL.glm.interaction', 'SL.bayesglm', 'SL.rpart', 'SL.rpartPrune',
  'SL.ranger', 'SL.glmnet', 'SL.gam'
)
CORES_NUM <- detectCores() - 1


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
tmle_rnd_seeds <- function(rnd_seeds = 1, Y, A, W, family_c = 'binomial', SL_lib = 'SL.glm', tab_out = 'TAB') {
  # Input:
  # rnd_seeds is the random seed to be used, a single numeric or integer
  # Y, A, W, family_c and SL_lib are arguments in the tmle::tmle function
  
  # Output:
  # tab_out = "TAB": a one row data.table reporting TMLE estimates, computational times etc.
  # tab_out = "ALL": the entire output from tmle::tmle
  # tab_out = "BOTH": the entire output from tmle::tmle
  
  # Version: v0.5
  # Author: Max Moldovan (max.moldovan@gmail.com), 28 Mar 2022
  
  set.seed(rnd_seeds)
  ptm0 <- proc.time()
  TMLE <- tmle(Y = Y, A = A, W = W, family = family_c, Q.SL.library = SL_lib, g.SL.library = SL_lib)
  exec_time <- proc.time() - ptm0
  
  # Check output requirement
  if (!tab_out %in% c('TAB', 'ALL', 'BOTH')) {
    stop('Invalid output type specified')
  } else if (tab_out == 'ALL') {
    output <- TMLE
  } else {
    dt_out <- data.table(ATEtmle = TMLE$estimates$ATE$psi,
                         ATEtmle_var = TMLE$estimates$ATE$var.psi,
                         ATEtmle_low = TMLE$estimates$ATE$CI[1],
                         ATEtmle_upp = TMLE$estimates$ATE$CI[2],
                         ATEtmle_pval = TMLE$estimates$ATE$pvalue,
                         random_seed = rnd_seeds,
                         elapsed_time = as.vector(exec_time[3])
    )
    
    if (tab_out == 'TAB') {
      output <- dt_out
    } else {
      output <- list(tab = dt_out, tmle = TMLE)
    }
  }
  output
}


# Main function (pass ARGIN from shell script) #################################

# function to parallelize (across VMs/instances) computation of estimates
# based on a given sample size N and a specified output directory
run_compute <- function(N, output_dir = '.', total_seeds = 10000) {
  # Log process running time
  start_time <- proc.time()
  log_file <- file(file.path(output_dir, 'R_log.txt'), 'w')
  log_lines <- function(lines) {
    cat(lines, sep = '\n', file = log_file, append = TRUE)
  }
  log_lines(c('Start time:', capture.output(start_time), ''))
  
  # Generate dataset of observational data (used by all N, this has
  # a constant runtime overhead of roughly 3 seconds or so ~ negligible
  # compared to the main loop)
  set.seed(RNG_SEED)
  NN <- 5000000
  ObsData_ALL <- generateData(n = NN)
  True_EY.1 <- mean(ObsData_ALL$Y.1)
  True_EY.0 <- mean(ObsData_ALL$Y.0)
  True_ATE <- True_EY.1 - True_EY.0
  True_MOR <- (True_EY.1*(1 - True_EY.0))/((1 - True_EY.1)*True_EY.0)
  log_lines(paste0('TRUE ATE: ', True_ATE))
  log_lines(paste0('TRUE MOR: ', True_MOR))
  
  # Sample data for the given N sample size (offset by N so that 
  # different N produce slightly different samples, but in a 
  # deterministic way)
  set.seed(RNG_SEED + N)
  sample_indices <- sample(1:NN, N, replace = FALSE)
  ObsData_local <- ObsData_ALL[sample_indices, ]
  m <- glm(Y ~ A + w1 + w2 + w3 + w4, family = binomial, data = ObsData_local)
  vars_explanatory <- c('w1', 'w2', 'w3', 'w4')
  
  #Prediction for A, A = 1 and, A = 0
  QAW <- predict(m, type = 'response')
  Q1W <- predict(m, newdata = data.frame(A = 1, ObsData_local[ ,..vars_explanatory]), type = 'response') 
  Q0W <- predict(m, newdata = data.frame(A = 0, ObsData_local[ ,..vars_explanatory]), type = 'response')
  
  # Estimated mortality risk difference, Marginal Odds Ratio (MOR)
  ATE_hat <- mean(Q1W - Q0W)
  MOR_hat <- mean(Q1W)*(1 - mean(Q0W)) / ((1 - mean(Q1W))*mean(Q0W))
  log_lines(paste0('ATE_hat: ', ATE_hat))
  log_lines(paste0('MOR_hat: ', MOR_hat))
  
  # Y, A and W computed (to be distributed across parallel threads)
  Y <- ObsData_local$Y
  A <- ObsData_local$A
  W <- ObsData_local[ , ..vars_explanatory]
  
  # Save and clear unneeded variables
  save(
    ObsData_ALL, ObsData_local, sample_indices, m, True_ATE, True_MOR,
    vars_explanatory, True_EY.0, True_EY.1, Q0W, Q1W, QAW, NN, ATE_hat,
    MOR_hat, Y, A, W,
    file = file.path(output_dir, 'ObsData.RData')
  )
  rm(
    ObsData_ALL, ObsData_local, m, sample_indices, vars_explanatory,
    Q0W, Q1W, QAW, True_ATE, True_EY.0, True_EY.1, True_MOR, NN
  )
  
  # Get all combinations of Superlearners, used within tmle::tmle
  sl_libs_ALL <- SUPERLEARNERS
  M <- length(sl_libs_ALL)
  list_comb_indx <- vector('list', M)
  mm <- 0
  for (i in 1:M) {
    list_comb_indx[[i]] <- combn(1:M, i)
    mm <- mm + dim(list_comb_indx[[i]])[2]
  }
  log_lines(paste0('Number of unique SuperLearners: ', M))
  log_lines(paste(sl_libs_ALL, collapse = ', '))
  log_lines(paste0('Number of SL combinations overall: ', mm))
  
  list_ALL_SLs <- vector('list', mm)
  SL_library_char_vec <- 1:mm*0
  SL_index <- 1
  for (i in 1:length(list_comb_indx)) {
    index_set <- list_comb_indx[[i]]
    for (j in 1:ncol(index_set)) {
      index_vector <- as.vector(index_set[ , j])
      SL_lib_local <- sl_libs_ALL[index_vector]
      SL_library_char_vec[SL_index] <- paste(SL_lib_local, collapse = '_')
      list_ALL_SLs[[SL_index]] <- SL_lib_local
      SL_index <- SL_index + 1
    }
  }
  
  # Clear unneeded variables
  rm(
    list_comb_indx, i, j, index_set, index_vector, M, mm, SL_index,
    SL_lib_local, SL_library_char_vec, sl_libs_ALL
  )
  
  # Pre-define random seeds to run through
  set.seed(RNG_SEED)
  rs_vec <- sample(1:10000000, total_seeds, replace = FALSE)
  
  # Main loop computation (parallelised over multiple cores where possible)
  log_lines(paste0('Parallel cores avaliable: ', detectCores()))
  log_lines(paste0('Parallel cores specified to be used: ', CORES_NUM))
  
  for (i in 1:length(list_ALL_SLs)) {
    SL_lib_local <- list_ALL_SLs[[i]]
    
    # Parallelise random seeds over cores 
    list_out <- mclapply(
      1:length(rs_vec), 
      function(j) {
        tryCatch({
          tmle_rnd_seeds(rnd_seeds = rs_vec[j], Y = Y, A = A, W = W, 
                         family = 'binomial', SL_lib = SL_lib_local,
                         tab_out = 'BOTH')
        },
        error = function(c) {
          list(
            'ERROR', 
            seed = rs_vec[j], 
            Y = Y, A = A, W = W, SL_lib = SL_lib_local  
          )
        })
      },
      mc.cores = CORES_NUM
    )

    list_of_tabs <- lapply(list_out, `[[`, 'tab')
    dt_out <- rbindlist(list_of_tabs)
    dt_out <- cbind(ATE_hat, dt_out)
    
    list_of_tmles <- lapply(
      list_out, 
      function(obj) {
        tmle_obj <- obj[['tmle']]
        if (is.null(tmle_obj)) {
          obj
        } else {
          tmle_obj
        }
      }
    )
    
    # Save intermediate results for each SL combination
    intermediate_time <- proc.time() - start_time
    log_lines(
      c('', paste0('Finished SLcomb=', i, '_', paste(SL_lib_local, collapse = '_')))
    )
    log_lines(paste0('Execution time:', capture.output(intermediate_time)))
    log_lines(paste0('Memory usage: ', capture.output(pryr::mem_used())))
    save(
      SL_lib_local, dt_out, list_of_tmles,
      file = file.path(
        output_dir, 
        paste0(i,'_', paste(SL_lib_local, collapse = '_'), '.RData')
      )
    )
    
    rm(dt_out, list_of_tmles)
    gc()
  }
  
  # Here at the end: read back in all the stored data and stitch
  # the complete lists of data tables and TMLEs
  # TODO: Actually is this even necessary? Do we want them in lists?
  list_all_DTs <- vector('list', length(list_ALL_SLs))
  list_all_TMLEs <- vector('list', length(list_ALL_SLs))
  
  for (i in 1:length(list_ALL_SLs)) {
    SL_lib_local <- list_ALL_SLs[[i]]
    load(
      file.path(
        output_dir, 
        paste0(i,'_', paste(SL_lib_local, collapse = '_'), '.RData')
      )
    )
    
    list_all_DTs[[i]] <- dt_out
    list_all_TMLEs[[i]] <- list_of_tmles
  }
  
  # Log session info and execution time
  session_info <- sessionInfo()
  log_lines(c('', capture.output(sessionInfo())))
  
  run_time <- proc.time() - start_time
  log_lines(c('', 'Execution time:', capture.output(run_time)))
  log_lines(paste0('Total memory usage: ', capture.output(pryr::mem_used())))
  
  # Close file connections, save all workspace variables and done.
  close(log_file)
  save(
    list_all_DTs, list_all_TMLEs, sl_libs_ALL, rs_vec, N, 
    session_info, RNG_SEED, total_seeds, SUPERLEARNERS, CORES_NUM,
    file = file.path(output_dir, 'r_out_ALL_outputs.RData')
  )
}
