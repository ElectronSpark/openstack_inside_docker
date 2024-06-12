FROM ubuntu:20.04

RUN apt update -y

# configure mysql database
RUN apt install -y mariadb-server python3-pymysql

COPY <<EOF /etc/profile.d/generate_env.sh
export LOCAL_INT_IP="$(ip route get 8.8.8.8 | sed -E 's/.*via (\S+) .*/\1/;t;d')"
export LOCAL_INT_NAME="$(ip route get 8.8.8.8 | sed -E 's/.*dev (\S+) .*/\1/;t;d')"
export LOCAL_INT_GATEWAY="$(ip route get 8.8.8.8 | sed -E 's/.*src (\S+) .*/\1/;t;d')"
EOF

ADD --chown=root:root database_setup.sh /root/database_setup.sh
CMD [ "/root/database_setup.sh" ]
