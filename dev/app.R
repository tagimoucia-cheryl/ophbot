# Demo script that predicts next vital sign
rlang::inform('--- Demo script that predicts next vital sign')

# ****
# TODO
# ****

# Generic standalone R code - no data dependencies
# but still needs to be run in the correct order
source('app/libraries.R')
source('app/config.R')
source('app/utils.R')

# Data pipeline with data dependencies
# check these with a call to `exists()` before you run the code
source('app/wrangle_pts.R')
source('app/wrangle_obs.R')

assertthat::assert_that(exists("dtpts"))
assertthat::assert_that(exists("dtobs"))
source('app/wrangle.R')

assertthat::assert_that(exists("mdt"))
source('app/model.R')

assertthat::assert_that(exists("mdt"))
source('app/write.R')

rlang::inform('--- script completed')

