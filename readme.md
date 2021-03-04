This is a template docker arrangement for running a specific script on a schedule.
You need to git clone this to the GAE or your local machine.
It will try and pick up the any local proxies (`http_proxy` etc.).
You must make your own `.env` file from the example `env-example` file.
Then 

```
docker-compose up --build
```

What it should do

* Every 5 mins it will read the last entry from the IDS; if that is not within the last 300 seconds it will raise an alert and 'stop'
* The job result (success/failure) will be posted to the slack channel.

Features

* Creates a docker image using Rocker/tidyverse
* Sets-up ODBC infrastructure for connection to MS-SQL databases (e.g. Epic's Clarity or Caboodle)
* Installs CRAN and GitHub packages (e.g. [emapR](https://github.com/inform-health-informatics/emapR.git))
* Builds and installs local packages (to make parts of the code more transportable)
* Runs `monitor_ids.R` every 5 minutes which could contain any bit of code you wish
* Adjust the schedule as per the instructions [here](https://github.com/mcuadros/ofelia)
* Pushes a status message to slack

It should be relatively trivial to swap this out for a Python version.

Links and references

* [Setting up ofelia](https://github.com/viktorsapozhok/docker-python-ofelia)
* [Building a slack webhook](https://api.slack.com/messaging/webhooks)
