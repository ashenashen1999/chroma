#!/usr/bin/env bash

set -e

function cleanup {
  rm server.htpasswd .chroma_env
}

function setup_auth {
  local auth_type="$1"
  case "$auth_type" in
  basic)
    docker run --rm --entrypoint htpasswd httpd:2 -Bbn admin admin >server.htpasswd
    cat <<EOF >.chroma_env
CHROMA_SERVER_AUTHN_CREDENTIALS_FILE="/chroma/server.htpasswd"
CHROMA_SERVER_AUTHN_PROVIDER="chromadb.auth.basic_authn.BasicAuthenticationServerProvider"
EOF
    ;;
  token)
    cat <<EOF >.chroma_env
CHROMA_AUTH_TOKEN_TRANSPORT_HEADER="Authorization"
CHROMA_SERVER_AUTHN_CREDENTIALS="test-token"
CHROMA_SERVER_AUTHN_PROVIDER="chromadb.auth.token_authn.TokenAuthenticationServerProvider"
EOF
    ;;
  xtoken)
    cat <<EOF >.chroma_env
CHROMA_AUTH_TOKEN_TRANSPORT_HEADER="X-Chroma-Token"
CHROMA_SERVER_AUTHN_CREDENTIALS="test-token"
CHROMA_SERVER_AUTHN_PROVIDER="chromadb.auth.token_authn.TokenAuthenticationServerProvider"
EOF
    ;;
  *)
    echo "Unknown auth type: $auth_type"
    exit 1
    ;;
  esac
}

trap cleanup EXIT

docker compose -f docker-compose.test.yml up --build -d

export CHROMA_INTEGRATION_TEST_ONLY=1
export CHROMA_API_IMPL=chromadb.api.fastapi.FastAPI
export CHROMA_SERVER_HOST=localhost
export CHROMA_PORT=8000
export CHROMA_SERVER_HTTP_PORT=8000
export CHROMA_SERVER_NOFILE=65535

cd clients/js
pnpm install

pnpm test:run
docker compose down

cd ../..

for auth_type in basic token xtoken; do
  echo "Testing $auth_type auth"
  setup_auth "$auth_type"
  cd clients/js
  docker compose --env-file ../../.chroma_env -f ../../docker-compose.test-auth.yml up --build -d
  pnpm test:run-auth-"$auth_type"
  cd ../..
  docker compose down
done
