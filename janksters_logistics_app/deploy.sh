#!/bin/bash

# exit immediately if a command fails
set -e

echo "Building Flutter web..."
cd frontend
flutter build web

echo "Copying build files to backend..."
# make sure the backend/build folder exists
mkdir -p ../backend/build
# remove old web build to prevent stale files
rm -rf ../backend/build/web
cp -r build/web ../backend/build/web

echo "Installing backend dependencies..."
cd ../backend
npm install

echo "Deploy script finished successfully!"
