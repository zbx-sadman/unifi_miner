make
#exit
chown zabbix:zabbix unifi.so


mv -f ./unifi.so /usr/local/lib/zabbix
service zabbix-agent restart
ps ax | grep zabbix_agentd

