#!/bin/bash
cd $WORKSPACE



// Clone your React Native app from Git
echo $GIT_BRANCH > GIT_BRANCH
echo $GIT_COMMIT > GIT_COMMIT

REMOTE_APK_PATH="PROJECT_PATH/android/app/build/outputs/bundle/release/"
S3_BUCKET="##"
CURRENT_DATE="$(date +%d-%m-%Y)/play-store-builds/"
EPOCH_TIME=$(date +%s)
FILE_NAME="app-release-"$EPOCH_TIME".aab"
SERVER=EC2_SERVER_IP

# Define an array of combinations
COMBINATIONS=(
  "YOUR_APP_NAME,YOUR_APP_ICON_RAW_IAMGE_LINK,YOU_APP_PACKAGE(without com.pro. eg: aiccsc26tm)"
  "...there can be multiple"
 )


# Loop through each combination and echo the values
for COMBINATION in "${COMBINATIONS[@]}"; do

  # Parse the combination into individual variables
  IFS=',' read -r NAME IMAGE_URL PACKAGE_NAME <<< "$COMBINATION"
  echo "Processing:"
  echo "Name: $NAME"
  echo "Image URL: $IMAGE_URL"
  echo "Package Name: $PACKAGE_NAME"
  echo "--------------------------"

  # Pass variables into the SSH session explicitly

ssh -o StrictHostKeyChecking=no root@$SERVER 'rm -rf PROJECT_PATH/*'
rsync -azi --exclude=.git* ./ root@$SERVER:PROJECT_PATH/

  # Execute commands on the remote server
  ssh -o StrictHostKeyChecking=no root@$SERVER bash <<EOCMD
    BASE_DIR="PROJECT_PATH/android/app/src/main/res"
    TEMP_DIR="/tmp/icon-resize"
    mkdir -p "\$TEMP_DIR"

    # Check if IMAGE_URL is accessible
    if wget -q --spider "$IMAGE_URL"; then
      echo "Downloading image..."
      wget -O "\$TEMP_DIR/original.png" "$IMAGE_URL"

      # Define the target directories and sizes
      declare -A RESOLUTIONS=(
        ["mipmap-hdpi"]="72x72"
        ["mipmap-mdpi"]="48x48"
        ["mipmap-xhdpi"]="96x96"
        ["mipmap-xxhdpi"]="144x144"
        ["mipmap-xxxhdpi"]="192x192"
      )

      # Replace images in each directory
      for DIR in "\${!RESOLUTIONS[@]}"; do
        SIZE="\${RESOLUTIONS[\$DIR]}"
        TARGET_DIR="\$BASE_DIR/\$DIR"
        mkdir -p "\$TARGET_DIR"
        echo "Processing \$DIR with size \$SIZE..."

        # Create and move resized images
        convert "\$TEMP_DIR/original.png" -resize "\$SIZE" "\$TEMP_DIR/ic_launcher.png"
        mv "\$TEMP_DIR/ic_launcher.png" "\$TARGET_DIR/ic_launcher.png"
        echo "Replaced ic_launcher.png in \$TARGET_DIR"
      done
    else
      echo "Error: Unable to access IMAGE_URL: $IMAGE_URL"
      exit 1
    fi

    # Clean up temporary files
    rm -rf "\$TEMP_DIR"
    echo "Image replacement process completed!"
EOCMD

ssh -o StrictHostKeyChecking=no root@$SERVER bash <<EOF
    NAME="$NAME"
    IMAGE_URL="$IMAGE_URL"
    PACKAGE_NAME="$PACKAGE_NAME"
    echo "Inside SSH Session"
    echo "Name: $NAME"
    echo "Image URL: $IMAGE_URL"
    echo "Package Name: $PACKAGE_NAME"
    echo "--------------------------"
cd PROJECT_PATH

# Replace com.pro.CURRENT_PACKAGE_NAME_IN_YOUR_PROJECT with $PACKAGE_NAME across the project
echo "Replacing package name com.pro.CURRENT_PACKAGE_NAME_IN_YOUR_PROJECT with com.pro.$PACKAGE_NAME"

grep -rl 'com.pro.CURRENT_PACKAGE_NAME_IN_YOUR_PROJECT' . | xargs sed -i "s/com\.pro\.CURRENT_PACKAGE_NAME_IN_YOUR_PROJECT/com.pro.$PACKAGE_NAME/g"

echo "Replacing package name CURRENT_APP_NAME with $NAME"

grep -rl 'CURRENT_APP_NAME' . | xargs sed -i "s/CURRENT_APP_NAME/$NAME/g"

npm install --legacy-peer-deps

cd android

echo "Creating Build"
./gradlew bundleRelease

echo "Build Process Completed"

sleep 1
EOF
                
# SSH into the server to find and upload the APK to S3
echo "Locating and uploading the built APK from the server..."
ssh -o StrictHostKeyChecking=no root@$SERVER <<EOF
set -e # Exit on any error
	  NAME="$NAME"
    IMAGE_URL="$IMAGE_URL"
    PACKAGE_NAME="$PACKAGE_NAME"

    echo "Inside Another SSH Session"
    echo "Name: $NAME"
    echo "Image URL: $IMAGE_URL"
    echo "Package Name: $PACKAGE_NAME"
    echo "--------------------------"

APK_FILE=\$(find "$REMOTE_APK_PATH" -name "*.aab" | head -n 1)

if [ -f "\$APK_FILE" ]; then
    echo "Uploading APK to S3..."
    aws s3 cp "\$APK_FILE" "$S3_BUCKET$CURRENT_DATE$NAME-$FILE_NAME"
    echo "APK uploaded successfully to S3."
else
    echo "APK build failed or not found in $REMOTE_APK_PATH." 
    exit 1
fi
EOF

done