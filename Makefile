# Makefile
UID := $(shell id -u)

.PHONY: foo
foo:
	echo $(PWD)
	echo $(UID)

# build the rstudio image
rstudio-build: dockerfile-rstudio
	docker build \
		 --file dockerfile-rstudio \
		 --build-arg http_proxy \
		 --build-arg https_proxy \
		 --build-arg HTTP_PROXY \
		 --build-arg HTTPS_PROXY \
		 . -t r363u-tidyv

# run the rstudio image
.PHONY: rstudio-run
rstudio-run: 
	docker run --rm \
		-p 8790:8787 \
		-e PASSWORD=sitrep \
		-e USERID=$(UID) \
		-e ROOT=true \
		-v $(PWD)/work:/home/rstudio/work \
		-v $(PWD)/renv:/home/rstudio/renv \
		-v $(PWD)/libs:/home/rstudio/libs \
		-d \
		--name rstudio-ofelia \
		r363u-tidyv    
	@echo "*** Rstudio should be available on port 8790"

# clean up rstudio stuff
.PHONY: rstudio-clean
rstudio-clean:
	docker stop rstudio-ofelia

# fix permissions
.PHONY: fix-permissions
fix-permissions: 
	# Set the group for all files to be docker. All GAE users are in the docker group
	chgrp -R docker work  
	# Grant read, write, and open folder permission for all exisiting files to the docker group, and make new folders created have the docker group
	chmod -R g+rwXs  work 
	# For all the directories in here, make all new files created by default have the right group privileges, irrespective of the user UMASK
	setfacl -R –d –m g::rwX work  

