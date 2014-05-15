#!/bin/bash -x
set -e

# Return the type of a given file as returned by /usr/bin/file
# $1: file path
function get_file_type () {
    /usr/bin/file -b "$1" 2>/dev/null
}

# Returns success iff a given file is a thin archive.
# $1: file type as returned by get_file_type()
function is_file_type_thin_archive () {
  # The output of /usr/bin/file will depend on the OS:
  # regular Linux -> 'current ar archive'
  # regular Darwin -> 'current ar archive random library'
  # thin Linux -> 'data'
  # thin Darwin -> 'data'
  case "$1" in
    *"ar archive"*)
      return 1
      ;;
    "data")
      return 0
      ;;
    *)
      echo "ERROR: Unknown '$FILE_TYPE' file type" >&2
      return 2
      ;;
  esac
}

function copy_thin() {
    AR=$1
    LIB=$2
    DEST=$3
    OBJECTS=`$AR -t $LIB`
    for OBJECT in $OBJECTS; do
	cp $OBJECT $DEST
    done
}

if [ -z $WEBRTC_REVISION ]; then
    export SYNC_REVISION=""
else
    export SYNC_REVISION="-r $WEBRTC_REVISION"
fi

BASE_PATH=$(pwd)
BRANCH=trunk
gclient config https://webrtc.googlecode.com/svn/trunk
echo "target_os = ['android', 'unix']" >> .gclient
gclient sync --nohooks $SYNC_REVISION

# hop up one level and apply patches before continuing
cd $BASE_PATH
PATCHES=`find $BASE_PATH/patches -name *.diff`
PATCH_PREFIX=`git rev-parse --show-prefix`
for PATCH in $PATCHES; do
    git apply --verbose --directory=${PATCH_PREFIX} ${PATCH} || { echo "patch $PATCH failed to patch! panic and die!" ; exit 1; }
done

cd $BRANCH
ARCHS="arm ia32"
BUILD_MODE=Release
DEST_DIR=out_android/artifact
LIBS_DEST=$DEST_DIR/lib
HEADERS_DEST=$DEST_DIR/include

rm -rf $DEST_DIR
mkdir -p $LIBS_DEST
mkdir -p $HEADERS_DEST

for ARCH in $ARCHS; do
    (
	rm -rf out/$BUILD_MODE

  if [ "$ARCH" == "arm" ]; then
    ABI="armeabi"
    LIBNAME="arm"
  else
    ABI="x86"
    LIBNAME="x86"
  fi

	source build/android/envsetup.sh --target-arch=$ARCH

	export GYP_DEFINES="build_with_libjingle=1 OS=android \
                            build_with_chromium=0 \
                            enable_tracing=1 \
                            include_tests=0 \
                            enable_android_opensl=0 \
                			      target_arch=$ARCH \
                            $GYP_DEFINES"
	gclient runhooks --force
	ninja -v -C out/$BUILD_MODE all
	
	AR=`NDK_ROOT=$BASE_PATH/$BRANCH/third_party/android_tools/ndk ${BASE_PATH}/ndk-which ar $ABI`
	cd $LIBS_DEST
	LIBS=`find $BASE_PATH/$BRANCH/out/$BUILD_MODE -name '*.a'`
	for LIB in $LIBS; do
	    LIB_TYPE=$(get_file_type "$LIB")
	    if is_file_type_thin_archive "$LIB_TYPE"; then
		copy_thin $AR $LIB `pwd`
	    else
		$AR -x $LIB
	    fi
	done
	for a in `ls *.o | grep gtest` ; do 
	    rm $a
	done
	$AR -q libwebrtc_$LIBNAME.a *.o
	rm -f *.o
	cd $BASE_PATH/$BRANCH
    )
done

export REVISION=`svn info | grep Revision | cut -f2 -d: | tr -d ' '`
echo "WEBRTC_REVISION=$REVISION" > build.properties

cp -v $BASE_PATH/$BRANCH/out/$BUILD_MODE/*.jar $LIBS_DEST

HEADERS=`find webrtc third_party talk -name *.h | grep -v android_tools`
while read -r header; do
    mkdir -p $HEADERS_DEST/`dirname $header`
    cp $header $HEADERS_DEST/`dirname $header`
done <<< "$HEADERS"

cd $BASE_PATH/$BRANCH/$DEST_DIR
tar cjf fattycakes-$REVISION.tar.bz2 lib include

