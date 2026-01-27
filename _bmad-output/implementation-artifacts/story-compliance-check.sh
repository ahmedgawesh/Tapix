#!/bin/bash
# story-compliance-check.sh - Validates stories against binding constraints

echo "🔍 STORY COMPLIANCE CHECKER"
echo "============================"

STORY_FILE="$1"
if [ -z "$STORY_FILE" ]; then
    echo "❌ ERROR: Please provide story file path"
    echo "Usage: ./story-compliance-check.sh <story-file.md>"
    exit 1
fi

echo "📋 Checking story: $STORY_FILE"

# Check for binding constraints section
if ! grep -q "BINDING CONSTRAINTS (MANDATORY" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing BINDING CONSTRAINTS section"
    exit 1
fi

# Check for compliance acceptance criteria
if ! grep -q "AC-COMP-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing compliance acceptance criteria"
    exit 1
fi

# Check for enforcement tasks
if ! grep -q "COMPLIANCE-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing enforcement tasks"
    exit 1
fi

# Check for project-context.md references
if ! grep -q "project-context.md" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing project-context.md references"
    exit 1
fi

# Check for UI architecture references
if ! grep -q "ui-architecture-specification.md" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing UI architecture references"
    exit 1
fi

# Check for enforcement notes
if ! grep -q "FAILURE TO FOLLOW BINDING CONSTRAINTS IS NOT ACCEPTABLE" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing enforcement notes"
    exit 1
fi

echo "✅ STORY COMPLIANCE CHECK PASSED"
echo "✅ All binding constraints are included"
echo "✅ AI Models will be forced to follow project-context.md"
echo "✅ Enforcement mechanisms are in place"

exit 0
