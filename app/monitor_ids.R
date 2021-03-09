# Simple proof of principle script that checks a database has recent updates

# 1. Connects to a remote database
# 2. Queries the database using SQL
# 3. Either raises an error if no recent updates or prints the last update time

# Get's the message date time from the last row of the main IDS table
# Raises an error if it's not recent

# 1. Connects to a remote database
con_ids <- DBI::dbConnect(RPostgres::Postgres(),
                        host = Sys.getenv("IDS_HOST"),
                        port = 5432,
                        user = Sys.getenv("IDS_USER"),
                        password = Sys.getenv("IDS_PWD"),
                        dbname = "ids_live")


# 2. Queries the database using SQL
query <- "SELECT * FROM public.tbl_ids_master m
ORDER BY m.unid DESC
LIMIT 1;"

# Query and then releases the connection
dt <- DBI::dbGetQuery(con_ids, query)
DBI::dbDisconnect(con_ids)

# 3. Either raises an error if no recent updates or prints the last update time

# 3.1. Calculate the time difference between now and the last row
now <- strptime( Sys.time(), "%Y-%m-%d %H:%M:%S")
last_message_datetime <- strptime( dt$messagedatetime, "%Y-%m-%d %H:%M:%S")
delta <- difftime(now, last_message_datetime, units = "secs")

# 3.2. Stop will send an exit code 1 and print the error to the log
if (delta > 300) {
  stop(paste("WARNING: No messages added to IDS for", delta, "seconds"))
} else {
    print(paste("Last message added to IDS", delta, "seconds ago"))
}

