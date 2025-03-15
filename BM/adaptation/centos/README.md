## Build CentOS 9 Stream docker

```bash
docker build --build-arg PROXY=$http_proxy -f Dockerfile.build -t centos9
```

PROXY is optional, if you are behind a proxy, you can pass it to the build command.


## Run the Debian 12 docker

```bash
docker run -it --privileged -v /:/host_fs --mount type=bind,source=/dev,target=/dev localhost/centos:stream9 /bin/bash
```

## Install dependencies locally

```bash
./install_local.sh

```
