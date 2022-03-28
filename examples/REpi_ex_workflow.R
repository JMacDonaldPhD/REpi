rm(list = ls())

# (Skip this section if latest REpi version is installed)
# ==== Installing REpi ====

# Will need devtools to install from github
#install.packages("devtools")

# install package
# devtools::install_github("JMacDonaldPhD/REpi", ref = "main")

# ==== Using REpi (Particle Filter Example) ====

library(REpi)
# Random Seed for reproducibility
set.seed(1)

# ==== Construct Epidemic Model ====
M <- 5 # No. meta-populations
N_M <- rep(1e3, M) # Population size in each meta-population
endTime <- 1 # An end time for simulation of the epidemic


# Discrete-Time (Chain-Binomial) Epidemic model which returns 
# functions for epidemic simulation and log-density calculation.
# This simulates over 30 days so most of the epidemic is observed.
# The endTime given above will refer to the amount of timepoints
# which will be observed. This will become clear later.
epiModel <- metaSIR_simple(N_M, endTime = 30)

# Epidemic Parameters
theta <- c(0.05, 1, 0.25) # Global Infection, Local Infection, Removal respectively
I0 <- c(50, rep(0, M - 1)) # Initial number of infectives in each population

# Simulate a realisation of the epidemic 
X_sim <- epiModel$sim(param = list(I0, theta))

# Calculate the log-density of simulated Epidemic
epiModel$llh(X_sim, theta)


# ==== Construct Observation Model ====

# Constructs a Case Ascertation (Binomial sample of infections) 
# Observation model which takes an underlying epidemic as its argument,
# returns sampling and log-likelihood calculation functions.
# This might change to look more like R's 'r', 'd' etc. convention.
obsModel <- caseAscObsModel_simple(X_sim)


# = Sampling and Log-likelihood calculation =
alpha <- 0.1 # The probability that an infection is detected on any given day.

# Simulate a sample from X_sim
y <- obsModel$sample(0.1)

# Calculate the log-density of the sample y
obsModel$llh(y, alpha)

# Reduce sample to days of interest. Generating the data 
# this way ensures that the same sample is generated
# if the random seed is the same. Then the sample can
# be truncated accordingly.
y <- y[,1:endTime, drop = F]


# Reconstruct epidemic model so simulate only the
# days of interest
epiModel <- metaSIR_simple(N_M, endTime = endTime)

# Convert Initial Infectives into the complete Initial State
X_0 <- matrix(nrow = M, ncol = 3)
X_0[,1] <- N_M - I0
X_0[,2] <- I0
X_0[,3] <- rep(0, M)

# Example of how to construct a bootstrap particle filter
particleFilter <- BS_PF(y, X_0, obsFrame = caseAscObsModel_simple, epiModel = epiModel)

# Returns Log-likelihood
particleFilter(K = 10, theta, alpha)


# Looks at the distribution of the Particle Filter Estimate
PF_sample <- replicate(1000, particleFilter(K = 10, theta, alpha))
plot(density(PF_sample), main=paste0("var(log estimate) = ", var(PF_sample), collapse = ""))

# Adapt_BS_PF chooses K particles such that var of the log-likelihood
# estimate is below 1. (Only adapts by increasing K, so may end up 
# with slightly too many particles)
K <- Adapt_BS_PF(K0 = 10, particleFilter, theta, alpha)

# Define prior for epidemic parameters
logPrior <- function(param){
  return(sum(dunif(param, 0, 10, log = TRUE)))
}

# Adapt the MCMC proposal parameters
lambda0 <- 1e-4
V0 <- diag(1, length(theta))
adapt_step <- adapt_particleMCMC(init = theta, epiModel = epiModel, obsFrame = caseAscObsModel_simple,
                                 y, X0 = X_0, alpha, logPrior, lambda0, V0, K = K, noIts = 1e4)
# Checks whether proposal scale parameter has stabilised (similar thing can be done with covariance parameters
# but they are not stored as of yet)
par(mfrow = c(1,1))
plot(adapt_step$lambda_vec, type = 'l')

# Run MCMC with adapted proposal parameters
MCMC_sample <- particleMCMC(init = theta, epiModel = epiModel, obsFrame = caseAscObsModel_simple,
                            y, X0 = X_0, alpha, logPrior, lambda = adapt_step$lambda,
                            V = adapt_step$V, K = K, noIts = 1e4)


# Save a plot of epidemic output
jpeg(filename = "testParticleMCMC.jpeg", width = 480*3, height = 480*3)
plotMCMC(MCMC_sample$draws[,1:3], theta, expressions = c(expression(beta[G]), expression(beta[L]),
                                                   expression(gamma)))
dev.off()