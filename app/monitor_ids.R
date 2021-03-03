# Steve Harris
# 2021-02-26

# Get's the message date time from the last row of the main IDS table
# Raises an error if it's not recent
# Sends that error to slack as a notification

con_ids <- DBI::dbConnect(RPostgres::Postgres(),
                        host = Sys.getenv("IDS_HOST"),
                        port = 5432,
                        user = Sys.getenv("IDS_USER"),
                        password = Sys.getenv("IDS_PWD"),
                        dbname = "ids_live")


query <- "SELECT * FROM public.tbl_ids_master m
ORDER BY m.unid DESC
LIMIT 1;"

dt <- DBI::dbGetQuery(con_ids, query)
DBI::dbDisconnect(con_ids)

now <- strptime( Sys.time(), "%Y-%m-%d %H:%M:%S")
last_message_datetime <- strptime( dt$messagedatetime, "%Y-%m-%d %H:%M:%S")
delta <- difftime(now, last_message_datetime, units = "secs")

if (delta > 300) {
  stop(paste("WARNING: No messages added to IDS for", delta, "seconds"))
} 

print(paste("Last message added to IDS", delta, "seconds ago"))


