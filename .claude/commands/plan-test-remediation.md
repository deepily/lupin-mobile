---
description: Run post-change verification for Lupin Mobile project
allowed-tools: Bash(.*), Read, Write, Edit, Grep, Glob
arguments:
  - name: baseline_report
    description: Path to baseline report (auto-detects if not provided)
    required: false
  - name: scope
    description: Remediation scope (ANALYSIS_ONLY recommended for docs repo)
    required: false
    default: ANALYSIS_ONLY
---

# Post-Change Remediation for Lupin Mobile

**Purpose**: Verify documentation structure after changes
**Project**: Lupin Mobile
**Note**: ANALYSIS_ONLY scope recommended (documentation repo doesn't need code fixes)

**Version**: 1.0

---

## Project Configuration

**Identity**:
- **Prefix**: `[LUPIN-MOBILE]`
- **Project Name**: Lupin Mobile
- **Working Directory**: .

**Arguments**:
- **Baseline Report**: ${1:-auto}
- **Remediation Scope**: ${2:-ANALYSIS_ONLY}

**Baseline Auto-Detection**:
- **Directory**: tests/results/reports
- **Pattern**: *baseline-test-report.md
- **Sort**: Most recent timestamp

**Test Configuration** (same as baseline):
- **Test Types**: smoke (documentation validation)
- **Logs Directory**: tests/results/logs
- **Reports Directory**: tests/results/reports

---

## Instructions to Claude

**On every invocation of this command:**

1. **Must use the following project-specific configuration**:
   - **[SHORT_PROJECT_PREFIX]**: `[LUPIN-MOBILE]`
   - **Project Name**: Lupin Mobile
   - **Working Directory**: .
   - **Arguments**:
     - Baseline Report: ${1:-auto}
     - Remediation Scope: ${2:-ANALYSIS_ONLY}
   - **Baseline Auto-Detection**:
     - Directory: tests/results/reports
     - Pattern: *baseline-test-report.md
     - Sort: Most recent timestamp
   - **Test Configuration**:
     - Test Types: smoke (documentation validation)
     - Logs Directory: tests/results/logs
     - Reports Directory: tests/results/reports
   - Never proceed without these parameters

2. **Must read the canonical workflow document**:
   - Location: planning-is-prompting → workflow/testing-remediation.md
   - This is the only authoritative source for all remediation steps
   - Never proceed without reading this document in full

3. **Must execute the complete remediation workflow**:
   - Execute all steps exactly as described in the canonical workflow document
   - Never skip any steps (including notifications or comparison analysis)
   - Never substitute a shortened or summarized version
   - Follow the workflow exactly as documented using the configuration parameters from instruction 1
   - For this documentation project, ANALYSIS_ONLY scope is recommended (generates comparison report, no code fixes needed)

---

**This wrapper demonstrates remediation for documentation-focused projects.**
