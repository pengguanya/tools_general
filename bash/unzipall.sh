#!/bin/bash

# Function to show usage
usage() {
    echo "Usage: $0 [-n] <source_zip> <destination_path>"
    echo "  -n: Extract contents directly into the destination basename"
    exit 1
}

# --- 1. Argument Parsing ---
USE_BASENAME=false

if [[ "$1" == "-n" ]]; then
    USE_BASENAME=true
    shift
fi

if [ "$#" -ne 2 ]; then
    usage
fi

SRC_ZIP=$(realpath "$1")
DEST_PATH="$2"

if [ ! -f "$SRC_ZIP" ]; then
    echo "Error: Source file '$SRC_ZIP' not found."
    exit 1
fi

# --- 2. Determine Output Directory ---
ZIP_FILENAME=$(basename "$SRC_ZIP" .zip)

if [ "$USE_BASENAME" = true ]; then
    FINAL_DIR="$DEST_PATH"
else
    FINAL_DIR="$DEST_PATH/$ZIP_FILENAME"
fi

mkdir -p "$FINAL_DIR"
echo "Extracting main zip to: $FINAL_DIR"

# Unzip the main file
unzip -q -o "$SRC_ZIP" -d "$FINAL_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to unzip primary file."
    exit 1
fi

# Switch to the target directory
cd "$FINAL_DIR" || exit

# --- 3. Recursive Unzip Loop ---
echo "Starting recursive scan..."

while true; do
    # Flag to track if we did any work in this pass
    processed_files=false
    
    # Find all .zip files. 
    # Use 'find' with 'read' to handle spaces in filenames correctly.
    while IFS= read -r -d '' zip_file; do
        
        # Get absolute path to ensure unzip doesn't get confused
        abs_zip_path=$(realpath "$zip_file")
        
        # Define the target directory (remove .zip extension)
        # We perform string manipulation on the relative path "./sub/file.zip"
        # to ensure the structure is maintained locally
        local_dir="${zip_file%.zip}"
        
        # create the directory
        mkdir -p "$local_dir"
        
        # Extract
        # -q: quiet
        # -o: overwrite (essential for recursion without prompts)
        unzip -q -o "$abs_zip_path" -d "$local_dir"
        
        # CHECK EXIT CODE explicitly before deleting
        if [ $? -eq 0 ]; then
            # SUCCESS:
            # 1. Fix Permissions (Crucial step for nested zips)
            # We give the owner write permissions to everything just extracted
            chmod -R u+rw "$local_dir"
            
            # 2. Remove the original zip file
            rm "$abs_zip_path"
            
            processed_files=true
        else
            # FAILURE:
            echo "Error: Could not unzip $zip_file. Leaving it alone."
            # We assume empty folder might exist due to mkdir, remove it if empty
            rmdir "$local_dir" 2>/dev/null
        fi

    done < <(find . -type f -name "*.zip" -print0)

    # Break the loop if no zip files were processed in this iteration
    if [ "$processed_files" = false ]; then
        break
    fi
done

echo "Success. All folders extracted recursively."
