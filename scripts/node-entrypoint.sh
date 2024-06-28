#!/bin/sh
set -e

update_project() {
  # perform any updates that are required based on the environment variables
  if [[ ! -z "${START_BLOCK}" ]]; then
      echo "[Config Update] Start Block: ${START_BLOCK}"
      yq -i '.dataSources[].startBlock = env(START_BLOCK)' project.yaml
  fi

  if [[ ! -z "${CHAIN_ID}" ]]; then
      echo "[Config Update] Chain ID: ${CHAIN_ID}"
      yq -i '.network.chainId = env(CHAIN_ID)' project.yaml
  fi

  if [[ ! -z "${NETWORK_ENDPOINT}" ]]; then
      echo "[Config Update] Network Endpoint: ${NETWORK_ENDPOINT}"
      yq -i '.network.endpoint = strenv(NETWORK_ENDPOINT)' project.yaml
  fi
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

if [ "$WATCH" = "true" ]
then
  # call the first command if WATCH is true
  echo "WATCH is true. Running the application with nodemon..."
  if [ "$NODE_ENV" = "production" ]
  then
      # Add commands to do something here
      echo "WARN: Hot-reload is not recommended in production. Unset $WATCH to disable it."
  fi
  rm -rf /dist
  update_project
  env yarn exec nodemon --config nodemon.json --exec "NODE_ENV=$NODE_ENV yarn run build && NODE_ENV=$NODE_ENV node /vendor/subql-cosmos/packages/node/bin/run $@"
else
  # call the other command if WATCH is not true
  echo "WATCH is not true. Running the application without nodemon..."
  # move the dist folder to the mounted folder in run time
  cp -R /dist/. /app/dist
  cp -R /types/. /app/src/types
  cp /project.yaml /app
  update_project
  # run the main node
  NODE_ENV=$NODE_ENV env node /vendor/subql-cosmos/packages/node/bin/run "$@"
fi

