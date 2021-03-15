# Libraries to install

cran_libs <- c(
   'tidyverse'
  ,'strex'
  ,'lubridate'
  ,'rms'
  ,'Hmisc'
  ,'lme4'
  ,'broom.mixed'
  ,'collections'
  ,'checkmate'
  ,'data.table'
)

github_libs <- c(
  'inform-health-informatics/emapR'
)

# CRAN
install.packages(cran_libs)

# GitHub
for (ll in github_libs) {
  remotes::install_github(ll, upgrade=FALSE)
}

