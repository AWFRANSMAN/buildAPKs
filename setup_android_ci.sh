#!/bin/bash
# ----------------------------------------
# GitHub CI/CD Setup for Android APK Builds
# ----------------------------------------

if [ -z "$1" ]; then
  echo "Usage: ./setup_android_ci.sh <github-repo-url>"
  exit 1
fi

REPO_URL=$1

echo "=== 1. Initializing Git and pushing to GitHub ==="
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin $REPO_URL
git push -u origin main

echo "=== 2. Creating GitHub Actions workflow ==="
mkdir -p .github/workflows
cat <<'EOF' > .github/workflows/android-build.yml
name: Build & Release Signed APK

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up JDK 17
        uses: actions/setup-java@v3
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Grant execute permission for gradlew
        run: chmod +x gradlew

      - name: Decode and Prepare Signing Key
        run: |
          echo "${SIGNING_KEYSTORE}" | base64 --decode > my-release-key.jks
        env:
          SIGNING_KEYSTORE: ${{ secrets.SIGNING_KEYSTORE }}

      - name: Build Signed Release APK
        run: ./gradlew assembleRelease \
          -Pandroid.injected.signing.store.file=my-release-key.jks \
          -Pandroid.injected.signing.store.password=${{ secrets.KEYSTORE_PASSWORD }} \
          -Pandroid.injected.signing.key.alias=${{ secrets.KEY_ALIAS }} \
          -Pandroid.injected.signing.key.password=${{ secrets.KEY_PASSWORD }}

      - name: Upload APK as Artifact
        uses: actions/upload-artifact@v3
        with:
          name: MyApp-APK
          path: app/build/outputs/apk/release/app-release.apk

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: app/build/outputs/apk/release/app-release.apk
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

git add .github/workflows/android-build.yml
git commit -m "Add GitHub Actions for signed APK build"
git push origin main

echo "=== 3. Updating Gradle for Auto Versioning ==="
# Append logic to app/build.gradle
APP_GRADLE="app/build.gradle"
if grep -q "versionName" "$APP_GRADLE"; then
  echo "Modifying versionName to use Git tags..."
  sed -i.bak '/versionName/c\        versionName "git describe --tags".execute().text.trim()' $APP_GRADLE
else
  echo "Please manually ensure versionName uses git tags in build.gradle"
fi

echo "=== 4. Creating First Release Tag ==="
git tag v1.0.0
git push origin v1.0.0

echo "✅ Setup complete!"
echo "Next steps:"
echo "1. Go to GitHub -> Repo -> Settings -> Secrets and variables -> Actions"
echo "   Add these secrets:"
echo "   - SIGNING_KEYSTORE (base64 of your .jks)"
echo "   - KEYSTORE_PASSWORD"
echo "   - KEY_ALIAS"
echo "   - KEY_PASSWORD"
echo ""
echo "2. After adding secrets, the workflow will sign your APK and upload it to GitHub Releases."
echo ""
echo "3. For new versions, just run:"
echo "   git tag v1.0.1 && git push origin v1.0.1"