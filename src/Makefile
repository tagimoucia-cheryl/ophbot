# Reproducible way of documenting the commands that this container should manage

hello:
	@echo "Hello World!"

check:
	# check that we have .env and .Renviron

# cd first into the appropriate directory
install_packages:
	cd ./packages; R CMD build dockR
	cd ./packages; R CMD INSTALL dockR_0.1.tar.gz

# this is the default command for the container should manage a series of
# scripts; need to ensure that we have a graceful way of failing
# FIXME: this make does not return the app exit code so appears to fail to ofelia
# see https://askubuntu.com/a/158531
# .PHONY: app
# app:
#	$(shell Rscript app/monitor_ids.R > /dev/null 2>&1 ; echo $$? )

