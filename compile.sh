#!/usr/bin/env bash
# Bash3 Boilerplate. Copyright (c) 2014, kvz.io

set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; exit 1' ERR

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")"
__base="$(basename ${__file} .sh)"
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- change this as it depends on your app

arg1="${1:-}"
rpmtopdir=

# trap 'echo Signal caught, cleaning up >&2; cd /tmp; /bin/rm -rfv "$TMP"; exit 15' 1 2 3 15
# allow command fail:
# fail_command || true
#

CHECKEXISTS() {
  if [[ ! -f $__dir/downloads/$1 ]];then
    echo "$1 not found, run 'pullsrc.sh', or manually put it in the downloads dir."
    exit 1
  fi
}


GUESS_DIST() {
    # 如果 rpm 命令不存在则无法工作
    if ! type -p rpm > /dev/null;then
        echo 'unknown' && return 0
    fi

    local dist=$(rpm --eval '%{?dist}' | tr -d '.')

    # 处理 Kylin 系统
    [[ $dist == "kylin" ]] && dist="kylin"

    # 其他系统的回退到 el7
    [[ $dist == "el9" ]] && dist="el7"
    [[ $dist == "el8" ]] && dist="el7"
    [[ $dist == "an7" ]] && dist="el7"
    [[ $dist == "an8" ]] && dist="el7"

    [[ -n $dist ]] && echo $dist && return 0

    local glibcver=$(ldd --version | head -n1 | grep -Eo '[0-9]+' | tr -d '\n')

    # centos 5 使用 glibc 2.5
    [[ $glibcver -eq 25 ]] && echo 'el5' && return 0

    # centos 6 使用 glibc 2.12
    [[ $glibcver -eq 212 ]] && echo 'el6' && return 0

    # centos 7 使用 glibc 2.17
    [[ $glibcver -eq 217 ]] && echo 'el7' && return 0

    # centos 8 使用 glibc 2.28
    [[ $glibcver -eq 228 ]] && echo 'el8' && return 0

    # 某些 centos 类发行版使用更高版本的 glibc，回退到 el7
    [[ $glibcver -gt 217 ]] && echo 'el7' && return 0
}

BUILD_RPM() {

    source version.env
    SOURCES=( $OPENSSHSRC \
              $OPENSSLSRC \
              $ASKPASSSRC \
    )
    # 仅在 EL5 上需要 perl 源码。
    [[ $rpmtopdir == "el5" ]] && SOURCES+=($PERLSRC)

    pushd $rpmtopdir
    for fn in ${SOURCES[@]}; do
        CHECKEXISTS $fn && \
        install -v -m666 $__dir/downloads/$fn ./SOURCES/
    done

    rpmbuild -ba SPECS/openssh.spec --target $(uname -m) --define "_topdir $PWD" \
        --define "opensslver ${OPENSSLVER}" \
        --define "opensshver ${OPENSSHVER}" \
        --define "opensshpkgrel ${PKGREL}" \
        --define "perlver ${PERLVER}" \
        --define '_opensslincdir /usr/include/openssl' \
        --define '_openssllibdir /usr/lib64' \
        --define 'no_gtk2 1' \
        --define 'skip_gnome_askpass 1' \
        --define 'skip_x11_askpass 1' \
        ;
    popd
}

LIST_RPMDIR(){
    local DISTVER=$(GUESS_DIST)
    local RPMDIR=$__dir/$(GUESS_DIST)/RPMS/$(uname -m)
    [[ -d $RPMDIR ]] && echo $RPMDIR
}

LIST_RPMS() {
    local RPMDIR=$(LIST_RPMDIR)
    [[ -d $RPMDIR ]] && find $RPMDIR -type f -name '*.rpm' ! -name '*debug*'
}

# 子命令处理
case $arg1 in
    GETEL)
        GUESS_DIST && exit 0
        ;;
    GETRPM)
        LIST_RPMS && exit 0
        ;;
    RPMDIR)
        LIST_RPMDIR && exit 0
        ;;
esac

# 手动指定 dist
[[ -n $arg1 && -d $__dir/$arg1 ]] && rpmtopdir=$arg1 && BUILD_RPM && exit 0

# 自动检测发行版
if [[ -z $arg1 ]]; then
    DISTVER=$(GUESS_DIST)
    case $DISTVER in
        amzn1)
            rpmtopdir=amzn1
            ;;
        amzn2)
            rpmtopdir=amzn2
            ;;
        amzn2023)
            rpmtopdir=amzn2023
            ;;
        el7)
            rpmtopdir=el7
            ;;
        el6)
            rpmtopdir=el6
            ;;
        el5)
            rpmtopdir=el5
            # 在 centos5 上，建议使用 gcc44
            rpm -q gcc44 && export CC=gcc44
            ;;
        kylin)
            rpmtopdir=kylin
            ;;
        *)
            echo "未定义的发行版，请手动指定: el5 el6 el7 amzn1 amzn2 amzn2023 kylin"
            echo -e "\n当前操作系统信息:"
            [[ -f /etc/os-release ]] && cat /etc/os-release
            [[ -f /etc/redhat-release ]] && cat /etc/redhat-release 
            [[ -f /etc/system-release ]] && cat /etc/system-release
            echo -e "当前操作系统供应商: $(rpm --eval '%{?_vendor}') \n"
            ;;
    esac
fi

if [[ ! -d $rpmtopdir ]]; then 
  echo "此脚本仅在 el5/el6/el7/amzn1/amzn2/amzn2023/kylin 上有效"
  echo "例如: ${0} el7"
  exit 1
fi

[[ -d $rpmtopdir ]] && BUILD_RPM

