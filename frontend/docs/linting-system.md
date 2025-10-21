# Code Linting & Formatting System

This document explains how code linting and formatting works in the Sushi frontend project, covering both development environment setup and automated processes.

## Overview

The project uses a multi-layered approach to code quality:

1. **ESLint** - JavaScript/TypeScript linting and code quality rules
2. **Prettier** - Code formatting and style consistency
3. **TypeScript** - Type checking and compile-time error detection
4. **Coc.nvim** - Editor integration for real-time feedback
5. **Pre-commit hooks** - Automated checks before commits

---

## ESLint Configuration

### Location & Setup
- **Config file**: `.eslintrc.json` (project root)
- **Package.json scripts**: `npm run lint`, `npm run lint:fix`
- **Integration**: Works with Next.js, TypeScript, and React

### What ESLint Checks
- **Code quality**: Unused variables, unreachable code, potential bugs
- **Best practices**: Proper React hooks usage, accessibility rules
- **Style consistency**: Import order, naming conventions
- **TypeScript integration**: Type-aware rules and optimizations

### Automatic Triggers
- ✅ **On save** (if Coc.nvim is configured)
- ✅ **On commit** (via pre-commit hooks)
- ✅ **Manual**: `npm run lint`

---

## Prettier Configuration

### Location & Setup
- **Config file**: `.prettierrc` (project root)
- **Ignore file**: `.prettierignore`
- **Package.json scripts**: `npm run format`, `npm run format:check`

### What Prettier Formats
- **Indentation**: 2 spaces, consistent across all files
- **Quotes**: Single quotes for JS/TS, double quotes for JSX
- **Line length**: 80 characters max
- **Semicolons**: Always required
- **Trailing commas**: ES5 style (objects, arrays)

### Automatic Triggers
- ✅ **On save** (via Coc.nvim + coc-prettier)
- ✅ **On commit** (via pre-commit hooks)
- ✅ **Manual**: `npm run format`

---

## Coc.nvim Integration

### Configuration Location
- **Settings**: `~/.vim/coc-settings.json`
- **Extensions**: Installed via `:CocInstall`

### Installed Extensions
```json
{
  "coc.preferences.formatOnSave": true,
  "eslint.autoFixOnSave": true,
  "prettier.onlyUseLocalVersion": true,
  "typescript.suggest.autoImports": true
}
```

### Real-time Features
- **Error highlighting**: Red underlines for ESLint errors
- **Warning highlighting**: Yellow underlines for warnings
- **Auto-fix on save**: ESLint fixes applied automatically
- **Format on save**: Prettier formatting applied automatically
- **Type checking**: TypeScript errors shown in real-time

### Coc Commands
- **`:CocRestart`** - Restart language servers (fixes most issues)
- **`:CocList diagnostics`** - Show all project errors/warnings
- **`:CocList extensions`** - Manage installed extensions

---

## Development Workflow

### 1. **Real-time Feedback** (While Editing)
```
Type code → Coc.nvim shows errors → Fix issues → Continue coding
```

- **Red underlines**: ESLint errors (must fix)
- **Yellow underlines**: ESLint warnings (should fix)
- **TypeScript errors**: Type mismatches, missing imports

### 2. **On Save** (Automatic)
```
Save file → ESLint auto-fix → Prettier format → File saved clean
```

- Automatically fixes fixable ESLint issues
- Applies consistent Prettier formatting
- Updates imports and removes unused variables

### 3. **Pre-commit** (Git Hooks)
```
git commit → Run linting → Run formatting → Check types → Commit or block
```

- Prevents commits with linting errors
- Ensures all committed code is properly formatted
- Runs TypeScript type checking

### 4. **Manual Commands**
```bash
npm run lint          # Check for linting errors
npm run lint:fix      # Fix all fixable linting errors
npm run format        # Format all files with Prettier
npm run format:check  # Check if files are properly formatted
npm run type-check    # Run TypeScript compiler checking
```

---

## Error Types & Solutions

### ESLint Errors
- **Syntax errors**: Missing semicolons, brackets
- **Unused variables**: Variables declared but never used
- **React rules**: Missing dependencies in useEffect, incorrect hook usage
- **Import issues**: Unused imports, incorrect import paths

### TypeScript Errors
- **Type mismatches**: Assigning wrong types to variables
- **Missing properties**: Object properties that don't exist on type
- **Import errors**: Importing from non-existent modules
- **Generic constraints**: Incorrect generic type usage

### Prettier Conflicts
- **ESLint vs Prettier**: Rules that conflict between tools
- **Custom formatting**: Manual formatting that conflicts with Prettier
- **Line length**: Code that exceeds character limits

---

## Configuration Files

### `.eslintrc.json`
```json
{
  "extends": [
    "next/core-web-vitals",
    "@typescript-eslint/recommended"
  ],
  "rules": {
    "@typescript-eslint/no-unused-vars": "error",
    "react-hooks/exhaustive-deps": "warn"
  }
}
```

### `.prettierrc`
```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "printWidth": 80
}
```

### `coc-settings.json` (Vim)
```json
{
  "coc.preferences.formatOnSave": true,
  "eslint.autoFixOnSave": true,
  "eslint.format.enable": true,
  "prettier.onlyUseLocalVersion": true,
  "typescript.suggest.autoImports": true,
  "typescript.preferences.importModuleSpecifier": "relative"
}
```

---

## Troubleshooting

### Common Issues

#### 1. **ESLint Not Running**
```bash
# Check if ESLint is installed
npm list eslint

# Restart Coc.nvim
:CocRestart

# Check Coc status
:CocList diagnostics
```

#### 2. **Prettier Not Formatting**
```bash
# Check Prettier installation
npm list prettier

# Manual format
npm run format

# Check Coc Prettier extension
:CocList extensions
```

#### 3. **TypeScript Errors Not Showing**
```bash
# Check TypeScript installation
npm list typescript

# Manual type check
npm run type-check

# Restart TypeScript service
:CocCommand tsserver.restart
```

#### 4. **Coc.nvim Issues**
```bash
# View Coc logs
:CocOpenLog

# Check extension status
:CocList extensions

# Update extensions
:CocUpdate
```

---

## Best Practices

### 1. **Fix Issues Early**
- Address red underlines (errors) immediately
- Don't ignore yellow underlines (warnings)
- Use `:CocList diagnostics` to see all project issues

### 2. **Consistent Formatting**
- Let Prettier handle all formatting automatically
- Don't manually format code - it will be overwritten
- Trust the auto-formatting on save

### 3. **Type Safety**
- Fix TypeScript errors before committing
- Use proper types instead of `any`
- Add type annotations for complex functions

### 4. **Regular Maintenance**
```bash
# Weekly maintenance
npm run lint:fix        # Fix all auto-fixable issues
npm run format          # Ensure consistent formatting
npm run type-check      # Verify all types are correct
```

---

## Integration with Git

### Pre-commit Hooks
The project automatically runs linting and formatting checks before each commit:

1. **Lint staged files** - Only check files being committed
2. **Format staged files** - Apply Prettier to staged files
3. **Type check** - Ensure TypeScript compilation succeeds
4. **Block commit** - If any checks fail, commit is prevented

### Bypassing Checks (Not Recommended)
```bash
# Skip pre-commit hooks (emergency only)
git commit --no-verify -m "Emergency fix"
```

---

## Performance Notes

- **Incremental checking**: Only modified files are re-checked
- **Caching**: ESLint and TypeScript cache results for faster subsequent runs
- **Background processing**: Coc.nvim runs checks in background without blocking editing
- **Debouncing**: Checks are debounced to avoid excessive CPU usage while typing

This system ensures consistent, high-quality code across the entire project while providing immediate feedback to developers during the coding process.