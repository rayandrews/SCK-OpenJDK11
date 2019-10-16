#!/bin/bash
#

# Required vars :
#
# OBF_BUILD_PATH (absolute path of project, ie obuildfactory/openjdk11/linux)
# OBF_SOURCES_PATH (absolute path of project sources)
# OBF_PROJECT_NAME (ie: openjdk11)
# OBF_MILESTONE (ie: b56)

function cacerts_gen()
{
  local DESTCERTS=$1
  local TMPCERTSDIR=`mktemp -d`

  pushd $TMPCERTSDIR
  curl -L http://curl.haxx.se/ca/cacert.pem -o cacert.pem
  cat cacert.pem | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{ print $0; }' > cacert-clean.pem
  rm -f cacerts cert_*
# split  -p "-----BEGIN CERTIFICATE-----" cacert-clean.pem cert_
  csplit -k -f cert_ cacert-clean.pem "/-----BEGIN CERTIFICATE-----/" {*}

  for CERT_FILE in cert_*; do
    ALIAS=$(basename ${CERT_FILE})
    keytool -noprompt -import -alias ${ALIAS} -keystore cacerts -storepass 'changeit' -file ${CERT_FILE} || :
    rm -f $CERT_FILE
  done

  rm -f cacert.pem cacert-clean.pem
  mv cacerts $DESTCERTS

  popd
  rm -rf $TMPCERTSDIR
}

function ensure_ant()
{
  if [ ! -x $OBF_DROP_DIR/ant/bin/ant ]; then
    mkdir -p $OBF_DROP_DIR/ant
    pushd $OBF_DROP_DIR/ant
    curl -L http://archive.apache.org/dist/ant/binaries/apache-ant-1.9.14-bin.tar.gz -o apache-ant-1.9.14-bin.tar.gz
    tar xzf apache-ant-1.9.14-bin.tar.gz
    mv apache-ant-1.9.14/* .
    rmdir apache-ant-1.9.14
    rm -f apache-ant-1.9.14-bin.tar.gz
    popd
  fi

  export PATH=$OBF_DROP_DIR/ant/bin:$PATH
  export ANT_HOME=$OBF_DROP_DIR/ant
}

function ensure_cacert()
{
  if [ ! -f $OBF_DROP_DIR/cacerts ]; then
    echo "no cacerts found, regenerate it..."
    cacerts_gen $OBF_DROP_DIR/cacerts
  else
    if test `find "$OBF_DROP_DIR/cacerts" -mtime +7`
    then
      echo "cacerts older than one week, regenerate it..."
      cacerts_gen $OBF_DROP_DIR/cacerts
    fi
  fi
}

function check_version()
{
    local version=$1 check=$2
    local winner=$(echo -e "$version\n$check" | sed '/^$/d' | sort -nr | head -1)
    [[ "$winner" = "$version" ]] && return 0
    return 1
}

function ensure_freetype()
{
  FT_VER=`freetype-config --ftversion`
  check_version "2.3" $FT_VER

  if [ $? == 0 ]; then

    if [ ! -d $OBF_DROP_DIR/freetype ]; then
      pushd $OBF_DROP_DIR
      curl -L http://freefr.dl.sourceforge.net/project/freetype/freetype2/2.9.1/freetype-2.9.1.tar.bz2 -o freetype-2.9.1.tar.bz2
      tar xjf freetype-2.9.1.tar.bz2
      cd freetype-2.9.1
      mkdir -p $OBF_DROP_DIR/freetype
      ./configure --prefix=$OBF_DROP_DIR/freetype
      make
      make install
      popd
    fi

    export OBF_FREETYPE_DIR=$OBF_DROP_DIR/freetype
    export OBF_FREETYPE_LIB_PATH=$OBF_FREETYPE_DIR/lib
    export OBF_FREETYPE_HEADERS_PATH=$OBF_FREETYPE_DIR/include

  fi
}

#
# Determine BUILD JVM to use
#
function ensure_java11()
{
  if [ ! -z "$OBF_JAVA11_HOME" ]; then
    export OBF_BOOTDIR=$OBF_JAVA11_HOME
    return
  else
    echo "Can't find Java 11 Home Directory, build failed"
    exit -1
  fi
}

#
# Build using new build system
#
function build()
{
  echo "### Building SCK OpenJDK11 ###"

  pushd $OBF_SOURCES_PATH >>/dev/null

  # patch common/autoconf/version-numbers
  if [ -f make/autoconf/version-numbers ]; then
    mv make/autoconf/version-numbers make/autoconf/version-numbers.orig
    cat make/autoconf/version-numbers.orig | grep -v "MILESTONE" | grep -v "JDK_BUILD_NUMBER" | grep -v "COMPANY_NAME" > make/autoconf/version-numbers
  fi

  export JDK_BUILD_NUMBER=$OBF_BUILD_DATE
  export MILESTONE=$OBF_MILESTONE
  export COMPANY_NAME=$BUNDLE_VENDOR
  export STATIC_CXX=false

  rm -rf $OBF_WORKSPACE_PATH/.ccache
  mkdir -p $OBF_WORKSPACE_PATH/.ccache

  if [ "$XDEBUG" = "true" ]; then

      if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then
        BUILD_PROFILE=linux-x86_64-normal-server-fastdebug
      elif [ "$CPU_BUILD_ARCH" = "ppc64" ]; then
        BUILD_PROFILE=linux-ppc64-normal-server-fastdebug
        EXTRA_FLAGS=$XEXTRA_FLAGS "--with-jvm-interpreter=cpp"
      else
        BUILD_PROFILE=linux-x86-normal-server-fastdebug
      fi

      # https://bugs.openjdk.java.net/browse/JDK-8047952
      EXTRA_CFLAGS="-U_FORTIFY_SOURCE"
      
      rm -rf $OBF_SOURCES_PATH/build/$BUILD_PROFILE
      mkdir -p $OBF_SOURCES_PATH/build/$BUILD_PROFILE
      pushd $OBF_SOURCES_PATH/build/$BUILD_PROFILE >>/dev/null

      bash $OBF_SOURCES_PATH/configure \
	         --with-boot-jdk=$OBF_BOOTDIR \
	         --with-freetype=$OBF_FREETYPE_DIR \
	         --with-cacerts-file=$OBF_DROP_DIR/cacerts \
           --with-ccache-dir=$OBF_WORKSPACE_PATH/.ccache \
	         --enable-debug \
           --with-conf-name=$BUILD_PROFILE \
	         --disable-warnings-as-errors $EXTRA_FLAGS

  else

      if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then
        BUILD_PROFILE=linux-x86_64-normal-server-release
      elif [ "$CPU_BUILD_ARCH" = "ppc64" ]; then
        BUILD_PROFILE=linux-ppc64-normal-server-release
            EXTRA_FLAGS=$XEXTRA_FLAGS "--with-jvm-interpreter=cpp"
      else
        BUILD_PROFILE=linux-x86-normal-server-release
      fi

      rm -rf $OBF_SOURCES_PATH/build/$BUILD_PROFILE
      mkdir -p $OBF_SOURCES_PATH/build/$BUILD_PROFILE
      pushd $OBF_SOURCES_PATH/build/$BUILD_PROFILE >>/dev/null

      bash $OBF_SOURCES_PATH/configure \
	         --with-boot-jdk=$OBF_BOOTDIR \
	         --with-freetype=$OBF_FREETYPE_DIR \
	         --with-cacerts-file=$OBF_DROP_DIR/cacerts \
           --with-conf-name=$BUILD_PROFILE \
           --disable-warnings-as-errors $EXTRA_FLAGS
      
  fi

  export IMAGE_BUILD_DIR=$OBF_SOURCES_PATH/build/$BUILD_PROFILE/images

  if [ "$XCLEAN" = "true" ]; then
      CONT=$BUILD_PROFILE make clean
  fi

  if [ "$XDEBUG_BINARIES" = "false" ]; then
      CONT=$BUILD_PROFILE make DEBUG_BINARIES=false EXTRA_CFLAGS=$EXTRA_CFLAGS images
  else
      CONT=$BUILD_PROFILE make DEBUG_BINARIES=true EXTRA_CFLAGS=$EXTRA_CFLAGS images
  fi

  popd >>/dev/null

  # restore original common/autoconf/version-numbers
  if [ -f make/autoconf/version-numbers.orig ]; then
    mv make/autoconf/version-numbers.orig make/autoconf/version-numbers
  fi

  popd >>/dev/null
}

#
# Verify build
#
function test_build()
{
  if [ -x $IMAGE_BUILD_DIR/jdk/bin/java ]; then
    $IMAGE_BUILD_DIR/jdk/bin/java -version
  else
    echo "can't find java into JDK $IMAGE_BUILD_DIR/jdk, build failed"
    exit -1
  fi
}

#
# Archives build
#
function archive_build()
{
  pushd $IMAGE_BUILD_DIR
  mkdir -p $OBF_DROP_DIR

  if [ "$XDEBUG" = "true" ]; then
    FILENAME_PREFIX="-fastdebug"
  fi

  tar cjf $OBF_DROP_DIR/jdk$FILENAME_PREFIX-$OBF_BASE_ARCH-$OBF_BUILD_DATE.tar.bz2 jdk

  echo "produced tarball files under $OBF_DROP_DIR"
  ls -l $OBF_DROP_DIR/jdk$FILENAME_PREFIX-$OBF_BASE_ARCH-$OBF_BUILD_DATE.tar.bz2

  popd
}

#
# Build start here
#

CPU_BUILD_ARCH=`uname -m`

export JDK_BUNDLE_VENDOR="UCAREJDK"
export BUNDLE_VENDOR="UCAREJDK"

echo "Calculated MILESTONE=$OBF_MILESTONE, BUILD_NUMBER=$OBF_BUILD_NUMBER"

#
# Ensure cacerts are available
#
ensure_cacert

#
# Ensure Ant is available
#
ensure_ant

#
# Ensure freetype is correct one
#
ensure_freetype

#
# Select Java 11 (32 / 64bits)
#
ensure_java11

#
# Build JDK images
#
build

#
# Test Build
#
test_build

#
# Archive Builds
#
archive_build
