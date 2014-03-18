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
export WEBRTC_OUT=$OUTPUT_DIR/$BUILD_MODE

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
    if [ $RETCODE -ne 0]; then
	exit $RETCODE
    fi
}

gclient config http://webrtc.googlecode.com/svn/trunk
echo "target_os = ['mac']" >> .gclient
RETRY_CMD="gclient sync"
retry_cmd
$SCRIPT_HOME/get-openssl.sh
cd trunk
export GYP_DEFINES="enable_tracing=1 build_with_libjingle=1 build_with_chromium=0 libjingle_objc=1 OS=mac target_arch=x64 use_system_ssl=1 use_openssl=0 use_nss=0"
export GYP_GENERATORS="ninja"
export GYP_GENERATOR_FLAGS="output_dir=$OUTPUT_DIR"
export GYP_CROSSCOMPILE=1
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

cd $ARTIFACT
tar cjf fattycakes-$REVISION.tar.bz2 lib include


