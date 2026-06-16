#!/bin/sh
docker node update --label-add mariadb.primary=true manager1
docker node update --label-add mariadb.replica=true worker1
docker node update --label-add maxscale=true manager1
docker node update --label-add maxscale=true manager2

printf 'StrongRootPasswordHere\n' | docker secret create mysql_root_password -
printf 'StrongAppPasswordHere\n' | docker secret create app_password -
printf 'StrongReplicationPasswordHere\n' | docker secret create replication_password -
printf 'StrongMaxScalePasswordHere\n' | docker secret create maxscale_password -
printf 'StrongMaxScaleMonitorPasswordHere\n' | docker secret create maxscale_monitor_password -

docker stack deploy -c stack.yml mdb
chmod +x scripts/bootstrap-replica.sh
./scripts/bootstrap-replica.sh mdb
