FROM ubuntu:24.04

RUN apt update && apt upgrade -y

RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt install -y snmpd mrtg tzdata \
 && useradd mrtg-user -u 222 -r -M \
 && mkdir /opt/mrtg /var/lib/mrtg /var/lock/mrtg \
 && chown mrtg-user /opt/mrtg /var/lib/mrtg /var/lock/mrtg

WORKDIR /opt/mrtg

USER mrtg-user

CMD ["/bin/bash"]
