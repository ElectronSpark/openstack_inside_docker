export LOCAL_INT_IP="$(ip route get 8.8.8.8 | sed -E 's/.*src (\S+) .*/\1/;t;d')"
export LOCAL_INT_NAME="$(ip route get 8.8.8.8 | sed -E 's/.*dev (\S+) .*/\1/;t;d')"
export LOCAL_INT_GATEWAY="$(ip route get 8.8.8.8 | sed -E 's/.*via (\S+) .*/\1/;t;d')"