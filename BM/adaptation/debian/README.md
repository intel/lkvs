## Build Debian 12 docker

```bash
docker build --build-arg PROXY=$http_proxy -f <path_to_debian>/Dockerfile.build -t debian
```

PROXY is optional, if you are behind a proxy, you can pass it to the build command.


## Run the Debian 12 docker

```bash
docker run -it --rm --privileged -v ~:/host_root --mount type=bind,source=/dev,target=/dev localhost/debian:latest /bin/bash
```

## Install dependencies locally

```bash
./install_local.sh

```
