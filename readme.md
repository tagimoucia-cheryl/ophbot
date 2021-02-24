This is a template docker arrangement for running a specific script on a schedule.
You need to git clone this to the GAE or your local machine.
It will try and pick up the any local proxies (`http_proxy` etc.).
You must make your own `.env` file from the example `env-example` file.
Then 

```
docker-compose up --build
```

What it should do

* Every 10 seconds it will run a 'Hello World!' R script
* The job result (success/failure) will be posted to the slack channel.

Features

* Runs `hello.R` every 10 seconds which could contain any bit of code you wish
* Adjust the schedule as per the instructions [here](https://github.com/mcuadros/ofelia)
* Pushes a status message to slack

It should be relatively trivial to swap this out for a Python version.

Links and references

* [Setting up ofelia](https://github.com/viktorsapozhok/docker-python-ofelia)
* [Building a slack webhook](https://api.slack.com/messaging/webhooks)
