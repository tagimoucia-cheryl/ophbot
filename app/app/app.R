# Demo script that predicts next vital sign
rlang::inform('--- Demo script that predicts next vital sign')

# ****
# TODO
# ****

# Generic standalone R code - no data dependencies
# but still needs to be run in the correct order
source('libraries.R')
source('config.R')
source('utils.R')

# Data pipeline with data dependencies
# check these with a call to `exists()` before you run the code
source('wrangle_pts.R')
source('wrangle_obs.R')

assertthat::assert_that(exists("dtpts"))
assertthat::assert_that(exists("dtobs"))
source('wrangle.R')

assertthat::assert_that(exists("mdt"))
source('model.R')

assertthat::assert_that(exists("mdt"))
source('write.R')

rlang::inform('--- script completed')

