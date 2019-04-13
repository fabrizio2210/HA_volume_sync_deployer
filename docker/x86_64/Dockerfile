FROM debian
MAINTAINER fabrizio2210
ENV DOCKERVERSION=18.03.1-ce
ENV DOCKERARCH=x86_64

# install docker client
RUN apt-get update && apt-get install -y curl dnsutils && apt-get clean
RUN curl -fsSLO https://download.docker.com/linux/static/stable/${DOCKERARCH}/docker-${DOCKERVERSION}.tgz \
    && tar xzvf docker-${DOCKERVERSION}.tgz --strip 1 -C /usr/local/bin docker/docker \
    && rm docker-${DOCKERVERSION}.tgz

COPY src/* /usr/local/bin/

CMD /usr/local/bin/manager.sh

