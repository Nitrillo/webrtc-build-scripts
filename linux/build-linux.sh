#!/bin/bash -ex

gclient config http://webrtc.googlecode.com/svn/trunk
gclient sync --force
cd trunk
BUILD_OUT=out/Debug
ninja -C $BUILD_OUT -t clean
ninja -C $BUILD_OUT all

PWD=`pwd`
ROOT=$PWD
LIBS_OUT=`find $ROOT/$BUILD_OUT -name '*.a'`
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

cd $ROOT
REVISION=`svn info $BRANCH | grep Revision | cut -f2 -d: | tr -d ' '`
echo "WEBRTC_REVISION=$REVISION" > build.properties

cd $ARTIFACT
tar cjf fattycakes-linux-$REVISION.tar.bz2 lib include


