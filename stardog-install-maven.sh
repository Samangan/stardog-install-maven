#!/usr/bin/env bash
#
# Install all Stardog jars into the local Maven repo
#
# Usage: ./stardog-install-maven.sh STARDOG_LIB
#
# Environment variables that are used:
#
# HOME
# M2_REPO         (defaults to ${HOME}/.m2}
# STARDOG_VERSION (defaults to 1.1.5)
# STARDOG_LIB     (defaults to various locations see code)
# TEMP            (defaults to /tmp)
# NEXUS_REPO      (can be specified in the id::layout::url format for instance
#                  thirdparty::default::http://nexushost/content/repositories/thirdparty
#                  don't forget to define <server><id>thirdparty</id>..</server>
#                  in your ~/.m2/settings.xml file)
#
M2_REPO="${M2_REPO:-${HOME}/.m2}"
script_dir="$(cd $(dirname $0) ; pwd)"
stardog_version="${STARDOG_VERSION:-1.1.5}"
stardog_project_dir=""

if [ "$1" == "" ] ; then
  if [ ! "${STARDOG_LIB}" == "" ] ; then
    stardog_libdir="${STARDOG_LIB}"
  elif [ -d "/opt/stardog-${stardog_version}/lib" ] ; then
    stardog_libdir="/opt/stardog-${stardog_version}/lib"
  elif [ -d "/opt/stardog/lib" ] ; then
    stardog_libdir="/opt/stardog/lib"
  elif [ -d "${HOME}/Work/stardog-${stardog_version}/lib" ] ; then
    stardog_libdir="${HOME}/Work/stardog-${stardog_version}/lib"
  elif [ -d "${HOME}/Work/stardog/lib" ] ; then
    stardog_libdir="${HOME}/Work/stardog/lib"
  else
    echo "ERROR: Specify stardog root directory"
    exit 1
  fi
else
  stardog_libdir="$1"
fi
if [ ! -d "${stardog_libdir}" ] ; then
  echo "ERROR: ${stardog_libdir} does not exist"
  exit 1
fi
skip_logging_jars=1
stardog_tmp_dir="${TEMP:-/tmp}"

if [ "" == "${stardog_libdir}" ] ; then
  if [ -d "${HOME}/Work/stardog-${stardog_version}/lib" ] ; then
    stardog_libdir="${HOME}/Work/stardog-${stardog_version}/lib"
  else
    stardog_libdir="${script_dir}/lib"
  fi
fi

cd "${stardog_libdir}"

function isVersion() {

  local version="$1"

  test "${version//./}" != "$1"
}

function installJar() {

  local depFile="$1"
  shift

  local jar="$*"
  local ifs=${IFS}
  local IFS=/

  set - $*

  IFS=${ifs}

  shift

  local groupId=$1
  local artifactId=$2
  local version=$3
  local file=$4
  local repoJarFile=$4
  local repoFile
  local tmp
  local stardogJar=0
  local deployToNexus=0

  #
  # artifactId will be empty for the jars in the root lib dir
  # Handle them a bit differently
  #
  if [ "${artifactId}" == "" ] ; then
  	if [ ! "${groupId%%-*}" == "stardog" ] ; then
  	  return 0
  	fi
  	stardogJar=1
    file="${groupId}"
    artifactId="$(basename ${file})"
    artifactId="${artifactId/.jar/}"
  	version="${artifactId##*-}"
    if isVersion "${version}" ; then
      artifactId="${artifactId/-${version}/}"
      if [ "${artifactId}" == "stardog" ] ; then
        stardog_version="${version}"
      fi
    else
      version="${stardog_version}"
    fi
  	groupId="com.clarkparsia"
    repoJarFile="${artifactId}-${version}.jar"
  	repoFile="${groupId//.//}/${artifactId}/${version}/${repoJarFile}"
  else
	#
	# Actually, the best artifact id comes from the jar file name itself
	#
	tmp="${file/-SNAPSHOT/}"
	tmp="${tmp/-GA}"
	tmp="${tmp/-incubating}"
    artifactId=${tmp%-*}
  	repoFile="${groupId//.//}/${artifactId}/${version}/${repoJarFile}"
  fi

  echo "Installing ${jar}"
  echo " - groupId    : $groupId"
  echo " - artifactId : $artifactId"
  echo " - version    : $version"
  echo " - file       : $file"
  echo " - repo file  : ${repoFile}"

  if ((skip_logging_jars)) ; then
    if [ "${artifactId}" == "slf4j-log4j12" -o "${artifactId}" == "slf4j-jdk14" -o "${artifactId}" == "log4j" ] ; then
      echo "Skipping this jar, take care of your own logging jars"
      return 0
    fi
  fi

  cat >> "${depFile}" << __maven__
		<dependency>
			<groupId>${groupId}</groupId>
			<artifactId>${artifactId}</artifactId>
			<version>${version}</version>
__maven__

  if [ "${artifactId}" == "junit" ] ; then
    cat >> "${depFile}" << __maven__
			<scope>test</scope>
__maven__
  fi

  if ((skip_logging_jars)) ; then
  	case ${artifactId} in
  	  jena-arq|jena-iri|jena-core)
        cat >> "${depFile}" << __maven__
			<exclusions>
				<exclusion>
					<artifactId>log4j</artifactId>
					<groupId>log4j</groupId>
				</exclusion>
				<exclusion>
					<artifactId>slf4j-api</artifactId>
					<groupId>log4j</groupId>
				</exclusion>
				<exclusion>
					<artifactId>slf4j-log4j12</artifactId>
					<groupId>org.slf4j</groupId>
				</exclusion>
			</exclusions>
__maven__
	    ;;
  	esac
  fi
  cat >> "${depFile}" << __maven__
		</dependency>
__maven__

  if [ ! "${NEXUS_REPO}" == "" ] ; then
    if ((stardogJar == 1)) ; then
      deployToNexus=1
    else
      case ${artifactId} in
        data-exporter|empire-*|cp-common-*|json-ld*|airline-*|nquads|jbcrypt|openrdf-*)
          deployToNexus=1
          ;;
      esac
    fi
    if ((deployToNexus == 1)) ; then
      set -x
      mvn deploy:deploy-file \
  	    -Dfile=${jar} \
        -Durl="http${NEXUS_REPO##*http}" \
  	    -DgroupId=${groupId} \
        -DartifactId=${artifactId} \
        -Dversion=${version} \
        -DupdateReleaseInfo=true \
        -DrepositoryId="${NEXUS_REPO%%:*}"
      set +x
    fi
  fi

  if [ -f "${M2_REPO}/repository/${repoFile}" ] ; then
  	echo "Already installed"
  	return 0
  fi

  mvn install:install-file \
  	-Dfile=${jar} \
  	-DgroupId=${groupId} \
    -DartifactId=${artifactId} \
    -Dversion=${version} \
    -Dpackaging=jar
}

function createStardogProjectDir() {
  
  stardog_project_dir="${stardog_tmp_dir}/stardog"

  test -d "${stardog_project_dir}" && rm -rf "${stardog_project_dir}"
  
  mkdir -p "${stardog_project_dir}"
  
  return $?
}

function createStardogProject() {

  local depFile="$1"
  local stardogPom="${stardog_project_dir}/pom.xml"


  cat > "${stardogPom}" << __pom__
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
	<modelVersion>4.0.0</modelVersion>
	<groupId>com.clarkparsia</groupId>
	<artifactId>stardog-libs</artifactId>
	<version>${stardog_version}</version>
	<packaging>pom</packaging>

	<description>
		This Stardog pom file is generated by the following Bash script:
		$0
	</description>

	<properties>
		<stardog.version>${stardog_version}</stardog.version>
	</properties>

	<dependencies>
__pom__

   cat "${depFile}" >> "${stardogPom}"

  cat >> "${stardogPom}" << __pom__
	</dependencies>
</project>
__pom__

   cat "${stardogPom}"
   
   return 0
}

function deploy() {

   cd "${stardog_project_dir}" || return $?
   
   if [ "${NEXUS_REPO}" == "" ] ; then
     echo "NEXUS_REPO not defined so doing a local deploy (aka mvn install)"
     mvn install
     return $?
   fi
   
   mvn -X deploy -DaltDeploymentRepository="${NEXUS_REPO}" -DupdateReleaseInfo=true
}

function main() {

  local depFile="${stardog_tmp_dir}/stardog-dependencies.xml"

  rm -f "${depFile}" || return $?
  touch "${depFile}" || return $?

  for jar in $(find . -name '*.jar' -type f -print) ; do
    installJar "${depFile}" ${jar}
  done
  #cat "${stardogPom}"

  createStardogProjectDir || return $?
  createStardogProject ${depFile} || return $?
  deploy || return $?
  
  return 0
}

main $@
exit $?
