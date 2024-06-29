#!/bin/sh
set -e

. scripts/shared.sh

update_project() {
  # perform any updates that are required based on the environment variables
  if [[ ! -z "${START_BLOCK}" ]]; then
      info_log "[Config Update] Start Block: ${START_BLOCK}"
      yq -i '.dataSources[].startBlock = env(START_BLOCK)' project.yaml
  fi

  if [[ ! -z "${CHAIN_ID}" ]]; then
      info_log "[Config Update] Chain ID: ${CHAIN_ID}"
      yq -i '.network.chainId = env(CHAIN_ID)' project.yaml
  fi

  if [[ ! -z "${ENDPOINT}" ]]; then
      info_log "[Config Update] Network Endpoint: ${ENDPOINT}"
      yq -i '.network.endpoint = strenv(ENDPOINT)' project.yaml
  fi
}

getParams() {
    local params="-f=/app"

    if [[ -n "$WORKERS" ]]; then
        params="--workers=$WORKERS "
    fi
    if [[ -n "$BATCH_SIZE" ]]; then
        params="${params}--batch-size=$BATCH_SIZE"
    fi
    if [[ -n "$DB_SCHEMA" ]]; then
        params="${params}--db-schema=$DB_SCHEMA"
    fi
    echo "$params"
}

# Add btree_gist extension to support historical mode - after the db reset from `graphile-migrate reset --erase`
export PGPASSWORD=$DB_PASS
psql -v ON_ERROR_STOP=1 \
        -h $DB_HOST \
        -U $DB_USER \
        -p $DB_PORT \
        -d $DB_DATABASE <<EOF
CREATE EXTENSION IF NOT EXISTS btree_gist;
EOF

params=$(getParams)

if [ "$WATCH" = "true" ]
then
  # call the first command if WATCH is true
  info_log "WATCH is true. Installing nodemon and Running with it..."
  if [ "$NODE_ENV" = "production" ]
  then
      # Add commands to do something here
      warning_log "Hot-reload is not recommended in production. Unset $WATCH to disable it."
  fi

  update_project
  exec="NODE_ENV=$NODE_ENV yarn run build && NODE_ENV=$NODE_ENV node /vendor/subql-cosmos/packages/node/bin/run ${params} $@"
  jq --arg value "$exec" '. + {"exec": $value}' nodemon.json > temp.json && mv temp.json nodemon.json
  cat nodemon.json
  yarn exec nodemon --config nodemon.json
else
  # call the other command if WATCH is not true
  info_log "WATCH is not true. Running the application without nodemon..."
  # move the dist folder to the mounted folder in run time
  update_project
  # run the main node
  env node /vendor/subql-cosmos/packages/node/bin/run "${params} $@"
fi

