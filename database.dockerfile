FROM ubuntu:20.04

RUN apt update -y

# configure mysql database
RUN apt install -y mariadb-server
# mysql client
RUN apt install -y python3-pymysql 

RUN apt install -y vim
RUN apt install -y iputils-ping tcpdump
RUN apt install -y net-tools
RUN apt install -y tini

ADD --chown=root:root ./database_setup.sh /root/database_setup.sh
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

WORKDIR /root
USER root
RUN apt autoclean -y & apt autoremove -y
RUN echo "source /etc/profile.d/99-generate_env.sh" >> /etc/bash.bashrc
CMD ["tini", "--", "/root/database_setup.sh"]