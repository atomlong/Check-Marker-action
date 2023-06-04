#!/usr/bin/bash

# get last commit hash of one package
_last_package_hash()
{
local package="${repo}/${GITHUB_REPOSITORY#*/}"
rclone cat "${marker_path}" 2>/dev/null | sed -rn "s|^\[([[:xdigit:]]+)\]${package}\s*$|\1|p"
return 0
}

# update current commit hash of this package
# If the build marker file does not exist, then do nothing.
_update_package_hash()
{
local package="${repo}/${GITHUB_REPOSITORY#*/}"
local marker=$(basename "${marker_path}")
local marker_dir=$(dirname "${marker_path}")

_lock_file "${marker_path}"
rclone lsf "${marker_path}" &>/dev/null && while ! rclone copy "${marker_path}" . &>/dev/null; do :; done || return 0
sed -i -r "s|^\s*(\[)[[:xdigit:]]+(\]${package}\s*)$|\1${now_hash}\2|g" "${marker}"
rclone move "${marker}" "${marker_dir}"
_release_file "${marker_path}"
return 0
}

# Lock the remote file to prevent it from being modified by another instance.
_lock_file()
{
local lockfile=${1}.lck
local instid="${GITHUB_REPOSITORY}:${GITHUB_RUN_NUMBER}"
local t_s last_s head_s
last_s=$(rclone lsjson ${lockfile} 2>/dev/null | jq '.[0]|.ModTime' | tr -d '"')
last_s=$([ -n "${last_s}" ] && date -d "${last_s}" "+%s" || echo 0)
t_s=$(date '+%s')
(( ${t_s}-${last_s} < 6*3600 )) && rclone copyto ${lockfile} lockfile.lck
echo "${instid}" >> lockfile.lck
sed -i '/^\s*$/d' lockfile.lck
rclone moveto lockfile.lck ${lockfile}

t_s=0
last_s=""
while true; do
head_s="$(rclone cat ${lockfile} 2>/dev/null | head -n 1)"
[ -z "${head_s}" ] && continue
[ "${head_s}" == "${instid}" ] && break
[ "${head_s}" == "${last_s}" ] && {
(( ($(date '+%s') - ${t_s}) > (30*60) )) && {
rclone cat ${lockfile} | awk "BEGIN {P=0} {if (\$1 != \"${head_s}\") P=1; if (P == 1 && NF) print}" > lockfile.lck
sed -i '/^\s*$/d' lockfile.lck
[ -s lockfile.lck ] && rclone moveto lockfile.lck ${lockfile} || {
rclone deletefile ${lockfile}
break
}
}
} || {
t_s=$(date '+%s')
last_s="${head_s}"
}
done
return 0
}

# Release the remote file to allow it to be modified by another instance.
_release_file()
{
local lockfile=${1}.lck
local instid=$$
[ "${CI}" == "true" ] && instid="${CI_REPO}:${CI_BUILD_NUMBER}"
rclone lsf ${lockfile} &>/dev/null || return 0
rclone cat ${lockfile} | awk "BEGIN {P=0} {if (\$1 != \"${instid}\") P=1; if (P == 1 && NF) print}" > lockfile.lck
[ -s lockfile.lck ] && rclone moveto lockfile.lck ${lockfile} || rclone deletefile ${lockfile}
rm -vf lockfile.lck
return 0
}

### functions above ###
### --------------- ###
### script below    ###

arch="${INPUT_ARCH:-x86_64}"
repo="${INPUT_REPO:-cygn}"
target_os="${INPUT_TARGET_OS:-Linux}"
now_hash="${GITHUB_SHA}"
marker_path="${INPUT_MARKER_PATH}"
rclone_config="${INPUT_RCLONE_CONFIG}"
update="${INPUT_UPDATE:-false}"

# fail if marker_path is not set in workflow
if [ -z "${marker_path}" ]; then
	error_message='Workflow missing input value for "marker_path"'
    echo "${error_message}" 1>&2
	echo "error_message=\"${error_message}\"" >>${GITHUB_OUTPUT}
	exit 1
fi

eval marker_path="${marker_path}"

if [ -z "${rclone_config}" ]; then
	error_message='Workflow missing input value for "rclone_config"'
	echo "${error_message}" 1>&2
	echo "error_message=\"${error_message}\"" >>${GITHUB_OUTPUT}
	exit 1
fi

if ! which rclone &>/dev/null; then
	which pacman &>/dev/null && sudo pacman -S --needed --noconfirm rclone
	which apt &>/dev/null && sudo apt -y install rclone
	if ! which rclone &>/dev/null; then
		error_message="No rclone installed on this system."
		echo "${error_message}" 1>&2
		echo "error_message=\"${error_message}\"" >>${GITHUB_OUTPUT}
		exit 1
	fi
fi

RCLONE_CONFIG_PATH=$(rclone config file | tail -n1)
mkdir -pv $(dirname "${RCLONE_CONFIG_PATH}")
[ $(awk 'END{print NR}' <<< "${rclone_config}") == 1 ] &&
base64 --decode <<< "${rclone_config}" > "${RCLONE_CONFIG_PATH}" ||
printf "${rclone_config}" > "${RCLONE_CONFIG_PATH}"

last_hash=$(_last_package_hash)

if [ "${last_hash}" == "${now_hash}" ]; then
	marked="true"
else
	if [ -z "${last_hash}" ] || [ "${update}" == "false" ]; then
		marked="false"
	else
		_update_package_hash && { marked="true"; last_hash="${now_hash}"; } || marked="false"
	fi
fi

echo "marked=${marked}" >>${GITHUB_OUTPUT}
echo "now_hash=${now_hash}" >>${GITHUB_OUTPUT}
echo "last_hash=${last_hash}" >>${GITHUB_OUTPUT}
