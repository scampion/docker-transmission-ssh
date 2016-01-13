FROM debian:jessie
MAINTAINER Sebastien Campion <seb@scamp.fr>

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install openssh-server
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install openssl
RUN useradd -m -d /home/scampion -p $(openssl passwd -1 'temp') -G sudo -s /bin/bash scampion
RUN sed -i -e "s/PermitRootLogin\syes/PermitRootLogin no/g" /etc/ssh/sshd_config
ADD ./start.sh /start.sh
RUN chmod 755 /start.sh
EXPOSE 22

RUN export DEBIAN_FRONTEND='noninteractive' && \
    apt-get update -qq && \
    apt-get install -qqy --no-install-recommends transmission-daemon curl \
                $(apt-get -s dist-upgrade|awk '/^Inst.*ecurity/ {print $2}') &&\
    apt-get clean && \
    dir="/var/lib/transmission-daemon" && \
    rm $dir/info && \
    mv $dir/.config/transmission-daemon $dir/info && \
    rmdir $dir/.config && \
    usermod -d $dir debian-transmission && \
    [ -d $dir/downloads ] || mkdir -p $dir/downloads && \
    [ -d $dir/incomplete ] || mkdir -p $dir/incomplete && \
    [ -d $dir/info/blocklists ] || mkdir -p $dir/info/blocklists && \
    file="$dir/info/settings.json" && \
    sed -i '/"peer-port"/a\    "peer-socket-tos": "lowcost",' $file && \
    sed -i '/"port-forwarding-enabled"/a\    "queue-stalled-enabled": true,' \
                $file && \
    sed -i '/"queue-stalled-enabled"/a\    "ratio-limit-enabled": true,' \
                $file && \
    sed -i '/"rpc-whitelist"/a\    "speed-limit-up": 10,' $file && \
    sed -i '/"speed-limit-up"/a\    "speed-limit-up-enabled": false,' $file && \
    chown -Rh debian-transmission. $dir && \
    rm -rf /var/lib/apt/lists/* /tmp/*
COPY start.sh /usr/bin/

VOLUME ["/var/lib/transmission-daemon"]

EXPOSE 9091 51413/tcp 51413/udp

ENTRYPOINT ["start.sh"]
