## Actuarial Valuation


# Now we do the actuarial valuation at period 1 and 2. 
# In each period, following values will be caculated:
# AL: Total Actuarial liability, which includes liabilities for active workers and pensioners.
# NC: Normal Cost  
# MA: Market value of assets.
# AA: Actuarial value of assets.
# EAA:Expected actuarial value of assets.
# UAAL: Unfunded accrued actuarial liability, defined as AL - NC
# EUAAL:Expected UAAL.
# PR: payroll 
# LG: Loss/Gain, total loss(positive) or gain(negative), Caculated as LG(t+1) = (UAAL(t) + NC(t))(1+i) - C - Ic - UAAL(t+1), 
# i is assumed interest rate. ELs of each period will be amortized seperately.  
# SC: Supplement cost 
# C : Actual contribution, assume that C(t) = NC(t) + SC(t)
# B : Total beneift Payment   
# Ic: Assumed interest from contribution, equal to i*C if C is made at the beginning of time period. i.r is real rate of return. 
# Ia: Assumed interest from AA, equal to i*AA if the entire asset is investible. 
# Ib: Assumed interest loss due to benefit payment, equal to i*B if the payment is made at the beginning of period
# I.r : Total ACTUAL interet gain, I = i.r*(AA + C - B), if AA is all investible, C and B are made at the beginning of period.
# S : Total payrol
# Funded Ratio: AA / AL

# Formulas
# AL(t), NC(t), B(t) at each period are calculated using the workforce matrix and the liability matrix.
# MA(t+1) = AA(t) + I(t) + C(t) - B(t), AA(1) is given
# EAA(t+1)= AA(t) + EI(t)
# AA(t+1) = (1-w)*EAA(t+1) + w*MA(t+1)
# I.r(t) = i.r(t)*[AA(t) + C(t) - B(t)]
# Ia(t) = i * AA(t)
# Ib(t) = i * B(t)
# Ic(t) = i * C(t)
# EI(t) = Ia(t) - Ib(t) + Ic(t) 
# C(t) = NC(t) + SC(t)
# UAAL(t) = AL(t) - AA(t)
# EUAAL(t) = [UAAL(t-1) + NC(t-1)](1+i(t-1)) - C(t-1) - Ic(t-1)
# LG(t) =   UAAL(t) - EUAAL for t>=2 ; LG(1) = -UAAL(1) (LG(1) may be incorrect, need to check)
# More on LG(t): When LG(t) is calculated, the value will be amortized thourgh m years. This stream of amortized values(a m vector) will be 
# placed in SC_amort[t, t + m - 1]
# SC = sum(SC_amort[,t])
# ExF = B(j) - C(j)

# About gains and losses
# In this program, the only source of gain or loss is the difference between assumed interest rate i and real rate of return i.r,
# which will make I(t) != Ia(t) + Ic(t) - Ib(t)



# Set up data frame
penSim0 <- data.frame(year = 1:nyear) %>%
  mutate(AL   = 0, #
         MA   = 0, #
         AA   = 0, #
         EAA  = 0, #
         FR   = 0, #
         ExF  = 0, # 
         UAAL = 0, #
         EUAAL= 0, #
         LG   = 0, #
         NC   = 0, #
         SC   = 0, #
         ADC  = 0, #
         C    = 0, #
         B    = 0, #                        
         I.r  = 0, #                        
         I.e  = 0, #
         Ia   = 0, #                         
         Ib   = 0, #                         
         Ic   = 0, #  
         i    = i,
         i.r  = 0,
         PR   = 0,
         ADC_PR = 0,
         C_PR = 0)

# matrix representation of amortization: better visualization but large size, used in this excercise
SC_amort0 <- matrix(0, nyear + m, nyear + m)
#SC_amort0
# data frame representation of amortization: much smaller size, can be used in real model later.
#SC_amort <- expand.grid(year = 1:(nyear + m), start = 1:(nyear + m))

# select actuarial method for AL and NC
ALx.method <- paste0("ALx.", actuarial_method)
NCx.method <- paste0("NCx.", actuarial_method)


cl <- makeCluster(ncore) 
registerDoParallel(cl)

start_time_loop <- proc.time()

#penSim_results <- list()
#for(k in 1:nsim){

penSim_results <- foreach(k = 1:nsim, .packages = c("dplyr", "tidyr")) %dopar% {
  # k <- 1
  # initialize
  penSim <- penSim0
  SC_amort <- SC_amort0 
  penSim[,"i.r"] <- i.r[, k]
  

  for (j in 1:nyear){
    # j <- 1
    # AL(j)
    
    # AL(j)
    penSim[j, "AL"] <- sum(wf_active[, , j] * ll2[[ALx.method]][[j]] + wf_retired[, , j] * ll2[["ALx.r"]][[j]])
    
    # NC(j)
    penSim[j, "NC"] <- sum(wf_active[, , j] * ll2[[NCx.method]][[j]]) 
    
    # B(j)
    penSim[j, "B"] <-  sum(wf_retired[, , j] * ll2[["B"]][[j]])
    
    # PR(j)
    penSim[j, "PR"] <-  sum(wf_active[, , j] * ll2[["sx"]][[j]])
    
    # MA(j) and EAA(j) 
    if(j == 1) {penSim[j, "MA"] <- switch(init_MA,
                                          MA = MA_0,                 # Use preset value
                                          AL = penSim[j, "AL"]) # Assume inital fund equals inital liability.
                penSim[j, "EAA"] <- switch(init_EAA,
                                           AL = EAA_0,                # Use preset value 
                                           MA = penSim[j, "MA"]) # Assume inital EAA equals inital market value.                      
    } else {
      penSim[j, "MA"]  <- with(penSim, MA[j - 1] + I.r[j - 1] + C[j - 1] - B[j - 1])
      penSim[j, "EAA"] <- with(penSim, AA[j - 1] + I.e[j - 1] + C[j - 1] - B[j - 1])
    }
    
    # AA(j)
    penSim[j, "AA"] <- with(penSim, (1 - w) * EAA[j] + w * MA[j]  )
    
    
    # UAAL(j)
    penSim$UAAL[j] <- with(penSim, AL[j] - AA[j]) 
    
    # LG(j)
    if (j == 1){
      penSim$EUAAL[j] <- 0
      penSim$LG[j] <- with(penSim,  UAAL[j])
    
    } else {
      penSim$EUAAL[j] <- with(penSim, (UAAL[j - 1] + NC[j - 1])*(1 + i[j - 1]) - C[j - 1] - Ic[j - 1])
      penSim$LG[j] <- with(penSim,  UAAL[j] - EUAAL[j])
    }   
    
    # Amortize LG(j)
    SC_amort[j, j:(j + m - 1)] <- amort_LG(penSim$LG[penSim$year == j], i, m, g, end = FALSE, method = amort_method)  
    
    # Supplemental cost in j
    penSim$SC[j] <- sum(SC_amort[, j])
    
    
    # ADC(j)
    penSim$ADC[j] <- with(penSim, NC[j] + SC[j])
    
  
    # C(j)
    penSim$C[j] <- switch(ConPolicy,
                          ADC     = with(penSim, ADC[j]),                          # Full ADC
                          ADC_cap = with(penSim, min(ADC[j], PR_pct_cap * PR[j])), # ADC with cap. Cap is a percent of payroll 
                          Fixed   = with(penSim, PR_pct_fixed * PR[j])             # Fixed percent of payroll
      ) 
    
    # Ia(j), Ib(j), Ic(j)
    penSim$Ia[j] <- with(penSim, AA[j] * i[j])
    penSim$Ib[j] <- with(penSim,  B[j] * i[j])
    penSim$Ic[j] <- with(penSim,  C[j] * i[j])
    
    # I.e(j)
    penSim$I.e[j] <- with(penSim, Ia[j] + Ic[j] - Ib[j])
    
    # I.r(j)
    penSim$I.r[j] <- with(penSim, i.r[j] *( AA[j] + C[j] - B[j]))
    
    # Funded Ratio
    penSim$FR[j] <- with(penSim, 100*AA[j] / exp(log(AL[j]))) # produces NaN when AL is 0.
    
    # External fund
    penSim$ExF[j] <- with(penSim, B[j] - C[j])
    
    # ADC and contribution as percentage of payroll
    penSim$ADC_PR[j] <- with(penSim, ADC[j]/PR[j])
    penSim$C_PR[j]   <- with(penSim, C[j]/PR[j])
    
  }
  
  #penSim_results[[k]] <- penSim
  penSim
}



end_time_loop <- proc.time()

stopCluster(cl)

Time_loop <- end_time_loop - start_time_loop 
