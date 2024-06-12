FROM rabbitmq:3.8.2

ADD config/rabbitmq/rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
ADD config/rabbitmq/definitions.json /etc/rabbitmq/definitions.json