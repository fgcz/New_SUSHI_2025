# Code Linting 

This document explains the current code quality tools and editor integration in the Sushi frontend project.

## Overview

The project uses a basic approach to code quality:

1. **Next.js ESLint** - Built-in linting with React and TypeScript rules
2. **TypeScript** - Type checking and compile-time error detection
3. **Coc.nvim** - Editor integration for real-time feedback (optional)

---

## ESLint Configuration

### Current Setup
- **Built-in Next.js ESLint**: Uses `eslint-config-next` package
- **Package.json script**: `npm run lint` 
- **No custom config file**: Relies on Next.js defaults

### What ESLint Checks
- **React rules**: Proper hooks usage, JSX best practices
- **Next.js rules**: Image optimization, Link usage, accessibility
- **Basic TypeScript**: Type-aware linting through Next.js integration
- **Import rules**: Prevents unused imports and basic ordering

### Manual Triggers
- ✅ **Manual only**: `npm run lint`
- ❌ **No automatic formatting** - no format scripts available
- ❌ **No pre-commit hooks** - no automated quality gates

---

## TypeScript Configuration

### Current Setup
- **Config file**: `tsconfig.json` (project root)
- **Next.js integration**: Built-in TypeScript support
- **Strict mode**: Enabled for better type safety

### What TypeScript Checks
- **Type safety**: Variable assignments, function parameters, return types
- **Import validation**: Ensures imported modules exist and have correct types
- **React props**: Validates component prop types and usage
- **Null safety**: Prevents null/undefined access errors

### Manual Triggers
- ✅ **Build time**: `npm run build` runs type checking
- ✅ **Development**: Next.js dev server shows type errors
- ❌ **No dedicated type-check script** - integrated with Next.js

---


