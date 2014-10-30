#!/bin/bash -x
set -e

#
# This script automates the build process described by webrtc:
# https://code.google.com/p/webrtc/source/browse/trunk/talk/app/webrtc/objc/README
#
cd $(dirname $0)
SCRIPT_HOME=$(pwd)
export BUILD_MODE=Release
export OUTPUT_DIR=out_osx

ROOT=${SCRIPT_HOME}
if [ -z "${WEBRTC_BRANCH}" ]; then
    WEBRTC_BRANCH=38
fi
WEBRTC_ROOT=$ROOT/trunk

export WEBRTC_OUT=$OUTPUT_DIR/$BUILD_MODE
if [ -z $WEBRTC_REVISION ]; then
    export SYNC_REVISION=""
else
    export SYNC_REVISION="-r $WEBRTC_REVISION"
fi

function retry_cmd
{
    RETRIES=3
    RETCODE=-1
    set +e
    while [ $RETRIES -gt 0 ] && [ $RETCODE -ne 0 ]; do
        $RETRY_CMD
        RETCODE=$?
        RETRIES=`expr $RETRIES - 1`
    done
    set -e
    if [ $RETCODE -ne 0 ]; then
	exit $RETCODE
    fi
}

gclient config http://webrtc.googlecode.com/svn/trunk
perl -i -wpe "s/svn\/trunk/svn\/branches\/${WEBRTC_BRANCH}/g" .gclient

echo "target_os = ['mac']" >> .gclient
if [ "1" != "$NOPATCH" ]; then
RETRY_CMD="gclient sync $SYNC_REVISION"
retry_cmd
fi
$SCRIPT_HOME/get-openssl.sh
cd ${WEBRTC_ROOT}
export GYP_DEFINES="enable_tracing=1 build_with_libjingle=1 build_with_chromium=0 libjingle_objc=1 OS=mac target_arch=x64 use_system_ssl=1 use_openssl=0 use_nss=0"
if [ "1" == "$DEBUG" ]; then
    export GYP_DEFINES="$GYP_DEFINES fastbuild=0"
else
    export GYP_DEFINES="$GYP_DEFINES fastbuild=1"
fi
export GYP_GENERATORS="ninja"
export GYP_GENERATOR_FLAGS="output_dir=$OUTPUT_DIR"
export GYP_CROSSCOMPILE=1
if [ "1" != "$NOPATCH" ]; then
    # hop up one level and apply patches before continuing
    cd $ROOT
    PATCHES=`find $PWD/patches -name *.diff`
    PATCH_PREFIX=`git rev-parse --show-prefix`
    for PATCH in $PATCHES; do
        git apply --verbose --directory=${PATCH_PREFIX} ${PATCH} || { echo "patch $PATCH failed to patch! panic and die!" ; exit 1; }
    done
    cd $WEBRTC_ROOT
fi
perl -0pi -e 's/gdwarf-2/g/g' tools/gyp/pylib/gyp/xcode_emulation.py
perl -0pi -e 's/\$\(SDKROOT\)\/usr\/lib\/libcrypto\.dylib/-lcrypto/g' talk/libjingle.gyp
perl -0pi -e 's/\$\(SDKROOT\)\/usr\/lib\/libssl\.dylib/-lssl/g' talk/libjingle.gyp
gclient runhooks
ninja -C $WEBRTC_OUT -t clean || ls $WEBRTC_OUT
ninja -v -C $WEBRTC_OUT libjingle_peerconnection_objc_test

AR=`xcrun -f ar`
PWD=`pwd`
ROOT=$PWD
LIBS_OUT=`find $PWD/$WEBRTC_OUT -d 1 -name '*.a'`
FATTYCAKES_OUT=out.huge
rm -rf $FATTYCAKES_OUT || echo "clean $FATTYCAKES_OUT"
mkdir -p $FATTYCAKES_OUT
cd $FATTYCAKES_OUT
for LIB in $LIBS_OUT
do
    $AR -x $LIB
done
$AR -q libfattycakes.a *.o
cd $ROOT

ARTIFACT=$OUTPUT_DIR/artifact
rm -rf $ARTIFACT || echo "clean $ARTIFACT"
mkdir -p $ARTIFACT/lib
mkdir -p $ARTIFACT/include
cp $FATTYCAKES_OUT/libfattycakes.a $OUTPUT_DIR/artifact/lib
HEADERS_OUT=`find net talk third_party webrtc -name *.h`
for HEADER in $HEADERS_OUT
do
    HEADER_DIR=`dirname $HEADER`
    mkdir -p $ARTIFACT/include/$HEADER_DIR
    cp $HEADER $ARTIFACT/include/$HEADER
done

cd $ROOT
REVISION=`svn info $BRANCH | grep Revision | cut -f2 -d: | tr -d ' '`
echo "WEBRTC_REVISION=$REVISION" > build.properties
echo "WEBRTC_VERSION=${WEBRTC_BRANCH}" >> build.properties

cd $ARTIFACT
tar cjf fattycakes-$REVISION.tar.bz2 lib include


