#!/bin/bash

# set -x

info() {
  echo "Info: $1"
}

warn() {
  >&2 echo "Warning: $1"
}

error() {
  >&2 echo "Error: $1"
  exit 1
}

require_var() {
  [ ${!1+x} ] || error "$1 is not defined"
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

require_var PLATFORM
require_var FIRMWARE
require_var CPARSER

LIBRARIES_DIR="${DIR}/lib"
BUILD_DIR="${DIR}/build"
LIBNAME="$1"

rm -rf "${DIR}/build"
mkdir -p "${DIR}/build"

for lib in `find "${LIBRARIES_DIR}" -mindepth 1 -maxdepth 1 -not -empty -type d`; do
  libname=$(basename "${lib}")
  if [ ! -z "${LIBNAME}" ] && [ "${libname}" != "${LIBNAME}" ]; then
    continue
  fi
  info "========================================================="
  info "Library ${libname}"
  info "========================================================="

  if [ ! -d "${lib}/src" ]; then
    warn "No src directory in '${libname}' library directory"
    mkdir -p "${lib}/src"
    for src in `find "${lib}" -mindepth 1 -type d \( -path "${lib}/examples" -o -path "${lib}/src" \) -prune -o -type f \( -name '*.cpp' -o -name '*.cc' -o -name '*.c' -o -name '*.h' -o -name '*.hh' -o -name '*.hpp' \) -print`; do
      srce="${src#${lib}}"
      d=$(dirname "${srce}")
      mkdir -p "${lib}/src/${d}"
      cp "${src}" "${lib}/src/${srce}"
    done
  fi

  if [ ! -d "${lib}/examples" ]; then
    warn "No examples directory in '${libname}' library directory"
    continue
  fi

  grep -R -e "SoftwareSerial" -e "NewSoftSerial" "${lib}" >/dev/null 2>&1
  softserial=$?

  grep -R -e "Adafruit_Sensor.h" "${lib}" >/dev/null 2>&1
  adafruit_sensor=$?

  grep -R -e "Adafruit_GFX.h" "${lib}" >/dev/null 2>&1
  adafruit_gfx=$?

  for ex in `find "${lib}/examples" -mindepth 1 -maxdepth 1 -not -empty -type d`; do
    exname=$(basename "${ex}")
    builddir="${BUILD_DIR}/${libname}/examples/${exname}"
    rm -rf "${builddir}"
    mkdir -p "${builddir}/src"
    for src in `find "${ex}" -mindepth 1 -maxdepth 1 -type f \( -name '*.ino' -o -name '*.pde' -o -name '*.cpp' -o -name '*.cc' -o -name '*.c' -o -name '*.h' -o -name '*.hh' -o -name '*.hpp' \) -print`; do
      cp "${src}" "${builddir}/src"
    done

    for pde in `find "${builddir}/src" -mindepth 1 -maxdepth 1 -type f -name '*.pde' -print`; do
      mv -- "$pde" "${pde%.pde}.ino"
    done

    # for ino in `find "${builddir}/src" -mindepth 1 -maxdepth 1 -type f -name '*.ino' -print`; do
      # mv -- "$ino" "${ino%.ino}.cpp"
      # preprocess
    # done

    nodejs "${CPARSER}/main.js" "${builddir}" >/dev/null 2>&1

    mkdir -p "${builddir}/lib"
    ln -s "${lib}" "${builddir}/lib/${libname}"

    if [ -d "${LIBRARIES_DIR}/SoftwareSerial" ] && [ -d "${LIBRARIES_DIR}/SparkIntervalTimer" ] && [ ${softserial} -eq 0 ]; then
      #info "(${exname}) Adding SoftwareSerial/NewSoftSerial"
      ln -s "${LIBRARIES_DIR}/SoftwareSerial" "${builddir}/lib/SoftwareSerial"
      ln -s "${LIBRARIES_DIR}/SparkIntervalTimer" "${builddir}/lib/SparkIntervalTimer"
    fi

    if [ ${adafruit_sensor} -eq 0 ] && [ -d "${LIBRARIES_DIR}/Adafruit_Sensor" ]; then
      ln -s "${LIBRARIES_DIR}/Adafruit_Sensor" "${builddir}/lib/Adafruit_Sensor"
    fi

    if [ ${adafruit_gfx} -eq 0 ] && [ -d "${LIBRARIES_DIR}/Adafruit-GFX-Library" ]; then
      ln -s "${LIBRARIES_DIR}/Adafruit-GFX-Library" "${builddir}/lib/Adafruit-GFX-Library"
    fi

    cp "${DIR}/build.mk" "${builddir}/src/build.mk"
    cp "${DIR}/project.properties" "${builddir}/project.properties"

    cd "${FIRMWARE}/main"
    make PLATFORM="${PLATFORM}" APPDIR="${builddir}" clean all >"${builddir}/build.log" 2>&1
    res=$?
    resstr=$([ $res == 0 ] && echo "OK" || echo "FAIL (see ${builddir}/build.log)")
    info "Example '${exname}': ${resstr}"
  done
done
