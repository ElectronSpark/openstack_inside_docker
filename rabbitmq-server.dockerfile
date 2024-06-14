FROM rabbitmq:3.8.2

RUN apt update -y
RUN apt install -y python3-pymysql 
RUN apt install -y net-tools

ADD --chown=rabbitmq:rabbitmq config/rabbitmq/rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
ADD --chown=rabbitmq:rabbitmq config/rabbitmq/definitions.json /etc/rabbitmq/definitions.json
ADD --chown=root:root ./config/profile.d/99-generate_env.sh /etc/profile.d/99-generate_env.sh

RUN apt autoclean -y & apt autoremove -y
