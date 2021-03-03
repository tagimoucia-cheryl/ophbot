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
app:
	Rscript app/monitor_ids.R

