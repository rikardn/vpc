#' VPC function for survival-type data
#'
#' Creates a VPC plot from observed and simulation survival data
#' @param sim a data.frame with observed data, containing the indenpendent and dependent variable, a column indicating the individual, and possibly covariates. E.g. load in from NONMEM using \link{read_table_nm}
#' @param obs a data.frame with observed data, containing the indenpendent and dependent variable, a column indicating the individual, and possibly covariates. E.g. load in from NONMEM using \link{read_table_nm}
#' @param psn_folder instead of specyfing "sim" and "obs", specify a PsN-generated VPC-folder
#' @param bins either "density", "time", or "data", or a numeric vector specifying the bin separators.
#' @param n_bins number of bins
#' @param obs_cols observation dataset column names (list elements: "dv", "idv", "id", "pred")
#' @param sim_cols simulation dataset column names (list elements: "dv", "idv", "id", "pred")
#' @param software name of software platform using (eg nonmem, phoenix)
#' @param show what to show in VPC (obs_ci, obs_median, sim_median, sim_median_ci)
#' @param rtte repeated time-to-event data? Deafult is FALSE (treat as single-event TTE)
#' @param rtte_calc_diff recalculate time (T/F)? When simulating in NONMEM, you will probably need to set this to TRUE to recalculate the TIME to relative times between events (unless you output the time difference between events and specify that as independent variable to the vpc_tte() funciton.
#' @param kmmc either NULL (for regular TTE vpc, default), or a variable name for a KMMC plot (e.g. "WT")
#' @param events numeric vector describing which events to show a VPC for when repeated TTE data, e.g. c(1:4). Default is NULL, which shows all events.
#' @param reverse_prob reverse the probability scale (i.e. plot 1-probability)
#' @param stratify character vector of stratification variables. Only 1 or 2 stratification variables can be supplied. If stratify_color is also specified, only 1 additional stratification can be specified.
#' @param stratify_color variable to stratify and color lines for observed data. Only 1 stratification variables can be supplied.
#' @param ci confidence interval to plot. Default is (0.05, 0.95)
#' @param plot Boolean indacting whether to plot the ggplot2 object after creation. Default is FALSE.
#' @param as_percentage Show y-scale from 0-100 percent? TRUE by default, if FALSE then scale from 0-1.
#' @param xlab ylab as numeric vector of size 2
#' @param ylab ylab as numeric vector of size 2
#' @param title title
#' @param smooth "smooth" the VPC (connect bin midpoints) or show bins as rectangular boxes. Default is TRUE.
#' @param vpc_theme theme to be used in VPC. Expects list of class vpc_theme created with function vpc_theme()
#' @param facet either "wrap", "columns", or "rows"
#' @param verbose TRUE or FALSE (default)
#' @param vpcdb Boolean whether to return the underlying vpcdb rather than the plot
#' @return a list containing calculated VPC information, and a ggplot2 object
#' @export
#' @seealso \link{vpc}
#' @examples
#' ## Example for repeated) time-to-event data
#' ## with NONMEM-like data (e.g. simulated using a dense grid)
#' data(rtte_obs_nm)
#' data(rtte_sim_nm)
#'
#' # treat RTTE as TTE, no stratification
#' vpc_tte(sim = rtte_sim_nm,
#'         obs = rtte_obs_nm,
#'         rtte = FALSE,
#'         sim_cols=list(dv = "dv", idv = "t"), obs_cols=list(idv = "t"))
#'
#' # stratified for covariate and study arm
#' vpc_tte(sim = rtte_sim_nm,
#'         obs = rtte_obs_nm,
#'         stratify = c("sex","drug"),
#'         rtte = FALSE,
#'         sim_cols=list(dv = "dv", idv = "t"), obs_cols=list(idv = "t"))
#'
#' # stratified per event number (we'll only look at first 3 events) and stratify per arm
#' vpc_tte(sim = rtte_sim_nm,
#'         obs = rtte_obs_nm,
#'         rtte = TRUE, events = c(1:3),
#'         stratify = c("drug"),
#'         sim_cols=list(dv = "dv", idv = "t"), obs_cols=list(idv = "t"))
vpc_tte <- function(sim = NULL,
                    obs = NULL,
                    psn_folder = NULL,
                    rtte = FALSE,
                    rtte_calc_diff = TRUE,
                    events = NULL,
                    bins = FALSE,
                    n_bins = 10,
                    software = "auto",
                    obs_cols = NULL,
                    sim_cols = NULL,
                    kmmc = NULL,
                    reverse_prob = FALSE,
                    stratify = NULL,
                    stratify_color = NULL,
                    ci = c(0.05, 0.95),
                    plot = FALSE,
                    xlab = NULL,
                    ylab = NULL,
                    show = list(),
                    as_percentage = TRUE,
                    title = NULL,
                    smooth = FALSE,
                    vpc_theme = NULL,
                    facet = "wrap",
                    verbose = FALSE,
                    vpcdb = FALSE) {
  if(is.null(obs) & is.null(sim)) {
    stop("At least a simulation or an observation dataset are required to create a plot!")
  }
  if(!is.null(kmmc)) {
    if(!kmmc %in% names(obs)) {
      stop(paste0("Specified covariate ", kmmc, " not found among column names in observed data."))
    }
  }
  if(!is.null(kmmc)) {
    if(!kmmc %in% names(sim)) {
      stop(paste0("Specified covariate ", kmmc, " not found among column names in simulated data."))
    }
  }
  if(!is.null(psn_folder)) {
    if(!is.null(obs)) {
      obs <- read_table_nm(paste0(psn_folder, "/m1/", dir(paste0(psn_folder, "/m1"), pattern="original.npctab")[1]))
    }
    if(!is.null(sim)) {
      sim <- read_table_nm(paste0(psn_folder, "/m1/", dir(paste0(psn_folder, "/m1"), pattern="simulation.1.npctab")[1]))
    }
    software = "nonmem"
  }
  if (!is.null(obs)) {
    software_type <- guess_software(software, obs)
  } else {
    software_type <- guess_software(software, sim)
  }

  if(is.null(sim)) {
    show_default$obs_ci <- TRUE
  }
  show <- replace_list_elements(show_default, show)

  ## checking whether stratification columns are available
  if(!is.null(stratify)) {
    check_stratification_columns_available(obs, stratify, "observation")
    check_stratification_columns_available(sim, stratify, "simulation")
  }
  if(!is.null(stratify_color)) {
    check_stratification_columns_available(obs, stratify_color, "observation")
    check_stratification_columns_available(sim, stratify_color, "simulation")
  }

  ## redefine strat column in case of "strat"
  if(!is.null(stratify)) {
    if(stratify[1] == "strat") {
      obs$strat_orig = obs$strat
      stratify <- "strat_orig"
    }
  }
  if(!is.null(stratify_color)) {
    if(stratify_color == "strat") {
      obs$strat_orig = obs$strat
      stratify_color <- "strat_orig"
    }
  }

  ## define column names
  cols <- define_data_columns(sim, obs, sim_cols, obs_cols, software_type)
  if(!is.null(obs)) {
    old_class <- class(obs)
    class(obs) <- c(software_type, old_class)
  }
  if(!is.null(sim)) {
    old_class <- class(sim)
    class(sim) <- c(software_type, old_class)
  }

  ## remove EVID != 0 / MDV != 0
  if(!is.null(obs)) {
    obs <- filter_dv(obs, verbose)
  }
  if(!is.null(sim)) {
    sim <- filter_dv(sim, verbose)
  }

  ## stratification
  stratify_original <- stratify
  if(!is.null(stratify_color)) {
    if (is.null(stratify)) {
      stratify <- stratify_color
    }
    if (length(stratify_color) > 1) {
      stop("Error: please specify only 1 stratification variable for color!")
    }
    if (!stratify_color %in% stratify) {
      stratify_original <- stratify
      stratify <- c(stratify, stratify_color)
    }
  }
  if(!is.null(stratify)) {
    if(rtte) {
      if (length(stratify) > 1) {
        stop ("Sorry, with repeated time-to-event data, stratification on more than 1 variables is currently not supported!")
        invisible()
      }
    } else {
      if (length(stratify) > 2) {
        stop ("Sorry, stratification on more than 2 variables is currently not supported!")
        invisible()
      }
    }
  }

  ## format obs data
  if(!is.null(obs)) {
    obs$id <- obs[[cols$obs$id]]
    if (length(obs[[cols$obs$id]]) == 0) {
      msg("Warning: No ID column found, assuming 1 row per ID.", verbose)
      obs$id <- 1:length(obs[,1])
    }
    obs$time <- as.num(obs[[cols$obs$idv]])
    obs$dv <- as.num(obs[[cols$obs$dv]])
    if(max(obs$dv) > 1) { # guessing DV definition if not just 0/1
      if(max(obs$dv) == 2) { # common approach in NONMEM, 2 = censored
        obs[obs$dv != 1,]$dv <- 0
        msg("Warning: vpc_tte() expected the observed dependent variable to contain only 0 (censored, or no event observed) or 1 (event observed). Setting all observations != 1 to 0.", verbose)
      } else {
        obs[obs$dv != 1,]$dv <- 1 # some people use DV to indicate the event time.
        msg("Warning: vpc_tte() expected the dependent variable to contain only 0 (censored, or no event observed) or 1 (event observed). Setting all observations != 1 to 1.", verbose)
      }
    }
    if("cens" %in% tolower(colnames(obs))) { # some people use a 'cens' column to indicate censoring
      msg(paste0("Detected column '",colnames(obs)[match("cens", tolower(colnames(obs)))],"' with censoring information in observation data, assuming 1=censored event, 0=observed event. Please transpose data if assumption not correct."), TRUE)
      colnames(obs)[match("cens", tolower(colnames(obs)))] <- "cens"
      obs[obs$cens == 1,]$dv <- 0
    }
    if (rtte) {
      if(rtte_calc_diff) {
        obs <- relative_times(obs)
      }
      obs <- obs %>% group_by(id) %>% arrange(id, time) %>% mutate(rtte = 1:length(dv))
#       obs %>% group_by(id) %>% mutate(rtte = cumsum(dv != 0))
#       obs[obs$dv == 0,]$rtte <- obs[obs$dv == 0,]$rtte + 1 # these censored points actually "belong" to the next rtte strata
      stratify <- c(stratify, "rtte")
    } else {
      obs$rtte <- 1
    }

    # add stratification column and comput KM curve for observations
    obs <- add_stratification(obs, stratify)
    if(!is.null(kmmc) && kmmc %in% names(obs)) {
      obs_km <- compute_kmmc(obs, strat = "strat", reverse_prob = reverse_prob, kmmc=kmmc)
    } else {
      if(show$obs_ci) {
        if(length(ci) == 2 && (round(ci[1],3) != round((1-ci[2]),3))) {
          stop("Sorry, only symmetric confidence intervals can be computed. Please adjust the ci argument.")
        }
        obs_km <- compute_kaplan(obs, strat = "strat", reverse_prob = reverse_prob, ci = ci)
      } else {
        obs_km <- compute_kaplan(obs, strat = "strat", reverse_prob = reverse_prob)
      }
    }
  } else { # get bins from sim
    obs_km <- NULL
  }
  if(!is.null(kmmc) & (class(bins) == "logical" && bins == FALSE)) {
    msg("Tip: with KMMC-type plots, binning of simulated data is recommended. See documentation for the 'bins' argument for more information.", msg)
  }

  if(!is.null(sim)) {
    # format sim data and compute KM curve CI for simulations
    if (all(c(cols$sim$idv, cols$sim$id, cols$sim$dv) %in% names(sim))) {
      sim$id <- sim[[cols$sim$id]]
      sim$dv <- sim[[cols$sim$dv]]
      sim$time <- sim[[cols$sim$idv]]
    } else {
      stop("Not all required variables were found, please check column definitions for id, dv and time.")
    }
    if(max(sim$dv) > 2) { # guessing DV definition if not just 0/1
      if(max(sim$dv) == 2) { # common approach in NONMEM, 2 = censored
        sim[sim$dv != 1,]$dv <- 1
        msg("Warning: Expected simulated dependent variable to contain only 0 (censored, or no event simerved) or 1 (event simerved). Setting all simulated observations != 1 to 0.", msg)
      } else {
        sim[sim$dv != 1,]$dv <- 1 # some people use DV to indicate the event time.
        msg("Warning: Expected simulated dependent variable to contain only 0 (censored, or no event simerved) or 1 (event simerved). Setting all simulated observations != 1 to 1.", msg)
      }
    }
    if("nonmem" %in% class(sim)) { # necessary due to a bug in NONMEM simulation
      sim <- sim[!(sim$time ==0 & sim$dv == 1),]
    }
    if(max(sim$dv) == 1) {
      if (sum(sim$dv > 0 & sim$dv < 1) > 0) {
        sim[sim$dv > 0  & sim$dv < 1,]$dv <- 0
      }
    }
    if("cens" %in% tolower(names(sim$cens))) { # some people use a 'cens' column to indicate censoring
      cat("Detected extra column with censoring information in simulation data.")
      colnames(sim)[match("cens", tolower(colnames(sim)))] <- "cens"
      sim[sim$cens == 1,]$dv <- 0
    }
    # add sim index number
    sim$sim <- add_sim_index_number(sim, id = cols$sim$id)

    # set last_observation and repeat_obs per sim&id
    sim <- sim %>% group_by(sim, id) %>% mutate(last_obs = 1*(1:length(time) == length(time)), repeat_obs = 1*(cumsum(dv) > 1))

    # filter out stuff and recalculate rtte times
    sim <- sim[sim$dv == 1 | (sim$last_obs == 1 & sim$dv == 0),]
    if(rtte) {
      sim <- sim %>% group_by(sim, id) %>% arrange(sim, id, time) %>% mutate(rtte = 1:length(dv)) %>% arrange(sim, id)
      if(rtte_calc_diff) {
        sim <- relative_times(sim, simulation=TRUE)
      }
    } else {
      sim$sim_id <- paste0(sim$sim, "_", sim$id) # remove duplicate observations rows per id to filter out repeated obs
      sim <- sim[!duplicated(sim$sim_id),]
    }

    n_sim <- length(unique(sim$sim))
    all <- c()
    tmp_bins <- unique(c(0, sort(unique(sim$time)), max(sim$time)))
    if(!(class(bins) == "logical" && bins == FALSE)) {
      if(class(bins) == "logical" && bins == TRUE) {
        bins <- "time"
      }
      if(class(bins) == "character") {
        if (bins == "obs") {
          tmp_bins <- unique(c(0, sort(unique(obs$time)), max(obs$time)))
        } else {
          if (!(bins %in% c("time","data"))) {
            msg(paste0("Note: bining method ", bins," might be slow. Consider using method 'time', or specify 'bins' as numeric vector"), verbose)
          }
          tmp_bins <- unique(c(0, auto_bin(sim %>% mutate(idv=time), type=bins, n_bins = n_bins-1), max(sim$time)))
        }
      }
      if(class(bins) == "numeric") {
        tmp_bins <- unique(c(0, bins, max(obs$time)))
      }
    }
    for (i in 1:n_sim) {
      tmp <- sim %>% filter(sim == i)
      tmp2 <- add_stratification(tmp %>% arrange(id, time), stratify)
      if(!is.null(kmmc) && kmmc %in% names(obs)) {
        tmp3 <- compute_kmmc(tmp2, strat = "strat", reverse_prob = reverse_prob, kmmc = kmmc)
      } else {
        tmp3 <- compute_kaplan(tmp2, strat = "strat", reverse_prob = reverse_prob)
      }
      tmp3$time_strat <- paste0(tmp3$time, "_", tmp3$strat)
      tmp4 <- expand.grid(time = c(0, unique(sim$t)), surv=NA, lower=NA, upper=NA, strat=unique(tmp3$strat))
      tmp4$time_strat <- paste0(tmp4$time, "_", tmp4$strat)
      tmp4[match(tmp3$time_strat, tmp4$time_strat),]$surv <- tmp3$surv
#       tmp4[match(tmp3$time_strat, tmp4$time_strat),]$lower <- tmp3$lower
#       tmp4[match(tmp3$time_strat, tmp4$time_strat),]$upper <- tmp3$upper
      tmp4 <- tmp4 %>% arrange(strat, time)
      tmp4$surv <- locf(tmp4$surv)
      tmp4[,c("bin", "bin_min", "bin_max", "bin_mid")] <- 0
      tmp4$bin <- cut(tmp4$time, breaks = tmp_bins, labels = FALSE, right = TRUE)
      tmp4$bin_min <- tmp_bins[tmp4$bin]
      tmp4$bin_max <- tmp_bins[tmp4$bin+1]
      tmp4$bin_mid <- (tmp4$bin_min + tmp4$bin_max) / 2
      all <- rbind(all, cbind(i, tmp4))
    }
    sim_km <- all %>%
      group_by (strat, bin) %>%
      summarize (bin_mid = head(bin_mid,1),
                 bin_min = head(bin_min,1),
                 bin_max = head(bin_max,1),
                 qmin = quantile(surv, 0.05),
                 qmax = quantile(surv, 0.95),
                 qmed = median(surv),
#                         lower_med = median(lower, 0.05),
#                         upper_med = median(upper, 0.05),
                 step = 0)
  } else {
    sim_km <- NULL
  }

  if (rtte) {
    if(!is.null(sim)) {
      sim_km$rtte <- as.num(gsub(".*rtte=(\\d.*).*", "\\1", sim_km$strat, perl = TRUE))
      if (!is.null(events)) {
        sim_km <- sim_km %>% filter(rtte %in% events)
        # redefine strat factors, since otherwise empty panels will be shown
        sim_km$strat <- factor(sim_km$strat, levels = unique(sim_km$strat))
      }
    }
    if(!is.null(obs)) {
      obs_km$rtte <- as.num(gsub(".*rtte=(\\d.*).*", "\\1", obs_km$strat, perl = TRUE))
      if (!is.null(events)) {
        obs_km <- obs_km %>% filter(rtte %in% events)
        obs_km$strat <- factor(obs_km$strat, levels = unique(obs_km$strat))
      }
    }
  }

  cens_dat <- NULL
  if(show$obs_cens) {
    cens_dat <- data.frame(obs[obs$dv == 0 & obs$time > 0,])
  }

  if (smooth) {
    geom_line_custom <- ggplot2::geom_line
  } else {
    geom_line_custom <- ggplot2::geom_step
  }
  if (!is.null(stratify_original)) {
    if (length(stratify) == 2) {
      sim_km$strat1 <- unlist(strsplit(as.character(sim_km$strat), ", "))[(1:length(sim_km$strat)*2)-1]
      sim_km$strat2 <- unlist(strsplit(as.character(sim_km$strat), ", "))[(1:length(sim_km$strat)*2)]
      obs_km$strat1 <- unlist(strsplit(as.character(obs_km$strat), ", "))[(1:length(obs_km$strat)*2)-1]
      obs_km$strat2 <- unlist(strsplit(as.character(obs_km$strat), ", "))[(1:length(obs_km$strat)*2)]
      cens_dat$strat1 <- unlist(strsplit(as.character(cens_dat$strat), ", "))[(1:length(cens_dat$strat)*2)-1]
      cens_dat$strat2 <- unlist(strsplit(as.character(cens_dat$strat), ", "))[(1:length(cens_dat$strat)*2)]
    }
  }
  if (!is.null(sim)) {
    if (!is.null(stratify_color)) {
      if (length(stratify) == 2) {
        sim_km$strat_color <- sim_km$strat2
      } else {
        sim_km$strat_color <- sim_km$strat
      }
    }
  }

  if (!is.null(obs)) {
    if(!is.null(stratify_color)) {
      if (length(stratify) == 2) {
        obs_km$strat_color <- obs_km$strat2
      } else {
        obs_km$strat_color <- obs_km$strat
      }
    }
    if (show$obs_cens) {
      if(nrow(cens_dat)>0) {
        cens_dat$y <- 1
        cens_dat$strat1 <- NA
        cens_dat$strat2 <- NA
        for (j in 1:length(cens_dat[,1])) {
          tmp <- obs_km[as.character(obs_km$strat) == as.character(cens_dat$strat[j]),]
          cens_dat$y[j] <- rev(tmp$surv[(cens_dat$time[j] - tmp$time) > 0])[1]
          if ("strat1" %in% names(tmp)) {
            cens_dat$strat1[j] <- rev(tmp$strat1[(cens_dat$time[j] - tmp$time) > 0])[1]
          }
          if ("strat2" %in% names(tmp)) {
            cens_dat$strat2[j] <- rev(tmp$strat2[(cens_dat$time[j] - tmp$time) > 0])[1]
          }
        }
        cens_dat <- cens_dat[!is.na(cens_dat$y),]
      }
    }
  }
  show$obs_dv <- TRUE

  # plotting starts here
  vpc_db <- list(sim = sim,
                 sim_km = sim_km,
                 obs = obs,
                 obs_km = obs_km,
                 all = all,
                 stratify = stratify,
                 stratify_original = stratify_original,
                 stratify_color = stratify_color,
                 bins = bins,
                 facet = facet, 
                 kmmc = kmmc,
                 cens_dat = cens_dat,
                 rtte = rtte,
                 type = "time-to-event")
  if(vpcdb) {
    return(vpc_db)
  } else {
    pl <- plot_vpc(vpc_db,
                   show = show, 
                   vpc_theme = vpc_theme,
                   smooth = smooth,
                   log_y = FALSE,
                   title = title,
                   xlab = xlab,
                   ylab = ylab)
    return(pl)
  }
}
