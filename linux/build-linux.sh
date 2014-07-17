#!/bin/bash -ex
PWD=`pwd`
ROOT=$PWD
WEBRTC_BRANCH=3.54
WEBRTC_ROOT=$ROOT/trunk

gclient config http://webrtc.googlecode.com/svn/trunk
perl -i -wpe "s/svn\/trunk/svn\/branches\/${WEBRTC_BRANCH}/g" .gclient

if [ "1" == "$DEBUG" ]; then
    export GYP_DEFINES="$GYP_DEFINES fastbuild=0"
else
    export GYP_DEFINES="$GYP_DEFINES fastbuild=1"
fi


gclient sync --force
cd ${WEBRTC_ROOT}
BUILD_OUT=out/Debug
ninja -C $BUILD_OUT -t clean
ninja -v -C $BUILD_OUT all

LIBS_OUT=`find $WEBRTC_ROOT/$BUILD_OUT -name '*.a'`
FATTYCAKES_OUT=out.huge
rm -rf $FATTYCAKES_OUT || echo "clean $FATTYCAKES_OUT"
mkdir -p $FATTYCAKES_OUT
cd $FATTYCAKES_OUT
AR=`which ar`

function copy_thin {
    OBJECTS=`$AR -t $1`
    for OBJECT in $OBJECTS
    do
	cp $OBJECT $2
    done
}

for LIB in $LIBS_OUT
do
    $AR -x $LIB || copy_thin $LIB `pwd`
done
$AR -q libfattycakes.a *.o
cd $ROOT

cd ${WEBRTC_ROOT}
ARTIFACT=out/artifact
rm -rf $ARTIFACT || echo "clean $ARTIFACT"
mkdir -p $ARTIFACT/lib
mkdir -p $ARTIFACT/include
cp $FATTYCAKES_OUT/libfattycakes.a $ARTIFACT/lib
HEADERS_OUT=`find talk third_party webrtc -name *.h`
for HEADER in $HEADERS_OUT
do
    HEADER_DIR=`dirname $HEADER`
    mkdir -p $ARTIFACT/include/$HEADER_DIR
    cp $HEADER $ARTIFACT/include/$HEADER
done

REVISION=`svn info $BRANCH | grep Revision | cut -f2 -d: | tr -d ' '`
echo "WEBRTC_REVISION=$REVISION" > build.properties
echo "WEBRTC_VERSION=${WEBRTC_BRANCH}" >> build.properties

cd $ARTIFACT
tar cjf fattycakes-$REVISION.tar.bz2 lib include


