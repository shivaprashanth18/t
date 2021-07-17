#!/bin/sh
function failed()
{
    echo "Failed $* : $@" >&2
    exit 1
}

#
# usage
#   ios_autobuild_interpreted.sh <game_dir_name> <configurations_to_build> <code_sign_identity> <iPhone|iPad|iPhone_iPad> [<Config-Type>]
#


set -ex

if [ "x$1" = "x" ]; then
    failed no_game_dir_set
fi
if [ "x$2" = "x" ]; then
    failed no_configuration_set
fi
if [ "x$3" = "x" ]; then
    failed no_code_sign_identity_set
fi
if [ "x$4" = "x" ]; then
    failed no_ios_target_iPhone_or_iPad_set
fi

# We need to build the code in the Runner directory
# using the data and the info from the game (given in the build.config)

#SOURCEDIR=~/Projects
#[  -d "$SOURCEDIR" ] || SOURCEDIR=~/source
#[  -d "$SOURCEDIR" ] || failed "Source Directory does not exist"
RUNNERDIR=$WORKSPACE/GameMaker/Runner/VC_Runner
if [  "x$1" != "xnone" ]; then
    GAMEDIR=$WORKSPACE/Games/$1
else
    GAMEDIR=$RUNNERDIR
fi
TOOLSDIR=$WORKSPACE/GameMaker/Tools/bin
PASSWORD=Glasgow0712
if [ -f "$WORKSPACE/GameMaker/svn_version.txt" ]; then
    SVN_REVISION=`cat $WORKSPACE/GameMaker/svn_version.txt`
else    
    SVN_REVISION=`svnversion $GAMEDIR`
fi
export YYHudsonConfig=$5

export OUTPUT=$GAMEDIR/output/interpreted
rm -rf $OUTPUT
mkdir -p $OUTPUT
PROFILE_HOME=~/Library/MobileDevice/Provisioning\ Profiles/
KEYCHAIN=/Library/Keychains/System.keychain
YYGameName=$1
if [  "x$1" != "xnone" ]; then
    . "$GAMEDIR/build/build$YYHudsonConfig.config"
else
    . "$GAMEDIR/iPad_Runner/yoyorunner.config"
    export YYGameName=
fi

if [ "x$SOURCE_BUILD_NUMBER" == "x" ]; then
    SOURCE_BUILD_NUMBER=0
fi

# Set the target device family correctly
YY_TARGET_DEVICE_FAMILY=1,2,3
YY_APP_ID=$YY_iPhone_AppId
YY_MIN_VERSION=8.0
YY_APP_VERSION=$YY_iPhone_VERSION
YY_SDKS=appletvos
YYDisplayName=$YY_iPhone_DisplayName
YYBuildConfigInfo=$YY_iPhone_BuildConfigInfo
YY_ARCHS="arm64" 

# set compile options up if needed
YY_EXTRA_DEFINES=""
if [ "x$YYBuildConfigInfo" != "x" ]; then
    YY_EXTRA_DEFINES="YOYO_BUILD_CONFIG=\"$YYBuildConfigInfo\""
fi
if [[ "$YY_BASE_NAME" == "Zeus" ]]; then 
    YY_EXTRA_DEFINES="$YY_EXTRA_DEFINES YY_ZEUS"
fi


# Process the build type Master|Adhoc|Distribution
case $2 in
Master) YY_CONFIGURATION=Master
    YY_CERT_DIR=$RUNNERDIR/tvOS_Runner
    ;;
Adhoc) YY_CONFIGURATION=Master
    YY_CERT_DIR=$GAMEDIR/build
    ;;
Distribution) YY_CONFIGURATION=Master
    YY_CERT_DIR=$GAMEDIR/build
    ;;
*)  failed configuration_incorrect_should_be_Master_Adhoc_Distribution
    ;;
esac

[ -d "$PROFILE_HOME" ] || mkdir -p "$PROFILE_HOME"

# Only play with the keychains if we are being run from Jenkins - so check to see if the environment variables are set up from Jenkins
#if [  "x$EXECUTOR_NUMBER" != "x" ]; then
#   security list-keychains -s $KEYCHAIN
#   #security default-keychain -s $KEYCHAIN
#   #security unlock-keychain -p $PASSWORD $KEYCHAIN
#   security list-keychains
#   security default-keychain
#   security dump-keychain
#fi

# cd $RUNNERDIR/iPad_Runner
# agvtool new-version -all $BUILD_NUMBER
if [ ! "x$2" = "xMaster" ]; then    
        PROVISION=$(eval echo \$`echo YY_$4_Provision$2`);
    CERT="$YY_CERT_DIR/$PROVISION";
else
    CERT=`ls -1 $YY_CERT_DIR/*.mobileprovision`
fi
[ -f "$CERT" ] && cp "$CERT" "$PROFILE_HOME"

cd $RUNNERDIR/tvOS_Runner
cp -f tvOS_Runner-Info.plist old-tvOS_Runner-Info.plist
    
# set the App Id in the plist   
defaults write $RUNNERDIR/tvOS_Runner/tvOS_Runner-Info CFBundleIdentifier $YY_APP_ID
defaults write $RUNNERDIR/tvOS_Runner/tvOS_Runner-Info CFBundleVersion $YY_APP_VERSION

# remove any previous .app
if [ -d build/$config-appletvos ]; then
    pushd build/$config-appletvos
    [ -f "$CERT" ] && cp "$CERT" .
    rm -rf .app
    popd
fi

# Remove old public headers from build
if [ -d $RUNNERDIR/tvOS_Runner/build/Master-appletvos/include ]; then
    rm -rf $RUNNERDIR/tvOS_Runner/build/Master-appletvos/include
fi

if [ -d $RUNNERDIR/tvOS_Runner/build/Master-appletvsimulator/include ]; then
    rm -rf $RUNNERDIR/tvOS_Runner/build/Master-appletvsimulator/include
fi

# Xcode build
YYProductName=`echo $YYDisplayName | sed 's/ /_/g'`     

xcodebuild -allowProvisioningUpdates -UseModernBuildSystem=0 -configuration Master -sdk appletvos ARCHS="arm64" -target tvOS_Runner VALID_ARCHS="arm64" ONLY_ACTIVE_ARCH=NO ENABLE_BITCODE=YES YYGameDir="$YYGameName" PRODUCT_NAME=$YYProductName CODE_SIGN_IDENTITY="$3" TARGETED_DEVICE_FAMILY="$YY_TARGET_DEVICE_FAMILY" IPHONEOS_DEPLOYMENT_TARGET=$YY_MIN_VERSION  GCC_PREPROCESSOR_DEFINITIONS="USE_FREETYPE FT2_BUILD_LIBRARY FREETYPE2_STATIC NDEBUG IPAD TVOS HAVE_STAT HAVE_NANOSLEEP HAVE_STDINT_H HAVE_TIME_H YOYO_BUILD_NUMBER=$SOURCE_BUILD_NUMBER YOYO_REVISION_NUMBER=$SVN_REVISION USE_YYOPENAL $YY_EXTRA_DEFINES" clean build || failed clean_did_not_work;

pushd $RUNNERDIR/tvOS_Runner/build/tvOS_Runner.build/Master-appletvos/tvOS_Runner.build/Objects-normal/arm64
ar cr $OUTPUT/libyoyo_interpreted-arm64.a *.o
popd

xcodebuild -allowProvisioningUpdates -UseModernBuildSystem=0 -configuration Master -sdk appletvsimulator ARCHS="x86_64" -target tvOS_Runner VALID_ARCHS="x86_64" ONLY_ACTIVE_ARCH=NO YYGameDir="$YYGameName" PRODUCT_NAME=$YYProductName CODE_SIGN_IDENTITY="$3" TARGETED_DEVICE_FAMILY="$YY_TARGET_DEVICE_FAMILY" IPHONEOS_DEPLOYMENT_TARGET=$YY_MIN_VERSION  GCC_PREPROCESSOR_DEFINITIONS="USE_FREETYPE FT2_BUILD_LIBRARY FREETYPE2_STATIC NDEBUG IPAD TVOS HAVE_STAT HAVE_NANOSLEEP HAVE_STDINT_H HAVE_TIME_H YOYO_BUILD_NUMBER=$SOURCE_BUILD_NUMBER YOYO_REVISION_NUMBER=$SVN_REVISION USE_YYOPENAL $YY_EXTRA_DEFINES" clean build || failed clean_did_not_work;

pushd $RUNNERDIR/tvOS_Runner/build/tvOS_Runner.build/Master-appletvsimulator/tvOS_Runner.build/Objects-normal/x86_64
ar cr $OUTPUT/libyoyo_interpreted-x86_64.a *.o
popd

# Copy headers to output
cp -rf $RUNNERDIR/tvOS_Runner/build/Master-appletvsimulator/include $OUTPUT/include

# revert the plist that we modify
cp -f $RUNNERDIR/tvOS_Runner/old-tvOS_Runner-Info.plist $RUNNERDIR/tvOS_Runner/tvOS_Runner.plist
rm -f $RUNNERDIR/tvOS_Runner/old-tvOS_Runner-Info.plist 

# create the output archive
ARCHIVE="$OUTPUT/$JOB_NAME-Master-Interp.zip";
pushd $OUTPUT
lipo -output libyoyo_interpreted.a -create -arch arm64 $OUTPUT/libyoyo_interpreted-arm64.a -arch x86_64 $OUTPUT/libyoyo_interpreted-x86_64.a
zip -r -T -y "$ARCHIVE" libyoyo_interpreted.a include || failed zip
popd

# build notifications library
JOB_NAME="${JOB_NAME}-Notifications"
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
bash $SCRIPTS_DIR/tvos_notifications_autobuild_interpreted.sh $1 $2 "${3}" $4 $5
