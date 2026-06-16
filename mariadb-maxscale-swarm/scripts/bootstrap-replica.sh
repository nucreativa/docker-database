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

echo "==> Create replication + MaxScale users on primary"
docker exec "${PRIMARY_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
REPLPW=$(cat /run/secrets/replication_password)
MXSPW=$(cat /run/secrets/maxscale_password)
MXSMONPW=$(cat /run/secrets/maxscale_monitor_password)

mariadb -uroot -p"${ROOTPW}" <<SQL
CREATE USER IF NOT EXISTS '\''repl'\''@'\''%'\'' IDENTIFIED BY '\'''"${REPLPW}"'\'';
GRANT REPLICATION SLAVE ON *.* TO '\''repl'\''@'\''%'\''; 
GRANT REPLICATION CLIENT ON *.* TO '\''repl'\''@'\''%'\'';

CREATE USER IF NOT EXISTS '\''maxscale'\''@'\''%'\'' IDENTIFIED BY '\'''"${MXSPW}"'\'';
GRANT SELECT, SHOW DATABASES ON *.* TO '\''maxscale'\''@'\''%'\'';

CREATE USER IF NOT EXISTS '\''maxscale_monitor'\''@'\''%'\'' IDENTIFIED BY '\'''"${MXSMONPW}"'\'';
GRANT REPLICATION CLIENT ON *.* TO '\''maxscale_monitor'\''@'\''%'\''; 
GRANT SUPER, RELOAD, PROCESS, SHOW DATABASES, EVENT ON *.* TO '\''maxscale_monitor'\''@'\''%'\'';

FLUSH PRIVILEGES;
SQL
'

echo "==> Dump primary"
docker exec "${PRIMARY_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
mariadb-dump -uroot -p"${ROOTPW}" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --triggers \
  --master-data=2 > /tmp/fullseed.sql
'

docker cp "${PRIMARY_CID}:/tmp/fullseed.sql" ./fullseed.sql
docker cp ./fullseed.sql "${REPLICA_CID}:/tmp/fullseed.sql"

echo "==> Restore into replica"
docker exec "${REPLICA_CID}" bash -lc '
ROOTPW=$(cat /run/secrets/mysql_root_password)
mariadb -uroot -p"${ROOTPW}" < /tmp/fullseed.sql
'

echo "==> Configure replica"
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

echo "==> Done"