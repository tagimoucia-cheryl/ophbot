# Makefile

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
		-e USERID=$UID \
		-e ROOT=true \
		-v $(pwd)/work:/home/rstudio/work \
		-v $(pwd)/renv:/home/rstudio/renv \
		-v $(pwd)/libs:/home/rstudio/libs \
		-d \
		--name rstudio-ofelia \
		r363u-tidyv    
	@echo "*** Rstudio should be available on port 8790"

# clean up rstudio stuff
.PHONY: rstudio-clean
rstudio-clean:
	docker stop rstudio-ofelia

