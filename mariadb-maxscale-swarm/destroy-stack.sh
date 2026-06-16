#!/bin/sh
docker stack rm mdb
docker secret rm mysql_root_password app_password replication_password maxscale_password maxscale_monitor_password
docker node update --label-rm mariadb.primary manager1
docker node update --label-rm mariadb.replica worker1
docker node update --label-rm maxscale manager1
docker node update --label-rm maxscale manager2