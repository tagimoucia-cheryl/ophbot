docker run --rm \
    -p 8790:8787 \
    -e PASSWORD=sitrep \
    -e USERID=$UID \
    -e ROOT=true \
    -v $(pwd)/work:/home/rstudio/work \
    -v $(pwd)/renv:/home/rstudio/renv \
    -v $(pwd)/libs:/home/rstudio/libs \
    -d \
    r363u-tidyv    

