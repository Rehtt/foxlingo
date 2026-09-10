.PHONY: run-gs
run-gs:
	ADB_SERVER_SOCKET=tcp:127.0.0.1:15037 \
	https_proxy=http://127.0.0.1:7890 \
	flutter run  --host-vmservice-port=51102 --dds-port=51103
