This readme (`dev/readme.md`) is distinct from the main readme (`./readme.md`).
It specifically addresses the details of the application that the 'bot' runs.

In this case, we're build a live NEWS score predictor.

Note that _everything_ except for `app.R` and any files in the `app` directory are ignored by the main application. Only these are copied to the docker app image. This also means that your 'app' must maintain relative file paths with respect to this structure.

-|
 |-app.R
 |-app
   |-setup.R
   |-read.R
