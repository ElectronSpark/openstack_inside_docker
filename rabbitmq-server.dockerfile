FROM rabbitmq:3.8.2

WORKDIR /root
USER root
RUN apt update -y
RUN apt install -y python3-pymysql 
RUN apt install -y net-tools
RUN apt install -y tini
RUN apt autoclean -y & apt autoremove -y

ADD config/rabbitmq/rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
ADD config/rabbitmq/definitions.json /etc/rabbitmq/definitions.json
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

WORKDIR /root
USER root
RUN apt autoclean -y & apt autoremove -y
RUN echo "source /etc/profile.d/99-generate_env.sh" >> /etc/bash.bashrc
RUN source /etc/profile.d/99-generate_env.sh