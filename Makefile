DOCKER_NAME=hermes-webtop
DOCKER_IMAGE_NAME=hermes-webtop
VOLUME_NAME=hermes-webtop-config
BACKUP_FILE=hermes_config_backup.tar.gz
BACKUP_DIR=./backup

.PHONY: backup restore clean

colima-start:
	colima start --profile hermes-webtop --cpu 4 --memory 4 --disk 100

colima-stop:
	colima stop --profile hermes-webtop

colima-delete:
	colima delete -f --data --profile hermes-webtop

start-locally-baked:
	DOCKER_URI=hermes-webtop:latest \
	PUID=$(shell id -u) \
	PGID=$(shell id -g) \
	docker compose up -d
	docker compose logs -f

start:
	PUID=$(shell id -u) \
	PGID=$(shell id -g) \
	docker compose up -d
	docker compose logs -f

stop:
	docker compose down

dev:
	$(MAKE) stop
	$(MAKE) docker-vol-clean
	$(MAKE) docker-build
	$(MAKE) start-locally-baked

docker-image-clean:
	# docker rm -f $$(docker ps -qa)
	docker rm -f $(DOCKER_NAME)

docker-vol-clean:
	docker volume rm -f $(VOLUME_NAME)

docker-clean:
	$(MAKE) stop
	$(MAKE) docker-vol-clean
	docker system prune -af --volumes

backup:
	mkdir -p $(BACKUP_DIR)
	@echo "Backing up volume: $(VOLUME_NAME) to $(BACKUP_DIR)/$(BACKUP_FILE)"
	docker compose down
	@mkdir -p $(BACKUP_DIR)
	docker run --rm \
	  -v $(VOLUME_NAME):/volume \
	  -v $(shell pwd)/$(BACKUP_DIR):/backup \
	  alpine \
	  tar czf /backup/$(BACKUP_FILE) -C /volume .
	
	@echo "Backup complete! Size of file: $$(du -h backup/$(BACKUP_FILE) | awk '{print $$1}')"
	docker compose up -d

restore:
	@test -f "$(BACKUP_DIR)/$(BACKUP_FILE)" || (echo "Error: $(BACKUP_DIR)/$(BACKUP_FILE) does not exist" && exit 1)
	@echo "Restoring volume: $(VOLUME_NAME) from $(BACKUP_DIR)/$(BACKUP_FILE)"
	docker compose down
	docker run --rm \
	  -v $(VOLUME_NAME):/volume \
	  -v $(shell pwd)/$(BACKUP_DIR):/backup \
	  alpine \
	  sh -c "cd /volume && rm -rf * && tar xzf /backup/$(BACKUP_FILE)"
	@echo "Restore complete!"
	docker compose up -d

docker-build:
	docker build -t $(DOCKER_IMAGE_NAME)  -f ./docker/Dockerfile ./docker
