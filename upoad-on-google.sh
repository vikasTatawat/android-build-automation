#!/bin/bash

# Set variables
S3_BUCKET_NAME="matpatra-apps"
S3_OBJECT_KEY=$2
LOCAL_AAB_PATH="./app.aab"
SERVICE_ACCOUNT_FILE="/var/www/html/matpatra/android-uploader-446303-e8f35b10cc85.json"
PACKAGE_NAME=$1
RELEASE_NOTES="This is the latest release of our app with new features and bug fixes."
VERSION_NAME=$3
TRACK="production" # Change to 'beta', 'alpha', or 'internal' for other tracks

# Download AAB from S3
echo "Downloading AAB from S3..."
aws s3 cp "s3://${S3_BUCKET_NAME}/${S3_OBJECT_KEY}" "${LOCAL_AAB_PATH}"

if [ $? -ne 0 ]; then
  echo "Failed to download AAB from S3."
  exit 1
fi
echo "AAB downloaded successfully."

# Upload AAB and release via Google Play API
python3 <<EOF
import sys
import traceback
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# Configurable variables
SERVICE_ACCOUNT_FILE = "${SERVICE_ACCOUNT_FILE}"
PACKAGE_NAME = "${PACKAGE_NAME}"
LOCAL_AAB_PATH = "${LOCAL_AAB_PATH}"
RELEASE_NOTES = "${RELEASE_NOTES}"
TRACK = "${TRACK}"
VERSION_NAME = "${VERSION_NAME}"

try:
    print("Authenticating with Google Play API...")
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE,
        scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    service = build("androidpublisher", "v3", credentials=credentials)
    
    # Create an edit session
    print("Creating edit session...")
    edit_request = service.edits().insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit_request["id"]
    print(f"Edit session created: {edit_id}")
    
    # Upload AAB file
    print("Uploading AAB file...")
    media = MediaFileUpload(LOCAL_AAB_PATH, mimetype="application/octet-stream", resumable=True)
    upload_response = service.edits().bundles().upload(
        editId=edit_id,
        packageName=PACKAGE_NAME,
        media_body=media
    ).execute()
    version_code = upload_response["versionCode"]
    print(f"AAB uploaded successfully with version code: {version_code}")
    
    # Update release track with release notes
    print("Updating release track...")
    track_body = {
        "releases": [{
            "name": VERSION_NAME,
            "status": "completed",
            "versionCodes": [version_code],
            "releaseNotes": [{"language": "en-US", "text": RELEASE_NOTES}]
        }]
    }
    service.edits().tracks().update(
        editId=edit_id,
        packageName=PACKAGE_NAME,
        track=TRACK,
        body=track_body
    ).execute()
    print("Track updated successfully.")
    
    # Commit the edit
    print("Committing edit...")
    service.edits().commit(editId=edit_id, packageName=PACKAGE_NAME).execute()
    print("App successfully published to Google Play!")
except Exception as e:
    print("An error occurred during the publishing process:")
    traceback.print_exc()
    sys.exit(1)
EOF

# Check for successful execution
if [ $? -eq 0 ]; then
    echo "Deployment completed successfully."
else
    echo "Deployment failed."
    exit 1
fi
