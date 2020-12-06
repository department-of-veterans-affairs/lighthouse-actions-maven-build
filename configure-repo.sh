#!/usr/bin/env bash
set -euo pipefail

LMB_DIR=$(dirname $(readlink -f $0))
export LMB_REF=$(git log -1 --format='%H')

usage() {
cat >/dev/stderr <<EOF
$0 [options] [command]

Perform a Maven build suitable for automation in the Lighthouse environment.

Options
--nexus-username <user>
--nexus-password <password>
  The user name and password for the Health APIs Nexus server
  Environment variables: NEXUS_USERNAME NEXUS_PASSWORD

--secret-name <name>
--secret-value <value>
  Update this specific secret with the given value
  Environmet variables: SECRET_NAME SECRET_VALUE

Commands
  Command may be specified with environment variable COMMAND

update-codeql
  Update github/workflows/codeql.yml

update-secrets --nexus-username <> --nexus-password <>
  Update the secrets for the GitHub repository (requires gh, jq, and nodejs)
  - HEALTH_APIS_RELEASES_NEXUS_USERNAME
  - HEALTH_APIS_RELEASES_NEXUS_PASSWORD

update-secret --secret-name <> --secret-value <>
  Update the secret for the GitHub repository

${1:-}
EOF
exit 1
}

main() {
  local args
  local longOpts="debug,nexus-username:,nexus-password:,secret-name:,secret-value:"
  local shortOpts=""
  if ! args=$(getopt -l "$longOpts" -o "$shortOpts" -- "$@"); then usage; fi
  eval set -- "$args"
  while true
  do
    case "$1" in
      --debug) DEBUG=true;;
      --nexus-username) NEXUS_USERNAME="$2";;
      --nexus-password) NEXUS_PASSWORD="$2";;
      --secret-name) SECRET_NAME="$2";;
      --secret-value) SECRET_VALUE="$2";;
      --) shift; break;;
    esac
    shift
  done
  if [ "${DEBUG:-}" == "true" ]; then set -x; fi
  if [ $# == 1 ]; then COMMAND="$1"; shift; fi
  if [ -z "${COMMAND:-}" ]; then usage "Command must be specified"; fi
  MVN_ARGS="$@"
  case $COMMAND in
    update-codeql) updateCodeQl;;
    update-secrets) updateSecrets;;
    update-secret) updateSecret;;
    *) usage "unknown command: $COMMAND";;
  esac
}

requireOpt() {
  local name="$1"
  local var="$2"
  local value="$(eval echo \${${var}:-})"
  if [ -z "${value:-}" ]
  then
    usage "$name not specified, use option --$name or environment variable $var"
  fi
}

requireTool() {
  local tool="$1"
  local website="$2"
  if ! which $tool > /dev/null 2>&1
  then
    echo "$tool is required: see $website"
    exit 1
  fi
}


DELETE_ME=()
onExit() {
  if [ "${#DELETE_ME[@]}" -gt 0 ]; then rm -rf ${DELETE_ME[@]}; fi
}
trap onExit EXIT

deleteMe() {
  DELETE_ME+=( $(readlink -f $1) )
}

writeWorkflow() {
  local templateName="$1"
  local template=$LMB_DIR/templates/$templateName
  local workflow=.github/workflows/$templateName
  cat $template | envsubst > $workflow
  echo "Updated $workflow"
}

updateCodeQl() {
  export MASTER_BRANCH=$(git remote show origin | grep 'HEAD branch:' | sed 's/.*: //')
  writeWorkflow codeql.yml
}


nodeEncryptionScript() {
cat<<EOF
const sodium = require('tweetsodium');
const key = process.argv[2];
const value = process.argv[3];
const messageBytes = Buffer.from(value);
const keyBytes = Buffer.from(key, 'base64');
const encryptedBytes = sodium.seal(messageBytes, keyBytes);
const encrypted = Buffer.from(encryptedBytes).toString('base64');
console.log(encrypted);
EOF
}

typeset -A ENCRYPTED
encryptSecret() {
  local var="$1"
  local value="$(eval echo \${${var}:-})"
  local encryptedValue
  if [ -z "${TMPDIR:-}" ]; then TMPDIR=$(mktemp -d) && deleteMe "$TMPDIR"; fi
  local encrypter=$TMPDIR/configure-repo-encrypter
  mkdir -p $encrypter
  cd $encrypter
  local encryptJs=$(mktemp encrypt.XXXX.js) && deleteMe "$encryptJs"
  nodeEncryptionScript > $encryptJs
  if [ -z "${TWEETSODIUM_INSTALLED:-}" ]
  then
    npm install --silent --no-progress --save tweetsodium
    TWEETSODIUM_INSTALLED=true
  fi
  encryptedValue=$(node $encryptJs "$KEY" "$value")
  cd - > /dev/null 2>&1
  ENCRYPTED[$var]="$encryptedValue"
}



putSecret() {
  local secretName="$1"
  local secretVariable="$2"
  if [ -z "${KEY:-}" -o -z "${KEY_ID:-}" ]
  then
    requireTool gh "https://github.com/cli/cli"
    requireTool jq "https://stedolan.github.io/jq"
    requireTool node "https://nodejs.org"
    local publicKey=$(mktemp key.XXXX.json) && deleteMe "$publicKey"
    gh api /repos/:owner/:repo/actions/secrets/public-key > $publicKey
    KEY_ID=$(jq -r .key_id $publicKey)
    KEY=$(jq -r .key $publicKey)
    echo "Using key $KEY_ID"
    encryptSecret $secretVariable
    echo "Updating $secretName with $secretVariable"
    gh api -X PUT /repos/:owner/:repo/actions/secrets/$secretName \
      -f encrypted_value="${ENCRYPTED[${secretVariable}]}" \
      -f key_id="$KEY_ID"
  fi
}

updateSecrets() {
  requireOpt nexus-username NEXUS_USERNAME
  requireOpt nexus-password NEXUS_PASSWORD
  for secretVariable in NEXUS_USERNAME NEXUS_PASSWORD
  do
    putSecret "HEALTH_APIS_RELEASES_$secretVariable" "$secretVariable"
  done
}

updateSecret() {
  requireOpt secret-name SECRET_NAME
  requireOpt secret-value SECRET_VALUE
  putSecret $SECRET_NAME SECRET_VALUE
}

main "$@"
exit 0
