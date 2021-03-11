## Utilities to develop a full machine learning pipeline on EMAP
UID := $(shell id -u)
# These two lines make local environment variables available to Make
include .env
export $(shell sed 's/=.*//' .env)

# Self-documenting help; any comment line starting ## will be printed
# https://swcarpentry.github.io/make-novice/08-self-doc/index.html
## help             : call this help function
.PHONY: help
help : Makefile
	@sed -n 's/^##//p' $<

## app-build        : builds the app
.PHONY: app-build
app-build:
	docker-compose build


## app-run          : runs the app as per the frequency defined in docker-compose
##                    (a log will also run automatically; this can be cancelled by Ctrl-C)
.PHONY: app-run
app-run:
	docker-compose up -d
	docker-compose logs -f

## app-clean        : cleans the app up
.PHONY: app-clean
app-clean:
	docker-compose down


## dev-build        : builds the dev containers (just Rstudio for now)
.PHONY: dev-build
dev-build: rstudio-build

## dev-up           : sets up Rstudio (8790) and PGWeb (8791)
##                    e.g. go to http://172.16.149:155:8790 for RStudio
##                    You may need to edit the port numbers if others are using this set-up on the same machine
.PHONY: dev-up
dev-up: rstudio-run pgweb-run

## rstudio-build    : builds the Rstudio container
.PHONY: rstudio-build
rstudio-build: dockerfile-rstudio
	docker build \
		 --file dockerfile-rstudio \
		 --build-arg http_proxy \
		 --build-arg https_proxy \
		 --build-arg HTTP_PROXY \
		 --build-arg HTTPS_PROXY \
		 . -t r4-tidyv

## rstudio-run      : runs the Rstudio container (the username is rstudio)
##                    (the password to Rstudio is set in this section of the Makefile)
.PHONY: rstudio-run
rstudio-run: 
	@docker run --rm \
		-p 8790:8787 \
		-e PASSWORD=notbot \
		-e USERID=$(UID) \
		-e ROOT=true \
		-v $(PWD)/dev:/home/rstudio/dev \
		-v $(PWD)/renv:/home/rstudio/renv \
		-d \
		--name rstudio-ofelia \
		r4-tidyv    
	@echo "*** Rstudio should be available on port 8790"

## pgweb-run        : Run pgweb and connect automaticaly to the UDS
.PHONY: pgweb-run
pgweb-run:
	@docker run -p 8791:8081 -d --rm \
		--name pgweb_uds \
		-e DATABASE_URL=postgres://sharris9:$(UDS_PWD)@172.16.149.132:5432/uds?sslmode=disable \
		sosedoff/pgweb
	@echo "*** PGWeb should be available on port 8791"

# clean up dev stuff
## dev-clean        : Stops and removes the RStudio and pgweb containers
.PHONY: dev-clean
dev-clean:
	docker stop rstudio-ofelia
	docker stop pgweb_uds

# Useful generic code chunks
# Not part of the main makefile
# fix permissions on the GAE
.PHONY: fix-permissions
fix-permissions: 
	# Set the group for all files to be docker. All GAE users are in the docker group
	chgrp -R docker work  
	# Grant read, write, and open folder permission for all exisiting files to the docker group, and make new folders created have the docker group
	chmod -R g+rwXs  work 
	# For all the directories in here, make all new files created by default have the right group privileges, irrespective of the user UMASK
	setfacl -R –d –m g::rwX work  



