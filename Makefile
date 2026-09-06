# 便捷入口（在项目根目录、且已 cp config.env.example config.env 后使用）
#
#   make install
#   make add NAME=alice IP=10.8.0.2
#   make add NAME=bob          # 省略 IP 时自动分配下一个空闲地址
#   make backup
#   make restore DIR=backup/20260101-120000

.PHONY: install add backup restore

install:
	./server/install.sh

add:
	./clients/add-client.sh $(NAME) $(IP)

backup:
	./scripts/backup.sh

restore:
	./scripts/restore.sh $(DIR)
