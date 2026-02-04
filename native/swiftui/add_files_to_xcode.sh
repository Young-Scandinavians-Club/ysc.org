#!/bin/bash
# This script adds APIKeyManager.swift and APIKeyInputView.swift to the Xcode project
# Run this from the native/swiftui directory

# Generate unique IDs (following Xcode's pattern)
API_KEY_MANAGER_REF=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | sed 's/\(.\{12\}\)\(.\{12\}\)/\1\2/')
API_KEY_INPUT_REF=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | sed 's/\(.\{12\}\)\(.\{12\}\)/\1\2/')
API_KEY_MANAGER_BUILD=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | sed 's/\(.\{12\}\)\(.\{12\}\)/\1\2/')
API_KEY_INPUT_BUILD=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24 | sed 's/\(.\{12\}\)\(.\{12\}\)/\1\2/')

echo "Generated IDs:"
echo "APIKeyManager fileRef: $API_KEY_MANAGER_REF"
echo "APIKeyInputView fileRef: $API_KEY_INPUT_REF"
echo ""
echo "Please add these files manually in Xcode:"
echo "1. Open Ysc.xcodeproj in Xcode"
echo "2. Right-click on the 'Ysc' group in the Project Navigator"
echo "3. Select 'Add Files to Ysc...'"
echo "4. Select APIKeyManager.swift and APIKeyInputView.swift"
echo "5. Make sure 'Copy items if needed' is UNCHECKED"
echo "6. Make sure 'Add to targets: Ysc' is CHECKED"
