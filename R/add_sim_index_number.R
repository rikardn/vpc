#' Add sim index number
#' 
#' @description Add simulation index number to simulation when not present
#' @param sim a data.frame containing the simulation data
#' @param id character specifying the column name in the data.frame
#' @export
add_sim_index_number <- function (sim, id = "id") { # for multiple simulations in a single dataframe, add an index number for every simulation
  if ("sim" %in% colnames(sim)) {   # Keep simulation index column if already present
      return(sim$sim)
  }
  sim[[id]] <- as.num(sim[[id]])
  sim_id <- unique(sim[[id]])
  sim$id_shift <- c(sim[[id]][2:length(sim[[id]])], 0) 
  idx <- c(1, (1:length(sim[[id]]))[sim[[id]] == tail(sim_id,1) & sim$id_shift == sim_id[1]], length(sim[[id]])+1)
  sim$sim <- 0
  for (i in 1:(length(idx)-1)) {
    sim$sim[idx[i] : (idx[i+1]-1)] <- i 
  }
  return(sim$sim)
}
