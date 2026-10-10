---
description: Run baseline test collection for Lupin Mobile project
allowed-tools: Bash(.*), Read, Write, Edit
---

# Baseline Testing for Lupin Mobile

**Purpose**: Establish baseline before workflow/documentation changes
**Project**: Lupin Mobile
**Note**: This is a documentation-only project - tests validate document structure and links
**Version**: 1.0

---

## Project Configuration

**Identity**:
- **Prefix**: [LUPIN-MOBILE]
- **Project Name**: Lupin Mobile
- **Working Directory**: .

**Paths**:
- **Logs Directory**: tests/results/logs
- **Reports Directory**: tests/results/reports

**Test Types**: smoke (documentation validation only)

**Test Scripts**:
- **Smoke**: Simple validation script (validates docs exist and are readable)

**Health Checks**: None required (no server/service dependencies)

**Environment**: No special environment variables needed

---

## Instructions to Claude

**On every invocation of this command:**

1. **MUST use the following project-specific configuration**:
   - **[SHORT_PROJECT_PREFIX]**: [LUPIN-MOBILE]
   - **Project Name**: Lupin Mobile
   - **Working Directory**: .
   - **Paths**:
     - Logs Directory: tests/results/logs
     - Reports Directory: tests/results/reports
   - **Test Types**: smoke (documentation validation only)
   - **Test Scripts**: Simple validation script (validates docs exist and are readable)
   - **Health Checks**: None required (no server/service dependencies)
   - **Environment**: No special environment variables needed
   - Do NOT proceed without these parameters

2. **MUST read the canonical workflow document**:
   - Location: planning-is-prompting → workflow/testing-baseline.md
   - This is the ONLY authoritative source for ALL baseline testing steps
   - Do NOT proceed without reading this document in full

3. **MUST execute the complete baseline testing workflow**:
   - Execute ALL steps exactly as described in the canonical workflow document
   - Do NOT skip any steps (including notifications or test execution)
   - Do NOT substitute a shortened or summarized version
   - Follow the workflow exactly as documented using the configuration parameters from Step 1
   - For this documentation project, "smoke tests" means: verify workflow documents exist and are readable, check referenced paths are valid, validate markdown formatting, ensure cross-references work

---

**This wrapper demonstrates the thin wrapper pattern for other projects to follow.**
