 docker build \
     --file dockerfile-rstudio
     --build-arg http_proxy \
     --build-arg https_proxy \
     --build-arg HTTP_PROXY \
     --build-arg HTTPS_PROXY \
     . -t r363u-tidyv

