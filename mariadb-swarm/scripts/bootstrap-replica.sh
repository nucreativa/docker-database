#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="${1:-mdb}"
PRIMARY_SERVICE="${STACK_NAME}_mariadb-primary"
REPLICA_SERVICE="${STACK_NAME}_mariadb-replica"

PRIMARY_CID=$(docker ps -q -f label=com.docker.swarm.service.name="${PRIMARY_SERVICE}" | head -n1)
REPLICA_CID=$(docker ps -q -f label=com.docker.swarm.service.name="${REPLICA_SERVICE}" | head -n1)

if [[ -z "${PRIMARY_CID}" || -z "${REPLICA_CID}" ]]; then
  echo "Primary or replica container not found."
  exit 1
fi

ROOT_PW=$(docker secret inspect mysql_root_password --format '{{.Spec.Name}}' >/dev/null 2>&1 || true)

echo "==> Creating replication user on primary"
docker exec "${PRIMARY_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
REPLPW=$(cat /run/secrets/replication_password)
mariadb -uroot -p"${ROOTPW}" <<SQL
CREATE USER IF NOT EXISTS '\''repl'\''@'\''%'\'' IDENTIFIED BY '\'''"${REPLPW}"'\'';
GRANT REPLICATION SLAVE ON *.* TO '\''repl'\''@'\''%'\'';
FLUSH PRIVILEGES;
SQL
'

echo "==> Dumping primary"
docker exec "${PRIMARY_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
mariadb-dump -uroot -p"${ROOTPW}" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --triggers \
  --master-data=2 \
  > /tmp/fullseed.sql
'

echo "==> Copying dump from primary to local"
docker cp "${PRIMARY_CID}:/tmp/fullseed.sql" ./fullseed.sql

echo "==> Copying dump into replica"
docker cp ./fullseed.sql "${REPLICA_CID}:/tmp/fullseed.sql"

echo "==> Restoring dump into replica"
docker exec "${REPLICA_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
mariadb -uroot -p"${ROOTPW}" < /tmp/fullseed.sql
'

echo "==> Configuring replica with GTID"
docker exec "${REPLICA_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
REPLPW=$(cat /run/secrets/replication_password)
mariadb -uroot -p"${ROOTPW}" <<SQL
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='\''mariadb-primary'\'',
  MASTER_PORT=3306,
  MASTER_USER='\''repl'\'',
  MASTER_PASSWORD='\'''"${REPLPW}"'\'',
  MASTER_USE_GTID=slave_pos;
START SLAVE;
SHOW SLAVE STATUS\G
SQL
'

echo "==> Done. Check replica status:"
echo "docker exec -it ${REPLICA_CID} mariadb -uroot -p"