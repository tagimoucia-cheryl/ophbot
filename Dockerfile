# Pull your base docker image
# Using rocker for R but could use python:3.8-slim or similar
FROM rocker/tidyverse:4.0.4

# Remove root privileges from the container process and run as 'cronbot'
RUN groupadd --gid 1001 cronbot && \
    useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash cronbot

# install necessary packages for connecting from R to SQL databases
RUN apt-get update -y && apt-get install -y \
    unixodbc \
    unixodbc-dev \
    tdsodbc \
    odbc-postgresql \
    tzdata

COPY odbc.ini /etc/odbc.ini
COPY odbcinst.ini /etc/odbcinst.ini

RUN install2.r data.table odbc checkmate
RUN installGithub.r inform-health-informatics/emapR

# Add your local directory (also called 'app') into 'app'
ADD app /home/cronbot/app

# Add any local R packages (that don't live in CRAN or github)
# Mainly as a reproducible way of moving code
# RUN R CMD INSTALL /home/cronbot/packages/emapR_0.1.0.tar.gz

# Ensure all files are owned by the user cronbot
RUN chown -R "1001:1001" /home/cronbot
USER cronbot
WORKDIR /home/cronbot/app

# Start the container with a 'dummy' process that prevents the container
# immediately stopping
CMD tail -f /dev/null





