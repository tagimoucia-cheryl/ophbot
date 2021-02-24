# Pull your base docker image
# TODO move the R and Python these out into separate dockerfiles

# PYTHON
# FROM python:3.8-slim

# R
FROM rocker/r-ver:4.0.0-ubuntu18.04

# Remove root privileges from the container process and run as 'cronbot'
RUN groupadd --gid 1000 cronbot && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash cronbot

# Create a directory called 'app' to hold your code
RUN mkdir /home/cronbot/app
# Add your local directory (also called 'app') into 'app'
ADD app /home/cronbot/app/app

# Python : install any libraries
# RUN cd /home/user/app && \
#     pip install --no-cache-dir .

# Ensure all files are owned by the user cronbot
RUN chown -R "1000:1000" /home/cronbot
USER cronbot
WORKDIR /home/cronbot/app

# Start the container with a 'dummy' process that prevents the container
# immediately stopping
CMD tail -f /dev/null
