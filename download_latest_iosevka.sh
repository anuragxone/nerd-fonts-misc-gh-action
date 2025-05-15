#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status.

# --- Configuration ---
GITHUB_REPO="be5invis/iosevka"
# We'll look for the "Super TTC" package. You can change this regex if you prefer another.
# Examples: "ttc-iosevka-.*\.zip", "webfont-iosevka-.*\.zip"
# This regex specifically targets files like "super-ttc-iosevka-VERSION.zip"
ASSET_NAME_PATTERN="PkgTTF-IosevkaTermCurly-.*\.zip"
DOWNLOAD_DIR="iosevka-term-curly" # Directory to download and extract into

# --- Helper Functions ---
check_deps() {
    for cmd in curl jq unzip; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' not found."
            echo "Please install it first."
            exit 1
        fi
    done
}

# --- Main Logic ---
echo "Fetching latest Iosevka release information..."

# Get the latest release data from GitHub API
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
RELEASE_INFO_JSON=$(curl -fsSL "$API_URL")

if [[ -z "$RELEASE_INFO_JSON" ]]; then
    echo "Error: Could not fetch release information. Check your internet connection or the repository URL."
    exit 1
fi

if echo "$RELEASE_INFO_JSON" | jq -e '.message == "Not Found"' > /dev/null; then
    echo "Error: Repository or releases not found at $API_URL"
    exit 1
fi

if echo "$RELEASE_INFO_JSON" | jq -e '(.message | test("API rate limit exceeded"))' > /dev/null; then
    echo "Error: GitHub API rate limit exceeded. Please try again later or use an authenticated request."
    exit 1
fi


LATEST_TAG=$(echo "$RELEASE_INFO_JSON" | jq -r '.tag_name')
if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
    echo "Error: Could not determine the latest release tag."
    echo "API Response: $RELEASE_INFO_JSON"
    exit 1
fi
echo "Latest release tag: $LATEST_TAG"

# Find the download URL for the desired asset
ASSET_DOWNLOAD_URL=$(echo "$RELEASE_INFO_JSON" | jq -r --arg pattern "$ASSET_NAME_PATTERN" '.assets[] | select(.name | test($pattern; "i")) | .browser_download_url')
# The "i" flag in test($pattern; "i") makes the regex case-insensitive, though unlikely needed here.

if [[ -z "$ASSET_DOWNLOAD_URL" || "$ASSET_DOWNLOAD_URL" == "null" ]]; then
    echo "Error: Could not find an asset matching the pattern '$ASSET_NAME_PATTERN' in release $LATEST_TAG."
    echo "Available assets:"
    echo "$RELEASE_INFO_JSON" | jq -r '.assets[].name'
    exit 1
fi

FILENAME=$(basename "$ASSET_DOWNLOAD_URL")
echo "Found asset: $FILENAME"
echo "Download URL: $ASSET_DOWNLOAD_URL"

# Create download directory if it doesn't exist
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo "Downloading $FILENAME..."
# curl -LJO will use the server-provided filename and follow redirects
# curl -f will fail silently on server errors (HTTP 4xx or 5xx)
if curl -fSLJO "$ASSET_DOWNLOAD_URL"; then
    echo "Download successful: $FILENAME"
else
    echo "Error: Download failed for $FILENAME."
    # Clean up potentially partially downloaded file if curl didn't use -O and we know the name
    # If using -J -O, curl usually names it correctly or fails to create it.
    exit 1
fi

# Extract the downloaded archive (assuming it's a zip)
if [[ "$FILENAME" == *.zip ]]; then
    echo "Extracting $FILENAME..."
    unzip -q "$FILENAME" -d "IosevkaTermCurly" # -q for quiet
    echo "Extraction complete. Fonts are in the current directory: $(pwd)"
    # Optional: Remove the zip file after extraction
    # read -p "Remove downloaded archive $FILENAME? (y/N): " confirm_delete
    # if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
    #     rm "$FILENAME"
    #     echo "$FILENAME removed."
    # fi
elif [[ "$FILENAME" == *.tar.gz || "$FILENAME" == *.tgz ]]; then
    echo "Extracting $FILENAME..."
    tar -xzf "$FILENAME"
    echo "Extraction complete. Fonts are in the current directory: $(pwd)"
elif [[ "$FILENAME" == *.tar.xz ]]; then
    echo "Extracting $FILENAME..."
    tar -xJf "$FILENAME"
    echo "Extraction complete. Fonts are in the current directory: $(pwd)"
else
    echo "Downloaded file is not a known archive type (.zip, .tar.gz, .tar.xz): $FILENAME"
    echo "Skipping extraction."
fi

echo ""
echo "Iosevka font version $LATEST_TAG downloaded and extracted to: $(pwd)"
echo "To install the fonts:"
echo "  Linux: Copy .ttc or .ttf files to ~/.local/share/fonts/ or /usr/local/share/fonts/ and run 'fc-cache -fv'"
echo "  macOS: Open Font Book and drag the .ttc or .ttf files into it, or copy them to ~/Library/Fonts/"
echo "  Windows: Right-click the .ttc or .ttf files and select 'Install'."

cd .. # Go back to original directory
exit 0