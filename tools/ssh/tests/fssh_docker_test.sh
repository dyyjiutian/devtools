#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 Dockerfile client-test fssh-script" >&2
    exit 1
fi

dockerfile="$1"
client_test="$2"
fssh_script="$3"
work=$(mktemp -d "${TMPDIR:-/tmp}/fssh-docker.XXXXXX")
suffix="$(basename "$work" | tr '[:upper:]' '[:lower:]')"
image="${suffix}:test"
network="${suffix}-network"
server1="${suffix}-server1"
server2="${suffix}-server2"
client="${suffix}-client"

cleanup() {
    docker rm -f "$client" "$server1" "$server2" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    docker image rm "$image" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

cp "$dockerfile" "$work/Dockerfile"
docker build -t "$image" "$work"
docker network create --internal "$network" >/dev/null
for container in "$server1" "$server2" "$client"; do
    docker run -d --name "$container" --network "$network" "$image" >/dev/null
done

test_credential="$(openssl rand -hex 16)"
for container in "$server1" "$server2"; do
    docker exec -e TEST_PASSWORD="$test_credential" "$container" bash -c '
        set -euo pipefail
        printf "fssh:%s\n" "$TEST_PASSWORD" | chpasswd
        printf "fsshother:%s\n" "$TEST_PASSWORD" | chpasswd
        ssh-keygen -A >/dev/null
        /usr/sbin/sshd -o PasswordAuthentication=yes -o PubkeyAuthentication=yes \
            -o UsePAM=no -o Port=22 -o Port=2222
    '
done

ip1=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$server1")
ip2=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$server2")
[[ -n "$ip1" && -n "$ip2" && "$ip1" != "$ip2" ]]

docker cp "$fssh_script" "$client:/tmp/fssh.sh"
docker cp "$client_test" "$client:/tmp/fssh_docker_client.sh"
docker exec "$client" install -d -m 700 -o fssh -g fssh /home/fssh/.ssh
for item in "$server1:$ip1" "$server2:$ip2"; do
    container="${item%%:*}"
    ip="${item#*:}"
    key=$(docker exec "$container" cat /etc/ssh/ssh_host_ed25519_key.pub)
    printf '%s %s\n[%s]:2222 %s\n' "$ip" "$key" "$ip" "$key" >>"$work/known_hosts"
done
docker cp "$work/known_hosts" "$client:/home/fssh/.ssh/known_hosts"
docker exec "$client" chown fssh:fssh /home/fssh/.ssh/known_hosts
docker exec -u fssh -e HOME=/home/fssh -e SSHPASS="$test_credential" \
    "$client" bash /tmp/fssh_docker_client.sh "$ip1" "$ip2"
