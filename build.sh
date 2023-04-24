#!/usr/bin/env bash
set -euo pipefail

usage() {
cat >/dev/stderr <<EOF
$0 [options] <command>

Perform a Maven build suitable for automation in the Lighthouse environment.
Automatically configures Maven to use GitHub artifacts

Options
--github-username <user>
  The user name for GitHub
--github-token <token>
  The token for the GitHub user
--initialize-build <file>
  The name of script to run prior to building with Maven.
  By default, this is initialize-build.sh
  If this file exists, it will be executed.

Commands
non-release
  Perform a basic mvn install.
release
  Perform a mvn deploy using the release profile.

${1:-}
EOF
exit 1
}

INITIALIZE_BUILD="initialize-build.sh"

init() {
  if [ "${DEBUG:-}" == "true" ]; then set -x; fi
  requireOpt github-username GITHUB_USERNAME
  requireOpt github-token GITHUB_TOKEN
  git config user.name libertybot
  git config user.email "<none>"
  export GH_TOKEN="${GITHUB_TOKEN}"
}

main() {
  local args
  local longOpts="debug,github-username:,github-token:,initialize-build:"
  local shortOpts=""
  if ! args=$(getopt -l "$longOpts" -o "$shortOpts" -- "$@"); then usage; fi
  eval set -- "$args"
  while true
  do
    case "$1" in
      --debug) DEBUG=true;;
      --github-username) GITHUB_USERNAME="$2";;
      --github-token) GITHUB_TOKEN="$2";;
      --initialize-build) INITIALIZE_BUILD="$2";;
      --) shift; break;;
    esac
    shift
  done
  init
  if [ $# == 1 ]; then COMMAND="$1"; shift; fi
  if [ -z "${COMMAND:-}" ]; then usage "Command must be specified"; fi
  MVN_ARGS="$@"
  case $COMMAND in
    non-release) nonReleaseBuild;;
    release) releaseBuild;;
    *) usage "unknown command: $COMMAND";;
  esac
}

commitNextSnapshot() {
  mvn $MVN_ARGS versions:set -DprocessAllModules=true -DgenerateBackupPoms=false -DnextSnapshot=true
  local snapshotVersion
  snapshotVersion=$(mvn $MVN_ARGS -N -q org.codehaus.mojo:exec-maven-plugin:exec -Dexec.executable='echo' -Dexec.args='${project.version}')
  git diff
  git add $(git status -s | grep "^ M" | cut -c4-)
  local message
  message="Next snapshot ${snapshotVersion}"
  git commit -m "${message}"
}

commitReleaseVersion() {
  local releaseVersion="${1:-}"
  if [ -z "${releaseVersion:-}" ]
  then
    echo "Release version could not be determined."
    exit 1
  fi
  git diff
  git add $(git status -s | grep "^ M" | cut -c4-)
  local message
  message="Release ${releaseVersion} - GitHub Workflow: ${GITHUB_WORKFLOW} ${GITHUB_RUN_ID}"
  git commit -m "${message}"
  git tag --force -m "${message}" ${releaseVersion}
}

configureSettings() {
  SETTINGS=$(mktemp settings.xml.XXXX)
  trap "rm $SETTINGS" EXIT
  defaultSettings>$SETTINGS
}

createGitHubRelease() {
  local releaseVersion="${1:-}"
  echo "Creating Release ${releaseVersion} in GitHub"
  # ToDo determine release notes
  gh release create ${releaseVersion} \
    --verify-tag \
    --title "Release ${releaseVersion}"
}

defaultSettings() {
cat<<EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <servers>
   <server>
     <id>github</id>
      <username>\${github.username}</username>
      <password>\${github.token}</password>
   </server>
 </servers>
  <profiles>
    <profile>
      <id>github</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <repositories>
        <repository>
          <id>github</id>
          <url>https://maven.pkg.github.com/department-of-veterans-affairs/all</url>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>github</id>
          <url>https://maven.pkg.github.com/department-of-veterans-affairs/all</url>
          <snapshots>
            <enabled>false</enabled>
          </snapshots>
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
          <url>https://repo.maven.apache.org/maven2</url>
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
          <url>https://repo.maven.apache.org/maven2</url>
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

isJavaVersionSupported() {
  if [ -z "${JAVA_VERSION:-}" ]
  then
    echo "Cannot determine containers java version, assuming it's supported."
    return 0
  else
    echo "Found installed java version: ${JAVA_VERSION}"
  fi

  local desiredVersion=$(mvn -N -q org.codehaus.mojo:exec-maven-plugin:exec \
    ${MVN_ARGS} \
    -Dexec.executable='echo' \
    -Dexec.args='${maven.compiler.target}')
  if [ -z "${desiredVersion:-}" ]
  then
    echo "Cannot determine compiler target version, assuming it's supported."
    return 0
  fi

  local javaMajorVersion=
  javaMajorVersion=$(echo ${JAVA_VERSION} | cut -d '.' -f 1)
  if [ "${javaMajorVersion}" != "${desiredVersion}" ]
  then
    echo "Container java version (${javaMajorVersion}) does not match desired java version (${desiredVersion}). Aborting build..."
    return 1
  fi

  return 0
}

nextRelease() {
  mvn $MVN_ARGS versions:set -DprocessAllModules=true -DgenerateBackupPoms=false -DremoveSnapshot=true 1>&2
  local releaseVersion
  releaseVersion=$(mvn $MVN_ARGS -N -q org.codehaus.mojo:exec-maven-plugin:exec -Dexec.executable='echo' -Dexec.args='${project.version}')
  echo "RELEASE_VERSION=${releaseVersion}" >> $GITHUB_ENV
  echo ${releaseVersion}
}

nonReleaseBuild() {
  echo "Build Non-Release"
  setupBuild
  MVN_ARGS+=" --update-snapshots"
  MVN_ARGS+=" -Ddocker.skip=true"
  set -x
  mvn $MVN_ARGS install
  set +x
  removeSnapshotsFromCache
}

releaseBuild() {
  echo "Build Release"
  setupBuild
  local releaseVersion
  releaseVersion=$(nextRelease)
  set -x
  mvn $MVN_ARGS -U -Prelease clean deploy
  set +x
  commitReleaseVersion "${releaseVersion}"
  commitNextSnapshot
  git push --tags --force
  git push
  createGitHubRelease "${releaseVersion}"
}

removeSnapshotsFromCache() {
  for f in $(find ~/.m2/repository/ -type d -name "*-SNAPSHOT")
  do
    rm -rf $f || true
  done
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

runInitializeBuild() {
  if [ ! -f "$INITIALIZE_BUILD" ]; then return; fi
  echo "Found $INITIALIZE_BUILD"
  bash -c $(readlink -f $INITIALIZE_BUILD)
}

setupBuild() {
  configureSettings
  MVN_ARGS+=" --batch-mode"
  MVN_ARGS+=" --settings ${SETTINGS}"
  MVN_ARGS+=" -Dgithub.username=${GITHUB_USERNAME}"
  MVN_ARGS+=" -Dgithub.token=${GITHUB_TOKEN}"
  MVN_ARGS+=" -Dgit.enforceBranchNames=false"
  if ! isJavaVersionSupported; then echo "Skipping build..."; return; fi
  runInitializeBuild
}

main "$@"
exit 0
