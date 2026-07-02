#!/usr/bin/env bash
set -x
set -eo pipefail

# Docker
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:="docker-compose.yml"}
DOCKER_PROJECT_DIR=${DOCKER_PROJECT_DIR:="."}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:="auditor"}
# Collector build
RELEASE_MODE=${RELEASE_MODE:=false}
TARGET_ARCH=${TARGET_ARCH:="x86_64-unknown-linux-musl"}


function stop_container () {
	echo >&2 "Stopping container"
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		down
}

function start_container() {
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		up -d
	# Copy slurm.conf to container
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		cp ./slurm.conf slurm:/etc/slurm/slurm.conf
	# Copy Slurm collector to container
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		cp \
		./auditor-slurm-collector \
		slurm:/auditor-slurm-collector
	# Copy config for collector
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		cp ./collector_config.yaml slurm:/collector_config.yaml
	# Copy basic batch script
	docker compose \
		--file $DOCKER_COMPOSE_FILE \
		--project-directory=$DOCKER_PROJECT_DIR \
    --project-name="$COMPOSE_PROJECT_NAME" \
		cp ./batch.sh slurm:/batch.sh

	# docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" chown slurm:slurm /auditor-slurm-collector /collector_config.yaml
	docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" mkdir -p /collector_logs
	docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" chown slurm:slurm /collector_logs

	COUNTER=0
	until docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" scontrol ping; do
		>&2 echo "Slurm container is still unavailable - sleeping"
		let COUNTER=COUNTER+1
		if [ "$COUNTER" -gt "30" ]; then
			echo >&2 "Docker container did not come up in time."
			echo >&2 "Docker logs:"
			docker logs "${COMPOSE_PROJECT_NAME}-slurm-1"
			docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" cat /var/log/slurm/slurmctld.log
			stop_container
			echo >&2 "Exiting."
			exit 1
		fi
		sleep 1
	done
}


function compile_collector() {
	if [ "$RELEASE_MODE" = true ]; then
		RUSTFLAGS='-C link-args=-s' \
			cargo build \
			--target $TARGET_ARCH \
			-p auditor-slurm-collector \
			--release
	else
		RUSTFLAGS='-C link-args=-s' \
			cargo build \
			--target $TARGET_ARCH \
			-p auditor-slurm-collector
	fi
}



function start_slurm_collector() {
	if [[ -z "${SKIP_COMPILATION}" ]]
	then
		compile_collector
	fi
	docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" /auditor-slurm-collector /collector_config.yaml &
  sleep 60
}

function test_collector() {
	# Run on partition1
	# docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" sh -c "sbatch --job-name=test_part1 --partition=part1 --comment=\"$COMMENT\" /batch.sh" 
	for i in $(seq 1 20); do
    COMMENT="{ 'group_id': 'group-${i}' }"

    docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" \
      sh -c "sbatch \
        --job-name=test_part${i} \
        --partition=part1 \
        --comment=\"$COMMENT\" \
        /batch.sh"
    done
	
	# Run on partition2
	docker exec "${COMPOSE_PROJECT_NAME}-slurm-1" sh -c "sbatch --job-name=test_part2 --partition=part2 /batch.sh"
}

start_container

