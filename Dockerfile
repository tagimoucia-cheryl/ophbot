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

COPY odbc/* /etc/

# External packages (CRAN)
RUN install2.r data.table odbc checkmate

# External packages (GitHub)
RUN installGithub.r inform-health-informatics/emapR

# Local development packages
# Mainly as a reproducible way of moving code
ADD src /home/cronbot/src
WORKDIR /home/cronbot/src
RUN make install_packages

# Add your local directory (also called 'app') into 'app'
ADD app /home/cronbot/src

# Ensure all files are owned by the user cronbot
RUN chown -R "1001:1001" /home/cronbot
USER cronbot

# Start the container with a 'dummy' process that prevents the container
# immediately stopping
CMD tail -f /dev/null





