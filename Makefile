# Makefile
UID := $(shell id -u)
include .env
export $(shell sed 's/=.*//' .env)

.PHONY: foo
foo:
	echo $(PWD)
	echo $(UID)

# dev set up
.PHONY: dev-up
dev-up: rstudio-run pgweb-run

# build the rstudio image
.PHONY: rstudio-build
rstudio-build: dockerfile-rstudio
	docker build \
		 --file dockerfile-rstudio \
		 --build-arg http_proxy \
		 --build-arg https_proxy \
		 --build-arg HTTP_PROXY \
		 --build-arg HTTPS_PROXY \
		 . -t r4-tidyv

# run the rstudio image
.PHONY: rstudio-run
rstudio-run: 
	@docker run --rm \
		-p 8790:8787 \
		-e PASSWORD=sitrep \
		-e USERID=$(UID) \
		-e ROOT=true \
		-v $(PWD)/work:/home/rstudio/work \
		-v $(PWD)/renv:/home/rstudio/renv \
		-v $(PWD)/libs:/home/rstudio/libs \
		-d \
		--name rstudio-ofelia \
		r4-tidyv    
	@echo "*** Rstudio should be available on port 8790"

# Run pgweb and connect automaticaly to the UDS
.PHONY: pgweb-run
pgweb-run:
	@docker run -p 8791:8081 -d --rm \
		--name pgweb_uds \
		-e DATABASE_URL=postgres://sharris9:$(UDS_PWD)@172.16.149.132:5432/uds?sslmode=disable \
		sosedoff/pgweb
	@echo "*** PGWeb should be available on port 8791"

# clean up dev stuff
.PHONY: dev-clean
dev-clean:
	docker stop rstudio-ofelia
	docker stop pgweb_uds

# fix permissions
.PHONY: fix-permissions
fix-permissions: 
	# Set the group for all files to be docker. All GAE users are in the docker group
	chgrp -R docker work  
	# Grant read, write, and open folder permission for all exisiting files to the docker group, and make new folders created have the docker group
	chmod -R g+rwXs  work 
	# For all the directories in here, make all new files created by default have the right group privileges, irrespective of the user UMASK
	setfacl -R –d –m g::rwX work  



