# This program calculates actuarial liabilities, normal costs, benefits, and other values that will be used
# in the simulation model

start_time_liab <- proc.time()

# 1. Decrement table ####
# For now, we assume all decrement rates do not change over time. 
# Use decrement rates from winklevoss.  
load("Data/winklevossdata.RData")

# Create decrement table and calculate probability of survival
decrement <- expand.grid(age = range_age, ea = range_ea) %>% 
  left_join(filter(gam1971, age>=20)) %>%    # mortality 
  left_join(term2) %>%                       # termination
  left_join(disb)  %>%                       # disability
  left_join(dbl)   %>%                       # mortality for disabled
  left_join(er)    %>%                       # early retirement
  select(ea, age, everything()) %>%          
  arrange(ea, age)  %>% 
  filter(age >= ea) %>%
  group_by(ea)
  
# Now assume the decrement tables contain multiple decrement rates(probabilities) rather than single decrement rates.
# If the decrement tables provide single decrement rates, we need to convert them to multiple decrement rates in a consistent way.   
# At least for TPAF, the multiple decrement rates (probabilities) are provided in AV.  
  
  # For active(".a")
  mutate(qxt.a   = qxt.p         * (1 - qxd.p/2) * (1 - qxm.p/2),
         qxd.a   = (1 - qxt.p/2) * qxd.p         * (1 - qxm.p/2),
         qxm.a   = (1 - qxt.p/2) * (1 - qxd.p/2) * qxm.p, 
         # qxr.a   = ifelse(age == 64, 1 - qxm.a  - qxtnv.a - qxd.a, 0), 
         qxr.a   = ifelse(age == 64, (1 - qxt.p)*(1 - qxd.p)*(1 - qxm.p), 0) # This formula yields more accurate values than the one above, which uses approximate probabilities. 
  ) %>%
  
  # For terminated(".t"), target status are dead and retired.
  # Terminated workers will never enter the status of "retired". Rather, they will begin to receive pension benefits 
  # when reaching age 65, but still with the status "terminated". So now we do not need qxr.t
  mutate(qxm.t   = qxm.p) %>%
  
  # For disabled(".d"), target status are dead. Note that we need to use the mortality for disabled 
  # Note the difference from the flows 3Darray.R. Disabled can not become retired here. 
  mutate(qxm.d = qxmd.p ) %>%
  
  # For retired(".r"), the only target status is "dead". Note that in practice retirement mortality may differ from the regular mortality.
  mutate(qxm.r   = qxm.p) %>% 
  
  # Calculate various survival probabilities
  mutate( pxm = 1 - qxm.p,
          pxT = (1 - qxm.p) * (1 - qxt.p) * (1 - qxd.p),
          px65m = order_by(-age, cumprod(ifelse(age >= 65, 1, pxm))), # prob of surviving up to 65, mortality only
          px65T = order_by(-age, cumprod(ifelse(age >= 65, 1, pxT))), # prob of surviving up to 65, composite rate
          p65xm = cumprod(ifelse(age <= 65, 1, lag(pxm))))            # prob of surviving to x from 65, mortality only

# 2. Salary scale #### 
# We start out with the case where 
# (1) the starting salary at each entry age increases at the rate of productivity growth plus inflation.
# (2) The starting salary at each entry age are obtained by scaling up the the salary at entry age 20,
#     hence at any given period, the age-30 entrants at age 30 have the same salary as the age-20 entrants at age 30. 

# Notes:
# At time 1, in order to determine the liability for the age 20 entrants who are at age 110, we need to trace back 
# to the year when they are 20, which is -89. 

# scale for starting salary 
growth <- data.frame(start.year = -89:nyear) %>%
  mutate(growth = (1 + infl + prod)^(start.year - 1 ))

# Salary scale for all starting year
salary <- expand.grid(start.year = -89:nyear, ea = range_ea, age = 20:64) %>% 
  filter(age >= ea) %>%
  arrange(start.year, ea, age) %>%
  left_join(merit) %>% left_join(growth) %>%
  group_by(start.year, ea) %>%
  mutate( sx = growth*scale*(1 + infl + prod)^(age - min(age)))


# 3. Individual AL and NC by age and entry age ####

liab <- expand.grid(start.year = -89:nyear, ea = range_ea, age = range_age) %>%
  left_join(salary) %>% 
  right_join(decrement) %>%
  arrange(start.year, ea, age) %>%
  group_by(start.year, ea) %>%
  # Calculate salary and benefits
  mutate(# sx = scale * (1 + infl + prod)^(age - min(age)),   # Composite salary scale
    year = start.year + age - ea,                      # year index in the simulation
    vrx = v^(65-age),                                  # discount factor
    Sx = ifelse(age == min(age), 0, lag(cumsum(sx))),  # Cumulative salary
    yos= age - min(age),                               # years of service
    n  = pmin(yos, fasyears),                          # years used to compute fas
    fas= ifelse(yos < fasyears, Sx/n, (Sx - lag(Sx, fasyears))/n), # final average salary
    fas= ifelse(age == min(age), 0, fas),
    Bx = benfactor * yos * fas,                        # accrued benefits
    bx = lead(Bx) - Bx,                                # benefit accrual at age x
    #ax = ifelse(age < 65, NA, get_tla(pxm, i)),        
    ax = get_tla(pxm, i),                              # Since retiree die at 110 for sure, the life annuity is equivalent to temporary annuity up to age 110. 
    ayx = c(get_tla2(pxT[age <= 65], i), rep(0, 45)),                # need to make up the length of the vector up to age 110
    ayxs= c(get_tla2(pxT[age <= 65], i,  sx[age <= 65]), rep(0, 45)),  # need to make up the length of the vector up to age 110
    B   = ifelse(age>=65, Bx[age == 65], 0)            # annual benefit 
  ) %>%
  
  #(liab %>% filter(start.year == -89, ea == 20, age >= 65) %>% select(pxm))$pxm %>% get_tla(i)
  #(liab %>% filter(start.year == -89, ea == 20, age <= 65) %>% select(pxT))$pxT %>% get_tla2a(i)
  
  
  # Calculate normal costs (following Winklevoss, normal costs are calculated as a multiple of PVFB)
  mutate(
    PVFBx = Bx[age == 65] * ax[age == 65] * vrx * px65T,
    NCx.PUC = bx * ax[age == 65] * px65T * vrx,                                         # Normal cost of PUC
    NCx.EAN.CD = PVFBx[age == min(age)] / ayx[age == 65],                               # Normal cost of EAN, constant dollar
    NCx.EAN.CP = PVFBx[age == min(age)] / (sx[age == min(age)] * ayxs[age == 65]) * sx  # Normal cost of EAN, constant percent
  ) %>% 
  # Calculate actuarial liablity
  mutate(
    ALx.PUC = Bx/Bx[age == 65] * PVFBx,
    ALx.EAN.CD = ayx/ayx[age == 65] * PVFBx,
    ALx.EAN.CP = ayxs/ayxs[age == 65] * PVFBx,
    ALx.r      = ax * Bx[age == 65]             # Remaining liability(PV of unpaid benefit) for retirees, identical for all methods
  ) %>% 
  ungroup %>% 
  select(start.year, year, ea, age, everything()) 

# 4. Calculate Total Actuarial liabilities and Normal costs 

# Define a function to extract the variables in a single time period
extract_slice <- function(Var, Year,  data = liab){
  # This function extract information for a specific year.
  # inputs:
  # Year: numeric
  # Var : character, variable name 
  # data: name of the data frame
  # outputs:
  # Slice: data frame. A data frame with the same structure as the workforce data.
  Slice <- data %>% ungroup %>% filter(year == Year) %>% 
    select_("ea", "age", Var) %>% arrange(ea, age) %>% spread_("age", Var, fill = 0)
  rownames(Slice) = Slice$ea
  Slice %<>% select(-ea) %>% as.matrix
  return(Slice)
}

# Extract variables in liab that will be used in the simulation, and put them in a list.
# Storing the variables this way can significantly boost the speed of the loop. 

var.names <- liab %>% select(B:ALx.r) %>% colnames()

# 
# #cl <- makeCluster(ncore)
# #registerDoParallel(cl)
# liab_list <- alply(var.names, 1, function(var){
#   alply(1:100,1, function(n) extract_slice(var, n))
# },
# #.parallel = TRUE,
# #.paropts = list(.packages = c("dplyr", "tidyr"))
# # Parellel does not work here b/c it does not recognize objects outside the function. 
# .progress = "text"
# )
# # stopCluster(cl)
# 
# names(liab_list) <- var.names



# a faster way to create liab_list instead of extract_slice and using aply twice
# the speed comes from processing the entire df first and setting the data frame up in matrix format before extracting the matrices into the list
var.names <- liab %>% select(B:ALx.r) %>% colnames()
a <- proc.time()
lldf <- liab %>% ungroup %>% # I don't think liab is grouped, but just in case...
  filter(year %in% 1:100) %>%
  select(year, ea, age, one_of(var.names)) %>% 
  right_join(expand.grid(year=1:100, ea=range_ea, age=range_age)) %>% # make sure we have all possible combos
  gather(variable, value, -year, -ea, -age) %>%
  spread(age, value, fill=0) %>%
  select(variable, year, ea, everything()) %>%
  arrange(variable, year, ea) # this df is in the same form and order, within each var, as the liab_list of matrices (vars may be in a different order)


# microbenchmark(
# ll2[["NCx.PUC"]]$`3` + ll2[["NCx.PUC"]]$`3`,
# ll2$NCx.PUC$`3` + ll2$NCx.PUC$`3`,
# )
  
# might be possible to stop here, but continue and create an equivalent list
f.inner <- function(df.inner) as.matrix(df.inner[-c(1:3)])
f.outer <- function(df.outer) lapply(split(df.outer, df.outer$year), f.inner) # process each year
ll2 <- lapply(split(lldf, lldf$variable), f.outer) # process each variable
proc.time() - a

# compare year 3 for variable NCx.PUC
# ll2$NCx.PUC$`3`
# liab_list$NCx.PUC$`3`

end_time_liab <- proc.time()

Time_liab <- end_time_liab - start_time_liab




#eg. extract "B" for year 1, a matrix is returned
#liab_list[["B"]][[1]]


# a <- proc.time()
# extract_slice("NCx.EAN.CP",1)
# extract_slice("NCx.EAN.CD",1)
# extract_slice("NCx.PUC", 1)
# b <- proc.time()
# b-a
# 
# 
# extract_slice("ALx.EAN.CP",1)
# extract_slice("ALx.EAN.CD",1)
# extract_slice("ALx.PUC", 1)
# extract_slice("ALx.r", 1)
# 
# 
# extract_slice("B", 1) # note that in the absence of COLA, within a time period older retirees receive less benefit than younger retirees do.
# b <- proc.time()
# b-a
# 
# 
# # Total AL for Active participants
# sum(wf_active[, , 1] * extract_slice("ALx.EAN.CP",1))
# sum(wf_active[, , 1] * extract_slice("ALx.EAN.CD",1))
# sum(wf_active[, , 1] * extract_slice("ALx.PUC",1))
# 
# 
# # Total Normal Costs
# sum(wf_active[, , 1] * extract_slice("NCx.EAN.CP",1))
# sum(wf_active[, , 1] * extract_slice("NCx.EAN.CD",1))
# sum(wf_active[, , 1] * extract_slice("NCx.PUC",1))
# 
# # Total AL for retirees
# sum(wf_retired[, , 1] * extract_slice("ALx.r",1))
# 
# # Total benefit payment
# sum(wf_retired[, , 1] * extract_slice("B",1))
