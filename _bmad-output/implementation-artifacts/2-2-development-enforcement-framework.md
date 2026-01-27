# TAPIX Development Enforcement Framework

> **CRITICAL**: This framework creates BINDING CONSTRAINTS that AI models MUST follow. These are not suggestions - they are mandatory requirements enforced at multiple levels.

---

## 🎯 Purpose

Transforms project-context.md and UI architecture from optional documentation into ENFORCED CONSTRAINTS that AI models cannot bypass or ignore.

---

## 🔗 Binding Constraint System

### Level 1: Story Template Enforcement

**ALL story templates MUST include these mandatory sections:**

```yaml
# BINDING REQUIREMENTS (MANDATORY - CANNOT BE IGNORED)
binding_constraints:
  # MUST reference project-context.md sections
  project_context_requirements:
    - section: "Real-Time State Management"
      requirement: "Bloc MUST extend RealtimeBloc"
      enforcement: "Code review will reject any Bloc not extending RealtimeBloc"
    - section: "Money Calculations" 
      requirement: "ALL money values stored as INTEGER cents"
      enforcement: "Automated tests will fail if double/float used for money"
    - section: "Currency Settings"
      requirement: "ALL money displays use CurrencyService"
      enforcement: "UI tests will verify CurrencyService usage"
  
  # MUST reference UI architecture specification
  ui_architecture_requirements:
    - section: "Screen Structure Pattern"
      requirement: "EVERY screen follows Scaffold + BlocBuilder pattern"
      enforcement: "Widget tests will verify structure compliance"
    - section: "Navigation Architecture"
      requirement: "ALL navigation uses GoRouter patterns"
      enforcement: "Integration tests will verify navigation"
```

### Level 2: AI Model Prompt Enforcement

**ALL AI model prompts MUST include:**

```markdown
## MANDATORY CONSTRAINTS (CANNOT BE IGNORED)

You MUST follow these binding requirements from project-context.md:

1. RealtimeBloc Pattern: EVERY Bloc extends RealtimeBloc - NO EXCEPTIONS
2. Integer Cents: ALL money stored as integers - NO floats/doubles  
3. CurrencyService: ALL money displays use CurrencyService - NO hardcoded symbols
4. Localization: ALL text uses .tr() - NO hardcoded strings
5. Responsive Design: MUST work mobile/tablet/desktop - NO platform-specific code

You MUST follow UI architecture specification:
- Screen placement as defined in hierarchy
- GoRouter navigation patterns exactly as specified
- Responsive breakpoint patterns
- Scaffold structure for every screen

VIOLATION OF THESE CONSTRAINTS IS NOT ACCEPTABLE.
```

### Level 3: Code Review Enforcement

**Automated validation checks:**

```dart
// Automated compliance checker
class ComplianceValidator {
  // Check RealtimeBloc usage
  bool validateRealtimeBloc(String blocCode) {
    return blocCode.contains('extends RealtimeBloc') && 
           blocCode.contains('dataStream') &&
           blocCode.contains('registerEventHandlers');
  }
  
  // Check CurrencyService usage  
  bool validateCurrencyService(String widgetCode) {
    return widgetCode.contains('CurrencyService') ||
           widgetCode.contains('currencyService.format');
  }
  
  // Check localization
  bool validateLocalization(String uiCode) {
    return !RegExp(r'["\'][^"\']*\s[^"\']*["\']').hasMatch(uiCode) ||
           uiCode.contains('.tr()');
  }
}
```

---

## 🚫 Enforcement Mechanisms

### Mechanism 1: Story Acceptance Criteria

**EVERY story MUST include these AC items:**

```yaml
acceptance_criteria:
  - AC-001: "Bloc extends RealtimeBloc with proper stream subscription"
  - AC-002: "All text localized using .tr() method"  
  - AC-003: "Money values use integer cents storage"
  - AC-004: "Money displays use CurrencyService.format()"
  - AC-005: "Screen follows responsive design pattern"
  - AC-006: "Navigation uses GoRouter as specified"
  - AC-007: "UI uses semantic colors from theme extensions"
  - AC-008: "All components database-wired (no standalone)"
```

### Mechanism 2: Development Workflow Gates

**Stories cannot progress without compliance:**

```yaml
workflow_gates:
  ready_for_dev:
    - check: "Story references project-context.md sections"
    - check: "Story includes binding_constraints section"
    
  in_progress:  
    - check: "Developer confirms reading project-context.md"
    - check: "Developer confirms reading UI architecture"
    
  review:
    - check: "Automated compliance check passes"
    - check: "Manual code review verifies constraints"
    
  done:
    - check: "All tests pass with 100% compliance"
    - check: "No project-context.md violations"
```

### Mechanism 3: AI Model Constraint Injection

**Force AI models to load and follow constraints:**

```markdown
## SYSTEM PROMPT ENFORCEMENT

Before ANY code generation, you MUST:

1. Load project-context.md and treat as BINDING LAW
2. Load UI architecture specification and treat as MANDATORY
3. Reference specific sections in your implementation
4. Explain how each constraint is satisfied

FAILURE TO FOLLOW THESE STEPS IS NOT ACCEPTABLE.

Example response format:
"I have loaded project-context.md section X and implemented Y accordingly.
I have loaded UI architecture section Z and followed pattern A exactly."
```

---

## 🔧 Implementation Tools

### Tool 1: Compliance Checker Script

```bash
#!/bin/bash
# compliance-check.sh - Validates code against project-context.md

echo "🔍 Checking compliance with project-context.md..."

# Check RealtimeBloc usage
if ! grep -r "extends RealtimeBloc" lib/features/; then
  echo "❌ VIOLATION: Blocs must extend RealtimeBloc"
  exit 1
fi

# Check CurrencyService usage  
if grep -r "\$\|€\|£" lib/features/ | grep -v "CurrencyService"; then
  echo "❌ VIOLATION: Hardcoded currency symbols found"
  exit 1
fi

# Check localization
if grep -r "'[A-Z][a-z].*'" lib/features/ | grep -v "\.tr()"; then
  echo "❌ VIOLATION: Unlocalized strings found"
  exit 1
fi

echo "✅ All compliance checks passed"
```

### Tool 2: Story Template Generator

```yaml
# Enhanced story template with enforcement
story_template:
  mandatory_sections:
    - binding_constraints: "References to project-context.md sections"
    - architecture_compliance: "UI architecture patterns to follow"
    - enforcement_checks: "Automated validation requirements"
    
  preconditions:
    - "Developer has read project-context.md"
    - "Developer has read UI architecture specification"
    - "Developer understands binding constraints"
```

---

## 📋 Enforcement Checklist

**Before ANY story implementation:**

- [ ] Story includes binding_constraints section
- [ ] Story references specific project-context.md sections  
- [ ] Story references specific UI architecture sections
- [ ] AC items include compliance requirements
- [ ] Developer confirms reading all binding documents

**During implementation:**

- [ ] Code follows RealtimeBloc pattern exactly
- [ ] Money uses integer cents everywhere
- [ ] CurrencyService used for all money displays
- [ ] All text localized with .tr()
- [ ] Responsive design implemented
- [ ] GoRouter navigation followed

**After implementation:**

- [ ] Automated compliance check passes
- [ ] Manual code review verifies constraints
- [ ] Tests validate compliance
- [ ] No project-context.md violations

---

## 🎯 Success Metrics

**Compliance is measured by:**

1. **100% RealtimeBloc adoption** - Zero exceptions
2. **0 hardcoded currency symbols** - All use CurrencyService  
3. **100% localization coverage** - No hardcoded strings
4. **100% responsive design** - Works on all screen sizes
5. **100% database integration** - No standalone components

---

**Last Updated**: 2026-01-26  
**Version**: 1.0.0  
**Status**: ENFORCEMENT ACTIVE - These constraints are BINDING
