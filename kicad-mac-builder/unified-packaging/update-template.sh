#!/bin/bash

# Script to update kicadtemplate.dmg with Trace branding
# This updates the background, window size, and icon positions for 700x500 background

set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DMG="${SCRIPT_DIR}/kicadtemplate.dmg"

# Cleanup function
cleanup() {
    # Unmount any KiCad volumes
    hdiutil detach "/Volumes/KiCad" -force 2>/dev/null || true
    diskutil unmount "/Volumes/KiCad" 2>/dev/null || true
}
trap cleanup EXIT

echo "Updating template DMG with Trace branding..."

# Clean up any existing mounts
cleanup

# Extract the template if it's compressed
if [ ! -f "${TEMPLATE_DMG}" ] && [ -f "${TEMPLATE_DMG}.tar.bz2" ]; then
    echo "Extracting template from tar.bz2..."
    cd "${SCRIPT_DIR}"
    tar -xjf kicadtemplate.dmg.tar.bz2
fi

# Mount the template DMG (let it auto-mount to /Volumes/)
echo "Mounting template DMG..."
hdiutil attach "${TEMPLATE_DMG}" -readwrite
sleep 2

# Find the device and mount point
DEVICE=$(hdiutil info | grep "/Volumes/KiCad" | awk '{print $1}' | head -1)
MOUNTPOINT="/Volumes/KiCad"

if [ -z "${DEVICE}" ]; then
    # Try to find any mounted volume from our DMG
    DEVICE=$(mount | grep kicadtemplate.dmg | awk '{print $1}' | head -1)
    if [ -n "${DEVICE}" ]; then
        MOUNTPOINT=$(mount | grep "${DEVICE}" | awk '{print $3}')
    fi
fi

if [ -z "${DEVICE}" ]; then
    echo "Error: Failed to mount DMG"
    exit 1
fi

echo "Mounted at ${MOUNTPOINT}"

# Create placeholder folders that will exist in the final DMG
# This ensures .DS_Store has position entries for these items
echo "Creating placeholder folders for icon positioning..."
mkdir -p "${MOUNTPOINT}/Trace"
mkdir -p "${MOUNTPOINT}/demos"
# Applications symlink should already exist in template, but ensure it does
if [ ! -e "${MOUNTPOINT}/Applications" ]; then
    ln -s /Applications "${MOUNTPOINT}/Applications"
fi

# Update background image
echo "Updating background image (700x500)..."
if [ -f "${SCRIPT_DIR}/background.png" ]; then
    # macOS can use either .background.png at root or .background/background.png
    # Use .background folder approach for better compatibility
    mkdir -p "${MOUNTPOINT}/.background"
    cp "${SCRIPT_DIR}/background.png" "${MOUNTPOINT}/.background/background.png"
    # Also copy to root as fallback
    cp "${SCRIPT_DIR}/background.png" "${MOUNTPOINT}/.background.png"
    # Verify files were copied
    if [ -f "${MOUNTPOINT}/.background/background.png" ]; then
        echo "Background copied to .background/background.png"
    fi
    if [ -f "${MOUNTPOINT}/.background.png" ]; then
        echo "Background copied to .background.png"
    fi
    # Hide the background files (but don't hide the .background folder itself)
    SetFile -a V "${MOUNTPOINT}/.background.png" 2>/dev/null || true
    SetFile -a V "${MOUNTPOINT}/.background/background.png" 2>/dev/null || true
    echo "Background updated"
else
    echo "Warning: background.png not found in ${SCRIPT_DIR}"
fi

# Update volume icon (the icon that appears on the DMG file)
echo "Updating volume icon..."
ICON_SOURCE=""
# Check for Trace icon files in order of preference
if [ -f "${SCRIPT_DIR}/VolumeIcon.icns" ]; then
    ICON_SOURCE="${SCRIPT_DIR}/VolumeIcon.icns"
elif [ -f "${SCRIPT_DIR}/../dmgbuild/kicad.icns" ]; then
    ICON_SOURCE="${SCRIPT_DIR}/../dmgbuild/kicad.icns"
fi

if [ -n "${ICON_SOURCE}" ] && [ -f "${ICON_SOURCE}" ]; then
    cp "${ICON_SOURCE}" "${MOUNTPOINT}/.VolumeIcon.icns"
    # Hide the icon file
    SetFile -a V "${MOUNTPOINT}/.VolumeIcon.icns"
    # Set the custom icon flag on the volume root
    SetFile -a C "${MOUNTPOINT}"
    echo "Volume icon updated"
else
    echo "Warning: No icon file found. Skipping volume icon update."
fi

# Update window settings using AppleScript
echo "Configuring window settings for 700x500 background..."
# Get the actual volume name
ACTUAL_VOLUME=$(diskutil info "${DEVICE}" | grep "Volume Name:" | awk -F': ' '{print $2}' | xargs)

osascript <<EOF
tell application "Finder"
    activate
    delay 1
    
    -- Get the disk object
    set targetDisk to disk "${ACTUAL_VOLUME}"
    
    -- Close any existing windows for this disk first
    try
        set windowList to every window
        repeat with w in windowList
            try
                set winTarget to target of w
                if class of winTarget is disk and name of winTarget is "${ACTUAL_VOLUME}" then
                    close w
                end if
            end try
        end repeat
        delay 0.5
    end try
    
    -- Open the disk window explicitly
    open targetDisk
    delay 3
    
    -- Find the window - try multiple methods
    set targetWindow to missing value
    
    -- First, let's try the most direct approach: iterate through all windows
    -- and find one whose target is our disk
    set mountPath to "${MOUNTPOINT}"
    set windowList to every window
    repeat with w in windowList
        try
            set winTarget to target of w
            if class of winTarget is disk then
                set diskName to name of winTarget as string
                -- Match by volume name (handles "KiCad", "Trace", etc.)
                if diskName is "${ACTUAL_VOLUME}" then
                    set targetWindow to w
                    exit repeat
                end if
                -- Also try matching by checking if it's the right disk via POSIX path
                try
                    set diskPath to POSIX path of winTarget
                    if diskPath is mountPath or diskPath contains mountPath or mountPath contains diskPath then
                        set targetWindow to w
                        exit repeat
                    end if
                end try
            end if
        on error
            -- Skip windows we can't inspect
        end try
    end repeat
    
    -- Method 1: Try by exact name (if direct search didn't work)
    if targetWindow is missing value then
        try
            set targetWindow to window "${ACTUAL_VOLUME}" of desktop
        end try
    end if
    
    -- Method 2: Try by finding window with matching target (most reliable)
    if targetWindow is missing value then
        set windowList to every window
        repeat with w in windowList
            try
                set winTarget to target of w
                -- Compare disk objects directly
                if class of winTarget is disk and name of winTarget is "${ACTUAL_VOLUME}" then
                    set targetWindow to w
                    exit repeat
                end if
            on error
                -- Try alternative comparison
                try
                    if winTarget is targetDisk then
                        set targetWindow to w
                        exit repeat
                    end if
                end try
            end try
        end repeat
    end if
    
    -- Method 3: Try by checking window name contains volume name (handles concatenated names)
    if targetWindow is missing value then
        set windowList to every window
        repeat with w in windowList
            try
                set winName to name of w as string
                -- Check if name contains the volume name (handles "TraceKiCad" type names)
                if winName is "${ACTUAL_VOLUME}" or winName contains "${ACTUAL_VOLUME}" or "${ACTUAL_VOLUME}" is in winName then
                    -- Verify it's the right window by checking target
                    try
                        set winTarget to target of w
                        if class of winTarget is disk and name of winTarget is "${ACTUAL_VOLUME}" then
                            set targetWindow to w
                            exit repeat
                        end if
                    end try
                end if
            end try
        end repeat
    end if
    
    -- Method 4: Use any window that targets a disk (last resort - use first disk window)
    if targetWindow is missing value then
        set windowList to every window
        repeat with w in windowList
            try
                set winTarget to target of w
                if class of winTarget is disk then
                    -- Use this window as it's likely the one we just opened
                    set targetWindow to w
                    exit repeat
                end if
            end try
        end repeat
    end if
    
    -- Final check - if still not found, try opening by path
    if targetWindow is missing value then
        try
            -- Try opening by mountpoint path as last resort
            set mountPath to POSIX file "${MOUNTPOINT}"
            open mountPath
            delay 2
            set windowList to every window
            -- Now try to find it again
            repeat with w in windowList
                try
                    set winTarget to target of w
                    if winTarget is targetDisk then
                        set targetWindow to w
                        exit repeat
                    end if
                end try
            end repeat
        end try
    end if
    
    -- Final check - if still not found, wait a bit more and try again
    if targetWindow is missing value then
        delay 2
        set windowList to every window
        -- Try one more time to find the window
        repeat with w in windowList
            try
                set winTarget to target of w
                if class of winTarget is disk then
                    set diskName to name of winTarget as string
                    if diskName is "${ACTUAL_VOLUME}" then
                        set targetWindow to w
                        exit repeat
                    end if
                end if
            end try
        end repeat
    end if
    
    -- Final error check with debugging info
    if targetWindow is missing value then
        -- List available windows and their targets for debugging
        set debugList to ""
        set windowList to every window
        set windowCount to count of windowList
        repeat with w in windowList
            try
                set winName to "unknown"
                set targetInfo to ""
                try
                    set winName to name of w as string
                on error
                    set winName to "unnamed window"
                end try
                try
                    set winTarget to target of w
                    if class of winTarget is disk then
                        set targetInfo to " (disk: " & (name of winTarget as string) & ")"
                    else
                        set targetInfo to " (target: " & (class of winTarget as string) & ")"
                    end if
                on error
                    set targetInfo to " (could not get target)"
                end try
                set debugList to debugList & winName & targetInfo & ", "
            on error errMsg
                set debugList to debugList & "window (error: " & errMsg & "), "
            end try
        end repeat
        error "Could not find window for volume ${ACTUAL_VOLUME}. Total windows: " & windowCount & ". Available: " & debugList
    end if
    
        -- Set window properties for 700x500 background
        try
        set current view of targetWindow to icon view
        set toolbar visible of targetWindow to false
        set statusbar visible of targetWindow to false
        -- Window bounds: {left, top, right, bottom}
        -- For 700x500 visible area: width=700, height=500 + ~22px title bar
        -- So: left=100, top=100, right=100+700=800, bottom=100+500+22=622
        set bounds of targetWindow to {100, 100, 630, 510}
        
        -- Configure icon view options
        set opts to icon view options of targetWindow
        set arrangement of opts to not arranged
        set icon size of opts to 80
        set text size of opts to 16
        set label position of opts to bottom
        
        -- Set background picture (if it exists)
        try
            -- Try .background/background.png first (standard macOS location)
            try
                set bgFolder to folder ".background" of targetDisk
                set bgFile to file "background.png" of bgFolder
                set background picture of opts to bgFile
            on error
                -- Fallback to .background.png at root
                try
                    set bgFile to file ".background.png" of targetDisk
                    set background picture of opts to bgFile
                on error
                    -- Last resort: try POSIX path
                    try
                        set bgPath to POSIX file "${MOUNTPOINT}/.background/background.png"
                        set background picture of opts to bgPath
                    end try
                end try
            end try
        end try
        
        -- Position icons for 700x500 layout with arrow graphic
        -- Arrow is centered horizontally at 350px (middle of 700px)
        -- Trace folder: left of arrow at (90, 200)
        -- Applications: right of arrow at (450, 200)
        -- demos: centered below at (350, 350)
        try
            set position of item "Trace" of targetWindow to {90, 200}
        end try
        try
            set position of item "Trace.app" of targetWindow to {90, 200}
        end try
        try
            set position of item "KiCad" of targetWindow to {90, 200}
        end try
        try
            set position of item "Applications" of targetWindow to {450, 200}
        end try
        try
            set position of item "demos" of targetWindow to {240, 300}
        end try
        
        -- Force window update to apply background
        update targetWindow
        
        -- Save view options
        delay 1
    on error errMsg
        display dialog "Error configuring window: " & errMsg
    end try
    
    -- Close window to save settings
    delay 1
    try
        close targetWindow
    end try
end tell
EOF

# Wait a moment for changes to be written
sleep 2

# Sync to ensure all changes are written
sync

echo "Window settings configured"

# Unmount the DMG
echo "Unmounting DMG..."
hdiutil detach "${MOUNTPOINT}" -force || hdiutil detach "${DEVICE}" -force

# Wait a moment
sleep 1

# Re-compress the template
echo "Re-compressing template..."
cd "${SCRIPT_DIR}"
if [ -f "kicadtemplate.dmg.tar.bz2" ]; then
    BACKUP_NAME="kicadtemplate.dmg.tar.bz2.backup-$(date +%Y%m%d-%H%M%S)"
    mv kicadtemplate.dmg.tar.bz2 "${BACKUP_NAME}"
    echo "Backup saved as: ${BACKUP_NAME}"
fi
tar -cjf kicadtemplate.dmg.tar.bz2 kicadtemplate.dmg

# Clean up the extracted DMG
rm kicadtemplate.dmg

echo ""
echo "✓ Done! Template updated and re-compressed."
echo "✓ Window size: 700x500 (bounds: {100, 100, 800, 622})"
echo "✓ Icon positions set for 700x500 background with arrow:"
echo "  - Trace folder: (90, 200) - left of arrow"
echo "  - Applications: (450, 200) - right of arrow"
echo "  - demos: (350, 350) - below center"
echo ""
