# Libraries to install

cran_libs <- c(
 'DBI'
,'devtools'
,'lubridate'
,'janitor'
,'ggplot2'
,'remotes'
,'rmarkdown'
,'lubridate' # not part of tidyverse
,'ggplot2'
,'plotly'
,'RPostgres'
,'data.table'
,'assertthat'
,'PostcodesioR'
,'purrr'
,'magrittr'
,'readr'
,'odbc'
,'collections'
,'strex'
,'merlin'
,'tidyverse'
,'Hmisc'
,'rms'
,'lme4'
,'merTools'
,'broom.mixed'
,'checkmate'
)
install.packages('checkmate')

for (ll in cran_libs) {
  renv::install(ll)
}

# local work
remotes::install_github('inform-health-informatics/emapR', upgrade=FALSE)
