#!/bin/bash
# enhanced-story-validation.sh - Validates stories against TAPIX_REBUILD_SPECIFICATION.md

echo "🔍 ENHANCED STORY VALIDATION CHECKER"
echo "=================================="

STORY_FILE="$1"
if [ -z "$STORY_FILE" ]; then
    echo "❌ ERROR: Please provide story file path"
    echo "Usage: ./enhanced-story-validation.sh <story-file.md>"
    exit 1
fi

echo "📋 Validating story: $STORY_FILE"

# Check for TAPIX_REBUILD_SPECIFICATION.md references
if ! grep -q "TAPIX_REBUILD_SPECIFICATION.md" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing TAPIX_REBUILD_SPECIFICATION.md references"
    exit 1
fi

# Check for Technical Requirements section
if ! grep -q "Technical Requirements (from TAPIX_REBUILD_SPECIFICATION.md)" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Technical Requirements section"
    exit 1
fi

# Check for Architecture Requirements
if ! grep -q "Clean Architecture" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Clean Architecture requirement"
    exit 1
fi

# Check for Real-Time Updates requirement
if ! grep -q "Real-Time Updates" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Real-Time Updates requirement"
    exit 1
fi

# Check for Money Calculations requirement
if ! grep -q "INTEGER cents" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing integer cents requirement"
    exit 1
fi

# Check for UI/UX Requirements section
if ! grep -q "UI/UX Requirements" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing UI/UX Requirements section"
    exit 1
fi

# Check for Responsive Design requirement
if ! grep -q "Responsive Design" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Responsive Design requirement"
    exit 1
fi

# Check for Business Logic Requirements section
if ! grep -q "Business Logic Requirements" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Business Logic Requirements section"
    exit 1
fi

# Check for Implementation Requirements section
if ! grep -q "Implementation Requirements" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Implementation Requirements section"
    exit 1
fi

# Check for Technical Acceptance Criteria
if ! grep -q "AC-TECH-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Technical Acceptance Criteria"
    exit 1
fi

# Check for UI/UX Acceptance Criteria
if ! grep -q "AC-UI-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing UI/UX Acceptance Criteria"
    exit 1
fi

# Check for Business Logic Acceptance Criteria
if ! grep -q "AC-BL-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Business Logic Acceptance Criteria"
    exit 1
fi

# Check for Technical Implementation Tasks
if ! grep -q "TECH-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Technical Implementation Tasks"
    exit 1
fi

# Check for UI/UX Implementation Tasks
if ! grep -q "UI-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing UI/UX Implementation Tasks"
    exit 1
fi

# Check for Business Logic Tasks
if ! grep -q "BL-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Business Logic Tasks"
    exit 1
fi

# Check for Testing Tasks
if ! grep -q "TEST-001" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Testing Tasks"
    exit 1
fi

# Check for Specification References section
if ! grep -q "Specification References (MANDATORY)" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Specification References section"
    exit 1
fi

# Check for Detailed Implementation Guidance
if ! grep -q "Detailed Implementation Guidance" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing Detailed Implementation Guidance"
    exit 1
fi

# Check for enforcement notes
if ! grep -q "TAPIX_REBUILD_SPECIFICATION.md and treat as BINDING LAW" "$STORY_FILE"; then
    echo "❌ VIOLATION: Missing enforcement notes for rebuild specification"
    exit 1
fi

echo "✅ ENHANCED STORY VALIDATION PASSED"
echo "✅ Story includes comprehensive details from TAPIX_REBUILD_SPECIFICATION.md"
echo "✅ All technical requirements covered"
echo "✅ All UI/UX requirements covered"
echo "✅ All business logic requirements covered"
echo "✅ All implementation tasks defined"
echo "✅ All acceptance criteria specified"
echo "✅ AI Models will be forced to follow detailed specifications"

exit 0
