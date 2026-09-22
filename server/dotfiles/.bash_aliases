# Get container id of existing container
dgrep () {
    docker ps -a | grep "$1" | cut -d " " -f 1
}
# Get the id of an image
digrep () {
    docker images -a | grep "$1" | tr -s " " | cut -d " " -f 3
}
# Get the first instance of a docker container with a named
dgrepf () {
    docker ps -a | grep "$1" | cut -d " " -f 1 | head -n 1
}
# Bash into existing named container
dbash () {
    docker exec -it $(dgrepf "$1") /bin/bash
}
