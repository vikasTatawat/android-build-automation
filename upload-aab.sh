#!/bin/bash
cd $WORKSPACE



// Clone your React Native app from Git
echo $GIT_BRANCH > GIT_BRANCH
echo $GIT_COMMIT > GIT_COMMIT

REMOTE_APK_PATH="/var/www/html/matpatra/new-community-app/android/app/build/outputs/bundle/release/"
S3_BUCKET="s3://matpatra-apps/community/"
CURRENT_DATE="$(date +%d-%m-%Y)/play-store-builds/"
EPOCH_TIME=$(date +%s)
FILE_NAME="-app-release-production-"$EPOCH_TIME".aab"
SERVER=#.#.#.#

# Define an array of combinations
COMBINATIONS=(
 #app Details
)


# Loop through each combination and echo the values
for COMBINATION in "${COMBINATIONS[@]}"; do

  # Parse the combination into individual variables
  IFS=',' read -r NAME IMAGE_URL PACKAGE_NAME APP_NAME <<< "$COMBINATION"
  echo "Processing:"
  echo "Name: $NAME"
  echo "Image URL: $IMAGE_URL"
  echo "Package Name: $PACKAGE_NAME"
  echo "App Name: $APP_NAME"
  echo "--------------------------"

  # Pass variables into the SSH session explicitly

ssh -o StrictHostKeyChecking=no root@$SERVER 'rm -rf /var/www/html/matpatra/new-community-app/*'
rsync -azi --exclude=.git* ./ root@$SERVER:/var/www/html/matpatra/new-community-app/

  ssh -o StrictHostKeyChecking=no root@$SERVER bash <<EOCMD
    BASE_DIR="/var/www/html/matpatra/new-community-app/android/app/src/main/res"
    TEMP_DIR="/tmp/icon-resize"
    mkdir -p "\$TEMP_DIR"

    # Check if IMAGE_URL is accessible
    if wget -q --spider "$IMAGE_URL"; then
      echo "Downloading image..."
      wget -O "\$TEMP_DIR/original.png" "$IMAGE_URL"

      # Define the target directories and sizes for ic_launcher.png
      declare -A RESOLUTIONS_LAUNCHER=(
        ["mipmap-hdpi"]="72x72"
        ["mipmap-mdpi"]="48x48"
        ["mipmap-xhdpi"]="96x96"
        ["mipmap-xxhdpi"]="144x144"
        ["mipmap-xxxhdpi"]="192x192"
      )

      # Define the target directories and sizes for ic_launcher_foreground.png
      declare -A RESOLUTIONS_FOREGROUND=(
        ["mipmap-hdpi"]="162x162"
        ["mipmap-mdpi"]="108x108"
        ["mipmap-xhdpi"]="216x216"
        ["mipmap-xxhdpi"]="324x324"
        ["mipmap-xxxhdpi"]="432x432"
      )

      # Replace images in each directory for ic_launcher.png
      for DIR in "\${!RESOLUTIONS_LAUNCHER[@]}"; do
        SIZE="\${RESOLUTIONS_LAUNCHER[\$DIR]}"
        TARGET_DIR="\$BASE_DIR/\$DIR"
        mkdir -p "\$TARGET_DIR"
        echo "Processing ic_launcher.png for \$DIR with size \$SIZE..."

        # Create and move resized images
        convert "\$TEMP_DIR/original.png" -resize "\$SIZE" "\$TEMP_DIR/ic_launcher.png"
        mv "\$TEMP_DIR/ic_launcher.png" "\$TARGET_DIR/ic_launcher.png"
        echo "Replaced ic_launcher.png in \$TARGET_DIR"
      done

      # Replace images in each directory for ic_launcher_foreground.png
      for DIR in "\${!RESOLUTIONS_FOREGROUND[@]}"; do
        SIZE="\${RESOLUTIONS_FOREGROUND[\$DIR]}"
        TARGET_DIR="\$BASE_DIR/\$DIR"
        mkdir -p "\$TARGET_DIR"
        echo "Processing ic_launcher_foreground.png for \$DIR with size \$SIZE..."

        # Create and move resized images
        convert "\$TEMP_DIR/original.png" -resize "\$SIZE" "\$TEMP_DIR/ic_launcher_foreground.png"
        mv "\$TEMP_DIR/ic_launcher_foreground.png" "\$TARGET_DIR/ic_launcher_foreground.png"
        echo "Replaced ic_launcher_foreground.png in \$TARGET_DIR"
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
    echo "App Name: $APP_NAME"
    echo "--------------------------"
cd /var/www/html/matpatra/new-community-app
echo "Setting Env"
cp .env.production .env
rm -rf .env.stage .env.production

# Replace com.pro.lccommunity25tm with com.pro.aiccsc26tm across the project
echo "Replacing package name com.pro.lccommunity25tm with com.pro.$PACKAGE_NAME"

grep -rl 'com.pro.lccommunity25tm' . | xargs sed -i "s/com\.pro\.lccommunity25tm/com.pro.$PACKAGE_NAME/g"

echo "Replacing package name LC Community with $NAME"

grep -rl 'LC Community' . | xargs sed -i "s/LC Community/$NAME/g"

echo "Replacing app name [lcc] to [$APP_NAME]"

grep -rl '\[hostName:"lcc"\]' . | xargs sed -i "s/\[hostName:\"lcc\"\]/[hostName:\"$APP_NAME\"]/g"


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

echo "Uploading com.pro.$PACKAGE_NAME"
cd /var/www/html/matpatra/
./upload_aab.sh "com.pro.$PACKAGE_NAME" "community/$CURRENT_DATE$NAME-$FILE_NAME" "Version_name"
rm -rf app.aab
EOF

done
