#!/usr/bin/env bash
set -euo pipefail

usage() {
cat >/dev/stderr <<EOF
$0 [options] <command>

Perform a Maven build suitable for automation in the Lighthouse environment.
Automatically configures Maven to use the Health APIs Nexus server

Options
--nexus-username <user>
  The user name for the Health APIs Nexus server
--nexus-password <password>
  The password for the Health APIs Nexus server

Commands
non-release
  Perform a basic mvn install.

${1:-}
EOF
exit 1
}

main() {
  local args
  local longOpts="debug,nexus-username:,nexus-password:"
  local shortOpts=""
  if ! args=$(getopt -l "$longOpts" -o "$shortOpts" -- "$@"); then usage; fi
  eval set -- "$args"
  while true
  do
    case "$1" in
      --debug) DEBUG=true;;
      --nexus-username) NEXUS_USERNAME="$2";;
      --nexus-password) NEXUS_PASSWORD="$2";;
      --) shift; break;;
    esac
    shift
  done
  if [ "${DEBUG:-}" == "true" ]; then set -x; fi
  if [ $# == 1 ]; then COMMAND="$1"; shift; fi
  if [ -z "${COMMAND:-}" ]; then usage "Command must be specified"; fi
  MVN_ARGS="$@"
  case $COMMAND in
    non-release) nonReleaseBuild;;
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


defaultSettings() {
cat<<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
   <server>
     <id>health-apis-releases</id>
      <username>\${health-apis-releases.nexus.user}</username>
      <password>\${health-apis-releases.nexus.password}</password>
   </server>
 </servers>
  <profiles>
    <profile>
      <id>gov.va.api.health</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <repositories>
        <repository>
          <id>health-apis-releases</id>
          <url>https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases/</url>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>health-apis-releases</id>
          <url>https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases/</url>
        </pluginRepository>
      </pluginRepositories>
    </profile>
    <!-- Add last to access first -->
    <profile>
      <id>central-evil-twin</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <repositories>
        <repository>
          <id>central-evil-twin</id>
          <url>http://repo.maven.apache.org/maven2</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>central-evil-twin</id>
          <url>http://repo.maven.apache.org/maven2</url>
          <releases>
            <enabled>true</enabled>
          </releases>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
EOF
}

configureSettings() {
  SETTINGS=$(mktemp settings.xml.XXXX)
  trap "rm $SETTINGS" EXIT
  defaultSettings>$SETTINGS
}

removeSnapshotsFromCache() {
  for f in $(find ~/.m2/repository/ -type d -name "*-SNAPSHOT")
  do
    rm -rf $f || true
  done
}

nonReleaseBuild() {
  requireOpt nexus-username NEXUS_USERNAME
  requireOpt nexus-password NEXUS_PASSWORD
  configureSettings
  MVN_ARGS+=" --settings $SETTINGS"
  MVN_ARGS+=" --batch-mode"
  MVN_ARGS+=" --update-snapshots"
  MVN_ARGS+=" -Ddocker.skip=true"
  MVN_ARGS+=" -Dgit.enforceBranchNames=false"
  MVN_ARGS+=" -Dhealth-apis-releases.nexus.user=$NEXUS_USERNAME"
  MVN_ARGS+=" -Dhealth-apis-releases.nexus.password=$NEXUS_PASSWORD"
  mvn $MVN_ARGS install
  removeSnapshotsFromCache
}

main "$@"
exit 0
