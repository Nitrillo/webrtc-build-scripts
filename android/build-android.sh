#!/bin/bash -x
set -e

BASE_PATH=$(pwd)
BRANCH=trunk
gclient config https://webrtc.googlecode.com/svn/trunk
echo "target_os = ['android', 'unix']" >> .gclient
gclient sync --nohooks

cd $BRANCH
ARCHS="arm"
BUILD_MODE=Release
DEST_DIR=out_android/artifact
LIBS_DEST=$DEST_DIR/libs
HEADERS_DEST=$DEST_DIR/include
rm -rf $LIBS_DEST || echo "Clean $LIBS_DEST"
mkdir -p $LIBS_DEST

for ARCH in $ARCHS; do
    (
	rm -rf out/$BUILD_MODE
	source build/android/envsetup.sh --target-arch=$ARCH

	export GYP_DEFINES="build_with_libjingle=1 \
                            build_with_chromium=0 \
                            enable_tracing=1 \
                            include_tests=0 \
                            $GYP_DEFINES"
	gclient runhooks --force
	ninja -C out/$BUILD_MODE all
	
	AR=${BASE_PATH}/$BRANCH/`./third_party/android_tools/ndk/ndk-which ar`
	cd $LIBS_DEST
	for a in `ls $BASE_PATH/$BRANCH/out/$BUILD_MODE/*.a` ; do 
	    $AR -x $a
	done
	for a in `ls *.o | grep gtest` ; do 
	    rm $a
	done
	$AR -q libwebrtc_$ARCH.a *.o
	rm -f *.o
	cd $BASE_PATH/$BRANCH
    )
done

export REVISION=`svn info | grep Revision | cut -f2 -d: | tr -d ' '`
echo "WEBRTC_REVISION=$REVISION" > build.properties

cp $BASE_PATH/$BRANCH/out/$BUILD_MODE/*.jar $LIBS_DEST

HEADERS=`find webrtc third_party talk -name *.h | grep -v android_tools`
while read -r header; do
    mkdir -p $HEADERS_DEST/`dirname $header`
    cp $header $HEADERS_DEST/`dirname $header`
done <<< "$HEADERS"

cd $BASE_PATH/$BRANCH/$DEST_DIR
tar cjf fattycakes-$REVISION.tar.bz2 libs include

